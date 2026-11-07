# Lumen Installer для Windows

Нативный клиент для Windows 10/11 на C# WPF и .NET 8. Он повторяет клиент для macOS (`macos/`): те же шаги (Подготовка → Проектор → Система → Сервисы Google →
Установка), то же обслуживание и то же оформление «ночное небо» с логотипом Lumen OS.

Сам на проектор клиент ничего не пишет. Он запускает официальный `installer\lumen-install.ps1` командой
`powershell.exe -NoProfile -ExecutionPolicy Bypass -File …` и показывает его диалог в окнах. Подпись, контрольные
суммы и разрешённые разделы проверяет скрипт.

## Что умеет

- **Поиск проектора.** По USB, Wi‑Fi (`adb connect`, mDNS) и в режиме fastboot. Модель определяется по
  `ro.boot.xgimi.modelname`, затем по плате, по fastboot product и по префиксу серийного номера. Её можно определить
  и по серийному номеру с наклейки или выбрать вручную.
- **Проверка подключения.** «Начать установку» и все команды, которые обращаются к проектору, доступны только
  когда проектор действительно подключён. Предупреждения недостаточно.
- **Релизы с GitHub.** Сгруппированы по моделям, скачиваются в `%USERPROFILE%\Lumen Installer\releases\<tag>`. Можно
  указать уже распакованную папку релиза.
- **Сервисы Google.** Берётся единственный допустимый MindTheGapps из `lib\*gapps_allow.txt`: скачивается с
  официального адреса или выбирается свой файл, затем проверяется sha256. План зависит от модели:
  - **XGIMI Play 6:** за один проход с системой (`-GappsZip`), потому что раздел заполняется на самом проекторе;
  - **XGIMI Z9X:** сразу после установки вторым шагом (`gapps -Zip`), клиент запускает его сам. Для одного прохода
    нужны erofs-utils, а для Windows их в установщике пока нет;
  - **XGIMI Z9X HB:** недоступно. erofs-utils нужны ему и для отдельного `gapps`.

  Если в установщике появится `tools\erofs-utils\windows-x64`, клиент сам переключится на установку за один проход.
- **Вопросы установщика.** «да/нет» выводятся кнопками. `ERASE` и `WRITE` нужно впечатать самому, иначе кнопка не
  включится. Закрыть окно без ответа означает ответить «нет».
- **Шкала шагов.** Строится по state-файлу установщика (`%USERPROFILE%\.lumen-installer`). Для пропущенных шагов
  написано, почему они пропущены. Журнал можно скопировать.
- **Обслуживание.** `check`, `verify`, `gapps` (состояние), `status`.
- **Языки.** Русский, английский и китайский (упрощённый). Переключатель на первом экране и в боковой панели, по
  умолчанию берётся язык системы. Установщик знает только русский и английский, поэтому при китайском интерфейсе он
  запускается с `-Lang en`.
- **adb и fastboot.** Google Platform-Tools той же версии и с тем же sha256, что прописаны в `lumen-install.ps1`.
  Кладутся в `%LOCALAPPDATA%\Lumen Installer`, работают на собственном порту установщика 5038. `ADB_SERVER_SOCKET`
  убирается из окружения.

Демо-проектора в версии для Windows нет: он есть только в сборке для разработчиков на macOS.

## Сборка

На Windows с установленным [.NET 8 SDK](https://dotnet.microsoft.com/download/dotnet/8.0):

```powershell
powershell -File scripts\get_installer.ps1
cd windows\LumenInstaller
dotnet run
dotnet publish -c Release -r win-x64 --self-contained false -o ..\publish
```

Получится `..\publish\LumenInstaller.exe`, рядом с ним папка `installer\` (из `vendor\lumen-os\installer`, которую
подтягивает `scripts\get_installer.ps1`; другой путь задаёт `-p:LumenOsInstaller=ПАПКА`). Для
запуска нужен .NET 8 Desktop Runtime. Чтобы exe работал без него, используйте `--self-contained true` (около 150 МБ).

Собрать на macOS или Linux тоже можно, но не запустить:

```bash
dotnet build -p:EnableWindowsTargeting=true
```

## Структура

```
LumenInstaller/
  Core/       Paths, Proc, Profiles, PlatformTools, Detector, Net, Releases, Gapps, InstallerRunner,
              Loc + Strings (тексты на трёх языках), RelayCommand
  Views/      PromptWindow (вопросы установщика), NavItem, конвертеры
  MainViewModel.cs, MainWindow.xaml, App.xaml (цвета и стили)
  Assets/     logo.png и app.ico из assets/lumen_logo.png
```

## Не проверено

Клиент собран на macOS, на Windows он не запускался. Главный риск: вопросы установщика через перенаправленный
stdin. `Read-Host` в Windows PowerShell 5.1 при перенаправленном вводе обычно читает строку из stdin, а приглашение
выводит в stdout без перевода строки. Клиент ловит такую незавершённую строку: «[yes/no]: », «[да/нет]: »,
«Type ERASE…», «Введите ERASE…». Это нужно проверить на настоящем Windows до первой установки на проектор, например
командой `check`, которая ничего не пишет. Если `Read-Host` не читает stdin, придётся запускать скрипт через
обёртку, которая подменяет `Read-Host`.
