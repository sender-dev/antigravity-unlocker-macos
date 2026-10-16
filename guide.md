# Antigravity Unlocker — guide

Один документ: что это, как поставить, как проверить, как откатить, как собрать,
что внутри и что осталось непроверенным.
Платформы: **Windows** (эталон), **Linux** (порт), **macOS** (этот порт).

Программа для Windows, Linux и macOS: позволяет аккаунту Google любой страны
(в том числе России) пользоваться Antigravity 2.0, Antigravity IDE и
Antigravity CLI. Настройка делается один раз для компьютера, после этого можно
входить с любыми аккаунтами. После обновления Antigravity анлокер патчит его
заново сам.

---

## 1. Что делает программа

1. **Патч клиента** — в бинарнике `language_server`/`agy` две строки одинаковой
   длины меняются местами (`ineligible` → `inexigible`) и `https_proxy` →
   `AG_LS_PROXY`. Размер файла не меняется, откат — обратная замена.
   На новых сборках (v2.4+) JS не патчится: авторизация ушла в Language Server.
2. **Локальный прокси** — `127.0.0.1:53129` (при занятости `43129…48129`).
   На него указывает **только** `AG_LS_PROXY`, который читает **только**
   пропатченный клиент. Системный `HTTPS_PROXY` не трогается: `git`, браузеры и
   всё остальное работают как раньше. TLS не расшифровывается, сертификаты не
   ставятся.
3. **Маршрут обхода ошибки 400** — соединения с двумя гейт-хостами Google
   (`cloudcode-pa.googleapis.com`, `daily-cloudcode-pa.googleapis.com`) идут
   через службу на вашем компьютере. Путь выбирается по тому, **на каком реально
   ответила модель**, а не по скорости; путь с ошибкой откладывается.
   Свой VPN настраивать не нужно (и мешать ему тоже не надо).
4. **DNS-слой (NRPT)** — только Windows. На macOS и Linux переключатели
   DNS-части ничего не поставят: там работают патч клиента и прокси-маршрут.

---

## 2. Установка на macOS

