Option Explicit

Const HiddenWindow = 0
Const WaitForCollector = True

Dim windowsShell, fileSystem, scriptDirectory, powershellPath, collectorScriptPath
Dim collectorCommand, collectorExitCode
Set windowsShell = CreateObject("WScript.Shell")
Set fileSystem = CreateObject("Scripting.FileSystemObject")
scriptDirectory = fileSystem.GetParentFolderName(WScript.ScriptFullName)
powershellPath = windowsShell.ExpandEnvironmentStrings("%SystemRoot%") & _
    "\System32\WindowsPowerShell\v1.0\powershell.exe"
collectorScriptPath = fileSystem.BuildPath(scriptDirectory, "RefreshQuota.ps1")

collectorCommand = QuoteArgument(powershellPath) & _
    " -NoProfile -NonInteractive -ExecutionPolicy Bypass -File " & QuoteArgument(collectorScriptPath)
collectorExitCode = windowsShell.Run(collectorCommand, HiddenWindow, WaitForCollector)
WScript.Quit collectorExitCode

Function QuoteArgument(argument)
    QuoteArgument = Chr(34) & argument & Chr(34)
End Function
