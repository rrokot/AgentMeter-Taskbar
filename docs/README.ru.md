# AgentMeter Taskbar

Панель задач Windows с лимитами Claude Code и Codex. У каждого сервиса видны две полосы для пятичасового и недельного периода. При наведении появляются проценты и время до сброса.

[English documentation](../README.md)

## Установка

Нужны Windows 11 x64 и StartAllBack с включённой классической панелью задач. Установщик работает в 64-битном Windows PowerShell и компилирует панель средствами .NET Framework.

1. Распакуй ZIP из [GitHub Releases](https://github.com/rrokot/AgentMeter-Taskbar/releases/latest) и открой Windows PowerShell в распакованной папке.
2. Запусти установщик. Параметр `ExecutionPolicy` применяется к запущенному процессу PowerShell.

   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1
   ```

3. Щёлкни правой кнопкой по панели задач и выбери **Панели инструментов → AgentMeter Quotas**. Если пункта пока нет, выйди из Windows и войди снова.

Codex появится, когда локальный сеанс Codex CLI запишет свои лимиты. Сборщик ищет свежую запись в `CODEX_HOME` или `%USERPROFILE%\.codex`.

### Настройка Claude Code

Claude Code передаёт доступные лимиты для поддерживаемых подписок через [команду строки состояния](https://code.claude.com/docs/en/statusline#rate-limit-usage). Данные появляются после первого ответа в сеансе.

Выполни команду в Windows PowerShell, чтобы получить настройку с путём к установленному скрипту:

```powershell
$scriptPath = (Join-Path $env:LOCALAPPDATA 'AgentMeterTaskbar\ClaudeStatusLine.ps1').Replace('\', '/')
$command = 'powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + $scriptPath + '"'
@{ statusLine = @{ type = 'command'; command = $command } } | ConvertTo-Json -Depth 3
```

Добавь поле `statusLine` в `%USERPROFILE%\.claude\settings.json` или в файл настроек в `CLAUDE_CONFIG_DIR`. Сохрани остальные настройки. Если строка состояния уже настроена, можно передавать тот же JSON в скрипт AgentMeter с флагом `-Quiet` из своей команды.

Выполни один запрос в Claude Code. Панель обновит данные в течение минуты. Последнее значение видно до времени сброса. Если время сброса отсутствует, значение видно 15 минут с обновления строки состояния.

## Обновление и удаление

Для обновления запусти `Install.ps1` из нового релиза и перезапусти Проводник Windows или выйди из Windows и войди снова.

Для удаления отключи **AgentMeter Quotas** в меню панели задач. Если добавлял AgentMeter в Claude Code, удали соответствующую настройку строки состояния. Затем выполни команду:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Uninstall.ps1
```

Если Проводник ещё держит DLL открытой, выйди из Windows и войди снова, затем повтори удаление.

Тесты запускаются в Windows PowerShell 5.1 с Pester 3.4. Данные тестов локальны.

```powershell
powershell.exe -NoProfile -Command "Invoke-Pester .\tests -EnableExit"
```

AgentMeter Taskbar распространяется под [лицензией MIT](../LICENSE). Уведомление о лицензии исходного AgentMeter включено в [NOTICE-AgentMeter.txt](../NOTICE-AgentMeter.txt).
