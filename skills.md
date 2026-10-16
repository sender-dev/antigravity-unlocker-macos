---
name: antigravity-unlocker-macos
description: Build, operate, port or debug the Antigravity Unlocker on macOS (Rust, `ag_unlocker`, Windows/Linux/macOS platform split). Use when the task involves the Antigravity Unlocker source tree, its macOS bundle, patching Antigravity's language server, launchd LaunchAgents for the local proxy, osascript elevation, code-signature repair after patching, or verifying macOS code paths on a host without a Mac.
---

# Antigravity Unlocker on macOS

Порт `ag_unlocker` (Rust, один бинарь: патчер + локальный прокси + окно egui и
терминальный TUI) на macOS. Полный пользовательский и инженерный разбор —
`guide.md` в корне репозитория; читать его при вопросах «как поставить /
откатить / что меняется в системе».

## Разделить задачу

| Задача | Где работать |
|---|---|
| Поставить, включить, откатить на Mac | `guide.md`, разделы 2–5 |
| Собрать бандл | `macos/build_macos.sh` на самом Mac (кросс-сборка невозможна) |
| Изменить/добавить macOS-поведение | `src/`, ветки `cfg(target_os = "macos")` |
| Портировать ещё одну платформу | таблица соответствий в `guide.md`, раздел 9 |
| Разобрать, что делает бинарь | REA-скилл `reverse-engineer-anything` |

## Правила, добытые на этом порте

Соблюдать при любой правке macOS-веток — это не стилистика, а поломки, которые
уже случались:

1. **Платформенные ветки не «не-windows».** `#[cfg(not(target_os = "windows"))]`
   в этом дереве означает **linux**. Linux-специфику (`systemctl`,
   `environment.d`, `pkexec`, `/proc`, `xdg-open`) сужать до
   `cfg(all(not(target_os = "windows"), not(target_os = "macos")))` и рядом
   добавлять macOS-аналог. Нейтральный код (asar, пары замен, TLS, маршруты) не
   трогать.
2. **После любой правки Mach-O — переподпись.** Изменённый байт ломает подпись,
   macOS убивает процесс при запуске (`Killed: 9`). Порядок: сначала вложенный
   бинарник (`codesign --force --sign - --preserve-metadata=entitlements`), потом
   охватывающий `.app` (без `--preserve-metadata`, он там отвергается). Реализация
   — `patch_binary::resign_after_patch`.
3. **`resources` в бандле лежит глубже.** `<app>.app/Contents/Resources` вместо
   `<root>/resources`. Не собирать путь руками — только
   `instances::resources_dir()`, иначе патч молча не находит файлы и отвечает
   «сигнатура не найдена».
4. **Служба — LaunchAgent, а не демон.** `~/Library/LaunchAgents/<label>.plist`,
   `RunAtLoad` (замена `enable`), `KeepAlive` (замена `Restart=on-failure`),
   управление `launchctl load/unload`, перезапуск `kickstart -k gui/<uid>/<label>`.
   Метка обязана совпадать с именем файла, иначе переключатель читается «выкл».
5. **Переменную для GUI-приложения задаёт launchd.** Никакой `environment.d` на
   macOS не читается: нужен `launchctl setenv` (живой сеанс) + агент с
   `RunAtLoad`, чтобы пережило перезагрузку. `launch.command` — обёртка Finder'а:
   PATH, карантин, копирование в data-dir, если запускать оттуда нельзя.
6. **Права.** `sudo` не нужен ни на запуск, ни на службы. Только запись в чужую
   установку идёт через `osascript … with administrator privileges`; команда
   собирается в два слоя экранирования (shell, затем AppleScript) — правя её,
   проверяй round-trip, а не сырую строку.

## Проверка macOS-кода без Mac

Кросс-компиляция на darwin с Linux невозможна (`ring`/`webpki` линкуют C против
Apple SDK). Рабочая замена — включить macOS-ветки фичей на Linux-хосте:

```bash
# 1. копия дерева, где cfg(target_os = "macos") → cfg(feature = "macsim")
# 2. в Cargo.toml: [features] macsim = []
cargo check --bin ag_unlocker --features macsim
cargo test  --bin ag_unlocker --features macsim
```

- Шаг 1 обязательно **пересоздавать копию целиком** перед каждой проверкой: иначе
  проверяешь устаревший снимок (уже случалось).
- Убедиться, что фича реально включилась: временный `compile_error!` под
  `#[cfg(feature = "macsim")]` должен сработать.
- Ждать: два пре-существующих падения (`group_key::parse_key_errors`,
  `resolvers::the_warm_path…`) — не регрессия, они падают и на чистом дереве
  (публичная сборка без вшитых ключей).
- Эта же проверка ловит ошибку, которую Linux-сборка не видит: `cfg`-ветка,
  текстовая вложенность модулей, дубликаты функций. Обязательно прогонять её
  после любой правки `#[cfg]`, даже «косметической».

## Сборка

```bash
bash macos/build_macos.sh                 # архитектура хоста
bash macos/build_macos.sh --universal     # arm64 + x86_64, lipo
```

Артефакт — `release/AG_<версия>_macos/` + `.tar.gz` (бинарь, `launch.command`,
`guide.md` как README). Версия — из `Cargo.toml`, `AG_FULL_VERSION` пробрасывается
в build.rs. Бандл подписывается ad-hoc на выходе.

## Не делать

- Не вызывать `sudo` для запуска, служб и per-user файлов.
- Не заявлять, что macOS-пакет проверен на Mac, если прогонялась только
  `macsim`-проверка: нативную сборку, реальные сигнатуры darwin-сборок Antigravity
  и живой сеанс launchd она не покрывает.
- Не «чинить» DNS-слой на macOS: NRPT — только Windows, на остальных платформах
  задумано «не портирован».
- Не трогать приватные маршруты: `src/relay.rs`+`.relay_key` и
  `src/exits.rs`+`.exits` — owner-only, в публичном дереве их нет и быть не должно.
- Не менять Linux-ветки, чтобы «упростить»: они работают и проверены.
