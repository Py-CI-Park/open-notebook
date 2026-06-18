@echo off
REM ============================================================================
REM  Open Notebook - [2] AIRGAP INSTALL  (run ONCE on the CLOSED network PC)
REM ----------------------------------------------------------------------------
REM  Place this whole bundle folder wherever you want it to live, e.g.
REM      D:\Chanil_Park\Project\Programming\AeroOne\
REM  then double-click this file. It rebuilds the Python venv fully OFFLINE
REM  from the bundled cache, creates data folders and a starter .env.
REM  No internet, no Docker, nothing pre-installed required.
REM ============================================================================
setlocal EnableExtensions
set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"

set "OLLAMA_HOST=127.0.0.1"
if /I "%~1"=="--ollama-host" if not "%~2"=="" set "OLLAMA_HOST=%~2"

set "UV=%ROOT%\tools\uv.exe"
set "PATH=%ROOT%\tools\node;%PATH%"
set "UV_PYTHON_INSTALL_DIR=%ROOT%\uv-python"
set "UV_CACHE_DIR=%ROOT%\uv-cache"
set "UV_OFFLINE=1"

echo.
echo === Open Notebook offline install ===
echo Location: %ROOT%
echo.

if not exist "%UV%" (echo [ERR] bundle incomplete: tools\uv.exe missing & goto :fail)
if not exist "%ROOT%\app\pyproject.toml" (echo [ERR] bundle incomplete: app\ missing & goto :fail)

echo [1/3] Creating data folders...
mkdir "%ROOT%\data\surrealdb" 2>nul
mkdir "%ROOT%\data\uploads"   2>nul
mkdir "%ROOT%\data\sqlite-db" 2>nul

echo [2/3] Building Python environment OFFLINE (from bundled cache)...
pushd "%ROOT%\app"
"%UV%" sync --frozen --offline
if errorlevel 1 (echo [ERR] offline uv sync failed & popd & goto :fail)
popd

echo [3/3] Writing auto-configured .env (if absent)...
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\write_env.ps1" -AppDir "%ROOT%\app" -OllamaHost "%OLLAMA_HOST%"
if errorlevel 1 (echo [ERR] .env generation failed & goto :fail)

echo.
echo ============================================================================
echo  INSTALL COMPLETE.
echo  .env auto-configured ^(encryption key + OLLAMA_BASE_URL + CORS_ORIGINS^). Models auto-register on 3-run.bat.
echo  2) Run   3-run.bat         to start all services
echo ============================================================================
echo.
pause
endlocal & exit /b 0

:fail
echo.
echo *** INSTALL FAILED *** (see error above)
echo.
pause
endlocal & exit /b 1
