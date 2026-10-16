//! One window at a time: a newer copy closes the older ones when it starts.
//!
//! Two windows of different versions share one settings file, one service and
//! one set of switches, and each re-applies its own idea of them on every
//! refresh - an older one put its relay and route state back under the newer
//! one, and the model did not answer until the old window was closed by hand
//! (field report, 2026-10-15). Only *windows* are matched: the services run
//! under other names (`ag_dns.exe` on Windows, `ag_proxy` on Linux and macOS) and
//! carry a flag, and the elevation helper carries one too, so none of them is
//! touched.

use std::path::{Path, PathBuf};

/// The `resources` directory of an install, wherever the platform puts it.
///
/// Everything the patch rewrites hangs off this one directory: the binaries under
/// `bin/`, the IDE's `app/out/main.js` and its extension. Windows and Linux keep
/// it directly under the install root; macOS keeps it one level down, at
/// `Contents/Resources` inside the `.app` bundle. Both spellings are checked
/// rather than assuming the volume folds case - a case-sensitive APFS volume and
/// a bundle unpacked by hand both exist, and picking the wrong path does not fail
/// loudly, it finds no binaries and reports "signature not found".
///
/// The conventional path is returned when neither exists, so a caller that
/// prints it names something a user would recognise.
pub fn resources_dir(inst: &Path) -> PathBuf {
    let plain = inst.join("resources");
    if plain.is_dir() {
        return plain;
    }
    let bundled = inst.join("Contents").join("Resources");
    if bundled.is_dir() {
        return bundled;
    }
    plain
}

/// Whether a process image name is a copy of the unlocker window: the exe this
/// one runs as, or any other release of it (`AG_<version>.exe` on Windows).
fn is_window_name(name: &str, own: &str) -> bool {
    let lower = name.to_ascii_lowercase();
    if lower == own.to_ascii_lowercase() {
        return true;
    }
    lower
        .strip_prefix("ag_")
        .and_then(|rest| rest.strip_suffix(".exe"))
        .is_some_and(|ver| ver.chars().next().is_some_and(|c| c.is_ascii_digit()))
}

/// Flags that make a process a service or helper, never a window.
fn is_service_args(args: &[String]) -> bool {
    args.iter().any(|a| {
        matches!(
            a.as_str(),
            "--dns-forwarder" | "--watchdog" | "--proxy" | "--patch-root" | "--unpatch-root"
        )
    })
}

/// Closes every other copy of the window. Best effort and silent: a copy that
/// refuses to die (another user's, a higher integrity level) is left running.
pub fn close_others() {
    let Ok(me) = std::env::current_exe() else {
        return;
    };
    let own = me
        .file_name()
        .map(|n| n.to_string_lossy().to_string())
        .unwrap_or_default();
    platform::close_others(&own);
}

#[cfg(target_os = "windows")]
mod platform {
    use std::process::Command;

    use super::is_window_name;

    pub fn close_others(own: &str) {
        let mut cmd = Command::new("tasklist");
        cmd.args(["/FO", "CSV", "/NH"]);
        let Ok(out) = crate::utils::no_window(&mut cmd).output() else {
            return;
        };
        let me = std::process::id();
        for line in String::from_utf8_lossy(&out.stdout).lines() {
            let mut cols = line.split("\",\"").map(|c| c.trim_matches('"'));
            let (Some(name), Some(pid)) = (cols.next(), cols.next()) else {
                continue;
            };
            let Ok(pid) = pid.parse::<u32>() else {
                continue;
            };
            if pid == me || !is_window_name(name, own) {
                continue;
            }
            let mut kill = Command::new("taskkill");
            kill.args(["/F", "/PID", &pid.to_string()]);
            let _ = crate::utils::no_window(&mut kill).output();
        }
    }
}

