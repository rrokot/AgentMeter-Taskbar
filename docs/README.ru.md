# AgentMeter Taskbar

Панель задач Windows с лимитами Claude Code и Codex. У каждого сервиса видны две полосы для пятичасового и недельного периода. При наведении появляются проценты и время до сброса.

[English documentation](../README.md)

## Установка

Нужны Windows 11 x64 и StartAllBack с включённой классической панелью задач.

1. Скачай `AgentMeter-Taskbar-Setup-v*.exe` из [GitHub Releases](https://github.com/rrokot/AgentMeter-Taskbar/releases/latest).
2. Запусти мастер установки. Windows может показать **«Неизвестный издатель»** при первом запуске. Мастер также обновляет прежнюю установку из ZIP.
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

Автообновления включены по умолчанию. AgentMeter проверяет GitHub при входе в Windows и раз в сутки, сверяет подпись релиза и контрольную сумму установщика, затем устанавливает новую версию в фоне. Новая DLL загрузится при следующем запуске Проводника. Для ручной проверки открой **Пуск → AgentMeter Taskbar → Check for updates**. Настройку автообновлений можно изменить повторным запуском мастера.

Для удаления открой **Параметры → Приложения → Установленные приложения → AgentMeter Taskbar**. Если добавлял AgentMeter в Claude Code, удали соответствующую настройку строки состояния. Проводник освободит загруженную DLL после завершения процесса.

Тесты запускаются в Windows PowerShell 5.1 с Pester 3.4. Данные тестов локальны.

```powershell
powershell.exe -NoProfile -Command "Invoke-Pester .\tests -EnableExit"
```

AgentMeter Taskbar распространяется под [лицензией MIT](../LICENSE). Уведомление о лицензии исходного AgentMeter включено в [NOTICE-AgentMeter.txt](../NOTICE-AgentMeter.txt).