Нужно: macOS 11+, 64-бит (Apple silicon или Intel), установленный Antigravity и
бесплатный ключ из закрепа группы [t.me/nova_txt](https://t.me/nova_txt/69864)
(свой для каждой версии анлокера). `sudo` не нужен.

1. Возьмите `AG_<версия>_macos.tar.gz` из Releases (или соберите — раздел 6).
2. Распакуйте и снимите карантин:
   ```bash
   cd ~/Downloads
   tar -xzf AG_2.23.1_macos.tar.gz
   xattr -dr com.apple.quarantine ~/Downloads/AG_2.23.1_macos
   ```
3. Запустите: **двойной клик по `launch.command`**. Или из терминала:
   ```bash
   bash ~/Downloads/AG_2.23.1_macos/launch.command
   ```
   Finder отказывается («неопознанный разработчик») — правый клик по
   `launch.command` → **Открыть**, один раз. Запускать можно и с флешки: если
   оттуда нельзя исполнять, обёртка сама скопирует программу в
   `~/Library/Application Support/agunlocker/` и запустит оттуда.
   Без графического сеанса (SSH) программа сама идёт в терминальный режим;
   принудительно — `bash launch.command --tui` (`↑↓` выбор, `Пробел`/`Enter`
   включить-выключить, `o` отчёт, `q` выход).
4. Вставьте ключ: **правый клик в поле ключа → Вставить** (поле перед вставкой
   очищается).
5. Нажмите **«Включить всё»** — Antigravity на пару секунд закроется.
6. **Полностью закройте Antigravity (`Cmd+Q`)** и откройте заново, напишите
   что-нибудь в чат. Карточка вверху окна станет зелёной:
   «Работает. Модель ответила …».

Запускать от себя, не через `sudo`: под root программа искала бы Antigravity в
домашней папке root и поставила бы службу root'у. Она это проверяет и скажет.

Пароль администратора macOS спросит **сама** и только если Antigravity стоит в
`/Applications` и принадлежит другому пользователю — чтобы записать патч.

### Windows и Linux (для сравнения)

- Windows: exe от имени администратора, служба — задача планировщика в
  `%ProgramData%\AGUnlocker`, патч root-установки — окно UAC.
- Linux: `bash launch.sh`, `sudo` не нужен, служба — юниты `systemd --user`
  (`ag-unlocker-proxy`, `ag-unlocker-watchdog`), патч root-установки — `pkexec`.
- Терминальная версия без архива: `tui.sh` (Linux) / `tui.ps1` (Windows).

---

## 3. Что появляется в системе

| Что | Где на macOS |
|---|---|
| Патч клиента | файл `language_server`/`agy` внутри Antigravity |
| Откат патча | обратная замена тех же байт, копии не нужны, размер не меняется |
| Копии JS IDE | `main.js.ag_backup`, `extension.js.ag_backup`; у распакованного архива — `app.asar.bak` |
| Локальный прокси | `127.0.0.1:53129` (при занятости `43129…48129`) |
| Переменная | `AG_LS_PROXY` — читает только пропатченный клиент |
| Служба прокси | `~/Library/LaunchAgents/eu.nova-app.agunlocker.proxy.plist` |
| Автопатч после обновления | `~/Library/LaunchAgents/eu.nova-app.agunlocker.watchdog.plist` |
| Переменная сеанса | `~/Library/LaunchAgents/eu.nova-app.agunlocker.env.plist` + `launchctl setenv` |
| Копия для службы, логи | `~/Library/Application Support/agunlocker/` (`ag_proxy`, `launchd.log`, `forwarder.log`, `upstream.txt`, `proxy_port`) |
| Настройки IDE | `~/Library/Application Support/<nameShort>/User/settings.json` |

**Подпись кода.** macOS не запускает Mach-O, чья подпись разошлась с содержимым,
поэтому после каждой правки анлокер переподписывает файл ad-hoc
(`codesign --force --sign -`, entitlements сохраняются), а если файл лежит внутри
`.app` — переподписывает и **сам бандл** (подпись бандла скрепляет весь вложенный
код). Без этого изменённый бинарник убивался бы при запуске (`Killed: 9`), а
Antigravity считался бы повреждённым.

---

## 4. Проверка

```bash
launchctl list | grep agunlocker     # службы загружены (две строки)
launchctl getenv AG_LS_PROXY         # переменная выставлена и смотрит на наш порт
lsof -nP -iTCP:53129 -sTCP:LISTEN    # прокси слушает

# патч наложен: > 0 после патча, 0 до него
grep -ac inexigible "/Applications/Antigravity.app/Contents/Resources/app/extensions/antigravity/bin/"language_server*

codesign -vv "/Applications/Antigravity.app"   # ожидаемо: valid on disk
```

Проще всего — карточка в верхней части окна: она пишет, что включено, отвечала ли
модель и была ли ошибка 400 за последние 12 часов.

---

## 5. Выключение и откат

Переключатели в окне и есть откат: «Разблокировать вход в аккаунт» снимает патч с
бинарников (обратной заменой) и возвращает JS из копий; «Обход ошибки 400»
выгружает службу и снимает `AG_LS_PROXY`.

Вручную:

```bash
launchctl unload ~/Library/LaunchAgents/eu.nova-app.agunlocker.proxy.plist
launchctl unload ~/Library/LaunchAgents/eu.nova-app.agunlocker.watchdog.plist
rm ~/Library/LaunchAgents/eu.nova-app.agunlocker.{proxy,watchdog,env}.plist
launchctl unsetenv AG_LS_PROXY
```

После этого снести `~/Library/Application Support/agunlocker/`. Если патч не снят
переключателем — проще всего переустановить Antigravity.

---

## 6. Сборка

### macOS (на Mac)

```bash
xcode-select --install                 # SDK и линкеры
curl https://sh.rustup.rs -sSf | sh    # rustup
bash macos/build_macos.sh              # под архитектуру этого Mac
bash macos/build_macos.sh --universal  # arm64 + Intel одним файлом
bash macos/build_macos.sh --target x86_64-apple-darwin
```

Результат — `release/AG_<версия>_macos/` и `.tar.gz` (бинарник, `launch.command`,
README). Версия берётся из `Cargo.toml`, бинарник подписывается ad-hoc при сборке.

**Собрать macOS-версию с Linux нельзя**: `ring` и `webpki` компилируют C против
Apple SDK, а его на Linux нет (наблюдаемая ошибка:
`cc: unrecognized command-line option '-arch'`).

### Windows и Linux

`build_rust.py` собирает `.exe` (Windows, MSVC + `+crt-static`) и Linux-бандл через
WSL (`cargo zigbuild`, glibc 2.17+); macOS-бандл он добавляет, если сборка идёт на
Darwin, и пропускает с сообщением в остальных случаях.

---

## 7. Если не работает

| Симптом | Что делать |
|---|---|
| «Неопознанный разработчик» / «файл повреждён» | `xattr -dr com.apple.quarantine <папка>`; правый клик → **Открыть** |
| Antigravity не запускается после патча | переподпись бандла делается автоматически; если нет — `sudo codesign --force --deep --sign - "/Applications/Antigravity.app"` |
| Кнопка просит пароль | это нормально: установка принадлежит другому пользователю, окно просит доступ только на запись патча |
| Ошибка 400 осталась | закрыть Antigravity полностью (`Cmd+Q`) и открыть снова; проверить `launchctl getenv AG_LS_PROXY` и `lsof -iTCP:53129` |
| «Порт занят другой программой» | `lsof -nP -iTCP:53129 -sTCP:LISTEN` покажет кто; закрыть её или **«Починить»** |
| Оборвалось после смены сети или VPN | выключить VPN или сменить сервер, отправить сообщение ещё раз — обход сам переберёт пути |
| «Нужна верификация аккаунта», 401 | кнопка верификации в окне: страница Google откроется в браузере, где выполнен вход в тот же аккаунт |
| `503`, ошибок 400 нет | запрос дошёл до Google — обход тут ни при чём, попробуйте другую модель или позже |
| Ничего не помогло | карточка называет причину (антивирус, файрвол, другая программа) → **«Сохранить отчёт»** → файл на Рабочем столе → в группу |

---

## 8. Чего нет на macOS и Linux

- **DNS-слой (NRPT)** — только Windows (`Add-DnsClientNrptRule` и локальный релей
  на `:53`). На macOS/Linux `dns.rs` отвечает «не портирован».
- **Встроенные выходы** — приватные данные, в открытом коде отсутствуют (раздел
  10). С публичной сборкой доступен патч клиента и локальный прокси; готовый
  выход в разрешённом регионе подключается только в owner-сборке.
- **Gemini CLI** не поддерживается: Google закрыл в нём вход для личных
  аккаунтов, на стороне клиента это не обойти.

---

## 9. Как это устроено (для тех, кто читает код)

| Механизм | Windows | Linux | macOS |
|---|---|---|---|
| Патч бинарника | замена строки той же длины | то же | то же + ad-hoc переподпись файла и охватывающего `.app` |
| Служба | задача планировщика | `systemd --user` (`ag-unlocker-*.service`) | LaunchAgent (`.plist`), `launchctl load/unload/kickstart` |
| Переменная `AG_LS_PROXY` | User environment (PowerShell) | `environment.d` + `systemctl set-environment` | LaunchAgent `…env.plist` (`launchctl setenv`) + `launchctl setenv` |
| Права на root-установку | окно UAC | `pkexec` | `osascript … with administrator privileges` |
| Каталог состояния | `%ProgramData%\AGUnlocker` | `~/.local/share/agunlocker` | `~/Library/Application Support/agunlocker` |
| `resources` установки | `<root>/resources` | `<root>/resources` | `<app>.app/Contents/Resources` |
| Поиск установок | реестр + `%LOCALAPPDATA%` | `/opt`, `/usr/share`, `~/.local/share`, `~/.local/bin` | `/Applications/*.app`, `~/Applications`, `~/.local/bin`, `/opt/homebrew/bin` |
| Другой экземпляр окна | `tasklist`/`taskkill` | `/proc` + `kill` | `ps -Ao pid=,comm=,args=` + `kill` |
| ID машины | SMBIOS | `/sys/class/dmi/id/product_uuid`, `/etc/machine-id` | `ioreg` → `IOPlatformUUID` |
| Графический сеанс | всегда окно | `DISPLAY`/`WAYLAND_DISPLAY` | `XPC_SERVICE_NAME`/`SECURITYSESSIONID` |
| Открыть ссылку/папку, диалог | `ShellExecuteW`, MessageBox | `xdg-open`, zenity/kdialog | `open`, `open -R`, `osascript display dialog` |

Ключевые файлы: `patch_binary.rs` (пары замен, цели), `patch_ide.rs`/`asar.rs`
(JS и архив IDE), `proxy.rs` (локальный CONNECT-прокси, порты), `routes.rs`/
`egress.rs`/`upstream.rs` (выбор маршрута), `endpoint.rs` (переменная и настройки
клиента), `background.rs` (службы), `elevate.rs` (права), `watchdog.rs`
(автопатч), `instances.rs` (`resources_dir`, поиск установок), `dns*.rs` (DNS-слой,
Windows), `hwid.rs` (ID машины), `group*.rs`/`gate.rs` (ключ и группа).

Общая идея порта — точечно: платформенно-нейтральный код (asar, пары замен, TLS,
маршруты) не тронут; linux-ветки, которые действительно linux (`systemctl`,
`environment.d`, `pkexec`, `/proc`), сужены до
`cfg(all(not(windows), not(macos)))`, рядом добавлен macOS-аналог.

---

## 10. Ключ, группа и приватные данные

Ключ бесплатный, выдаётся в группе и **свой для каждой версии анлокера**: после
обновления нужен новый. Ключ привязан к машине (`gate.json` +
`/sys/class/dmi/id/product_uuid` на Linux, `IOPlatformUUID` на macOS).

В открытом коде нет только данных встроенных маршрутов (чтобы публичные серверы не
перегружались); остальное собирается из исходников. `build.rs` подключает их
только при наличии приватных файлов: `src/relay.rs` + `.relay_key` (и
`AG_WITH_RELAY=1`) и `src/exits.rs` + `.exits`. Публичная сборка компилируется с
`relay=false exits=false group=false` — это видно в выводе сборки.

---

## 11. Что проверено и что нет

**Проверено**

- `cargo check --bin ag_unlocker` — Linux: чисто.
- `cargo test --bin ag_unlocker` — Linux: **330 passed, 2 failed**.
- macOS-ветки типизированы и исполнены: копия дерева, где `target_os = "macos"`
  заменён на фичу-симулятор `macsim`, собирается и проходит
  `cargo test --features macsim` на Linux — **337 passed, 2 failed**.
  Что фича действительно включается, проверено временным `compile_error!` под
  `#[cfg(feature = "macsim")]`.
- Тесты на macOS-логику: plist LaunchAgent'а (метка, слоты argv, экранирование
  XML), путь агента, AppleScript-экранирование elevation (round-trip),
  распознавание `.app`-бандла и `Contents/Resources`, поиск охватывающего `.app`
  для переподписи.
- `bash macos/build_macos.sh` вне macOS корректно отказывается с объяснением;
  `build_rust.py` проходит разбор и его ветка пропуска macOS исполнена.

Два падения (`group_key::parse_key_errors`,
`resolvers::the_warm_path_re_probes_instead_of_trusting_what_it_knows`)
воспроизводятся и на исходном дереве: публичная сборка идёт без вшитых ключей
(раздел 10). Это не регрессия порта.

**Не проверено (нужен Mac)**

- Нативная сборка и запуск, реальный патч darwin-сборок Antigravity (сигнатуры в
  `language_server`/`agy`), поведение `codesign --preserve-metadata=entitlements`
  на конкретной сборке, работа LaunchAgent'ов в живом сеансе, откат на живой
  установке.
