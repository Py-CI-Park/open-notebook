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

echo [3/3] Writing starter .env (if absent)...
if not exist "%ROOT%\app\.env" (
  > "%ROOT%\app\.env" echo # Open Notebook - air-gapped config
  >>"%ROOT%\app\.env" echo OPEN_NOTEBOOK_ENCRYPTION_KEY=CHANGE-ME-to-a-secret-string-min-16
  >>"%ROOT%\app\.env" echo.
  >>"%ROOT%\app\.env" echo # Database ^(native Windows MUST use 127.0.0.1, not localhost^)
  >>"%ROOT%\app\.env" echo SURREAL_URL=ws://127.0.0.1:8000/rpc
  >>"%ROOT%\app\.env" echo SURREAL_USER=root
  >>"%ROOT%\app\.env" echo SURREAL_PASSWORD=root
  >>"%ROOT%\app\.env" echo SURREAL_NAMESPACE=open_notebook
  >>"%ROOT%\app\.env" echo SURREAL_DATABASE=open_notebook
  >>"%ROOT%\app\.env" echo.
  >>"%ROOT%\app\.env" echo # API
  >>"%ROOT%\app\.env" echo API_HOST=127.0.0.1
  >>"%ROOT%\app\.env" echo API_PORT=5055
  >>"%ROOT%\app\.env" echo API_RELOAD=false
  >>"%ROOT%\app\.env" echo.
  >>"%ROOT%\app\.env" echo # On-prem AI endpoint ^(example: Ollama on the LAN^)
  >>"%ROOT%\app\.env" echo # OLLAMA_BASE_URL=http://10.0.0.10:11434
  echo     - created app\.env  ^(EDIT the encryption key + AI endpoint!^)
) else (
  echo     - app\.env already exists, leaving it untouched
)

echo.
echo ============================================================================
echo  INSTALL COMPLETE.
echo  1) Edit  %ROOT%\app\.env   ^(set encryption key + on-prem AI endpoint^)
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
