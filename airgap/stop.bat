@echo off
REM ============================================================================
REM  Open Notebook - STOP  (shuts down all 4 services)
REM ============================================================================
setlocal EnableExtensions
echo Stopping Open Notebook services...

REM Close the named service windows started by 3-run.bat
taskkill /F /FI "WINDOWTITLE eq ONB SurrealDB*" >nul 2>nul
taskkill /F /FI "WINDOWTITLE eq ONB API*"       >nul 2>nul
taskkill /F /FI "WINDOWTITLE eq ONB Worker*"    >nul 2>nul
taskkill /F /FI "WINDOWTITLE eq ONB Frontend*"  >nul 2>nul

REM Safety net: kill by image + command line (PowerShell, works on Win11)
taskkill /F /IM surreal.exe >nul 2>nul
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "Get-CimInstance Win32_Process | Where-Object { ($_.Name -in 'python.exe','node.exe') -and ($_.CommandLine -match 'run_api|surreal_commands|next') } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }"

echo Done.
endlocal & exit /b 0