/// macOS: `ps` rather than `/proc`, which does not exist here. The command
/// line is read from `ps -Ao pid=,comm=,args=`, and the same two rules apply -
/// `is_window_name` for the image, `is_service_args` to skip the services and
/// the root helper - so only other windows are asked to quit. `comm` on macOS
/// is the full executable path inside a bundle (`.app/Contents/MacOS/<name>`),
/// which is why the name is taken from the last path component.
#[cfg(target_os = "macos")]
mod platform {
    use super::{is_service_args, is_window_name};
    use std::process::Command;

    pub fn close_others(own: &str) {
        let Ok(out) = Command::new("ps")
            .args(["-Ao", "pid=,comm=,args="])
            .output()
        else {
            return;
        };
        let text = String::from_utf8_lossy(&out.stdout);
        let me = std::process::id();
        for line in text.lines() {
            let line = line.trim_start();
            let mut fields = line.splitn(3, char::is_whitespace);
            let Some(pid) = fields.next().and_then(|p| p.parse::<u32>().ok()) else {
                continue;
            };
            if pid == me {
                continue;
            }
            let Some(comm) = fields.next() else {
                continue;
            };
            let name = comm.rsplit('/').next().unwrap_or(comm);
            if !is_window_name(name, own) {
                continue;
            }
            let args: Vec<String> = fields
                .next()
                .map(|a| a.split_whitespace().map(str::to_string).collect())
                .unwrap_or_default();
            if is_service_args(&args) {
                continue;
            }
            let _ = Command::new("kill").arg("-TERM").arg(pid.to_string()).output();
        }
    }
}

#[cfg(all(not(target_os = "windows"), not(target_os = "macos")))]
mod platform {
    use super::{is_service_args, is_window_name};

    pub fn close_others(own: &str) {
        let Ok(dir) = std::fs::read_dir("/proc") else {
            return;
        };
        let me = std::process::id();
        for entry in dir.flatten() {
            let Some(pid) = entry
                .file_name()
                .to_str()
                .and_then(|n| n.parse::<u32>().ok())
            else {
                continue;
            };
            if pid == me {
                continue;
            }
            let base = entry.path();
            // `comm` is cut at 15 bytes; the exe link is the whole name.
            let Some(name) = std::fs::read_link(base.join("exe"))
                .ok()
                .and_then(|p| p.file_name().map(|n| n.to_string_lossy().to_string()))
            else {
                continue;
            };
            if !is_window_name(&name, own) {
                continue;
            }
            let args: Vec<String> = std::fs::read(base.join("cmdline"))
                .map(|raw| {
                    raw.split(|b| *b == 0)
                        .map(|a| String::from_utf8_lossy(a).to_string())
                        .collect()
                })
                .unwrap_or_default();
            if is_service_args(&args) {
                continue;
            }
            // The `kill` tool, not libc: one signal does not earn an `unsafe` block.
            let _ = std::process::Command::new("kill")
                .arg("-TERM")
                .arg(pid.to_string())
                .output();
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn other_releases_of_the_window_are_windows_and_the_services_are_not() {
        assert!(is_window_name("AG_2.22.0.exe", "AG_2.23.1.exe"));
        assert!(is_window_name("AG_2.23.1.exe", "AG_2.23.1.exe"));
        assert!(is_window_name("ag_unlocker", "ag_unlocker"));
        assert!(!is_window_name("ag_dns.exe", "AG_2.23.1.exe"));
        assert!(!is_window_name("ag_proxy", "ag_unlocker"));
        assert!(!is_window_name("Antigravity.exe", "AG_2.23.1.exe"));
    }

    #[test]
    fn a_flagged_process_is_a_service() {
        let a = |v: &[&str]| v.iter().map(|s| s.to_string()).collect::<Vec<_>>();
        assert!(is_service_args(&a(&["ag", "--proxy"])));
        assert!(is_service_args(&a(&["ag", "--unpatch-root", "/opt/x"])));
        assert!(!is_service_args(&a(&["ag"])));
    }
}
