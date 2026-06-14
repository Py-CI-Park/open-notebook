@echo off
REM ============================================================================
REM  Open Notebook - [3] RUN  (run on the CLOSED network PC, every time)
REM ----------------------------------------------------------------------------
REM  Starts all 4 services in separate windows, fully offline:
REM    SurrealDB(8000) -> API(5055) -> Worker -> Frontend(8502)
REM  Open http://127.0.0.1:8502 once the Frontend window says "Ready".
REM ============================================================================
setlocal EnableExtensions
set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"

REM ---- self-contained environment (children inherit this) -------------------
set "UV=%ROOT%\tools\uv.exe"
set "PATH=%ROOT%\tools\node;%ROOT%\tools\ffmpeg\bin;%ROOT%\tools;%PATH%"
set "UV_PYTHON_INSTALL_DIR=%ROOT%\uv-python"
set "UV_CACHE_DIR=%ROOT%\uv-cache"
set "UV_OFFLINE=1"
set "DATA_FOLDER=%ROOT%\data"
set "TIKTOKEN_CACHE_DIR=%ROOT%\tiktoken-cache"
set "PYTHONPATH=%ROOT%\app"

if not exist "%ROOT%\app\.venv" (echo [ERR] not installed yet - run 2-airgap-install.bat first & pause & goto :eof)

echo Starting Open Notebook services...
echo   data: %DATA_FOLDER%
echo.

REM ---- 1) SurrealDB ---------------------------------------------------------
start "ONB SurrealDB" cmd /k "cd /d "%ROOT%" && tools\surreal.exe start --user root --pass root rocksdb:data\surrealdb\onb.db"
echo   [1/4] SurrealDB launching... (port 8000)
timeout /t 6 /nobreak >nul

REM ---- 2) API (runs DB migrations on startup) -------------------------------
start "ONB API" cmd /k "cd /d "%ROOT%\app" && "%UV%" run --env-file .env python run_api.py"
echo   [2/4] API launching... (port 5055)
timeout /t 6 /nobreak >nul

REM ---- 3) Worker (background jobs: embeddings, podcasts, ...) ---------------
start "ONB Worker" cmd /k "cd /d "%ROOT%\app" && "%UV%" run --env-file .env python -m surreal_commands.cli.worker --import-modules commands"
echo   [3/4] Worker launching...
timeout /t 3 /nobreak >nul

REM ---- 4) Frontend ----------------------------------------------------------
start "ONB Frontend" cmd /k "cd /d "%ROOT%\app\frontend" && set "INTERNAL_API_URL=http://127.0.0.1:5055" && call node_modules\.bin\next.cmd start -p 8502 -H 0.0.0.0"
echo   [4/4] Frontend launching... (port 8502)

echo.
echo ============================================================================
echo  Open Notebook is starting up.
echo    Frontend : http://127.0.0.1:8502
echo    API docs : http://127.0.0.1:5055/docs
echo  Use stop.bat to shut everything down.
echo ============================================================================
endlocal & exit /b 0
