@echo off
setlocal
set "SCRIPT=%~dp0ethershell.ps1"
set "PWSH=%ProgramFiles%\PowerShell\7\pwsh.exe"

if not exist "%SCRIPT%" (
    echo [ERROR] ethershell.ps1 was not found next to this launcher.
    echo Expected: "%SCRIPT%"
    pause
    exit /b 1
)

if not exist "%PWSH%" (
    echo [ERROR] PowerShell 7 was not found.
    echo Expected: "%PWSH%"
    echo.
    echo Install it with:
    echo winget install --id Microsoft.PowerShell --source winget
    pause
    exit /b 1
)

"%PWSH%" -NoLogo -NoProfile -ExecutionPolicy Bypass -Command ^
  "$p='%PWSH%'; $s='%SCRIPT%'; try { Start-Process -FilePath $p -Verb RunAs -WorkingDirectory '%~dp0' -ArgumentList @('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',('""{0}""' -f $s)) -ErrorAction Stop } catch { Write-Host ('[ERROR] ' + $_.Exception.Message) -ForegroundColor Red; Read-Host 'Press ENTER to close' }"

if errorlevel 1 (
    echo.
    echo [ERROR] EtherShell could not be launched.
    pause
)
