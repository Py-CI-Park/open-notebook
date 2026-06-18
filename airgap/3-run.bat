@echo off
REM ============================================================================
REM  Open Notebook - [3] RUN  (run on the CLOSED network PC, every time)
REM ----------------------------------------------------------------------------
REM  Starts all 4 services in separate windows, fully offline:
REM    SurrealDB(8000) -> API(5055) -> Worker -> Frontend(8502)
REM  Default mode serves the frontend/API on the LAN; use --local for this PC only.
REM ============================================================================
setlocal EnableExtensions EnableDelayedExpansion
set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"

set "DRY_RUN="
set "LOCAL_ONLY="
set "ALLOW_HOST="

:parse_args
if "%~1"=="" goto :parse_done
if /I "%~1"=="--dry-run" (set "DRY_RUN=1" & shift & goto :parse_args)
if /I "%~1"=="--local" (set "LOCAL_ONLY=1" & shift & goto :parse_args)
if /I "%~1"=="--allow-host" (shift & goto :capture_host)
set "ARG=%~1"
if /I "!ARG:~0,13!"=="--allow-host=" (set "ALLOW_HOST=!ARG:~13!" & shift & goto :parse_args)
if /I "%~1"=="--help" goto :help
echo [WARN] Unknown argument ignored: %~1
shift
goto :parse_args

:capture_host
if "%~1"=="" (
  echo [ERR] --allow-host requires an IP or hostname.
  endlocal & exit /b 1
)
set "ALLOW_HOST=%~1"
shift
goto :parse_args

:parse_done
if not defined LOCAL_ONLY if not defined ALLOW_HOST set "ALLOW_HOST=auto"
if /I "%ALLOW_HOST%"=="auto" call :resolve_auto_host

set "ON_API_HOST=127.0.0.1"
set "ON_FRONTEND_HOST=127.0.0.1"
set "ON_PUBLIC_HOST=127.0.0.1"
if defined ALLOW_HOST (
  set "ON_API_HOST=0.0.0.0"
  set "ON_FRONTEND_HOST=0.0.0.0"
  set "ON_PUBLIC_HOST=%ALLOW_HOST%"
)
set "ON_API_URL=http://%ON_PUBLIC_HOST%:5055"
set "ON_CORS_ORIGINS=http://localhost:8502,http://127.0.0.1:8502"
if defined ALLOW_HOST set "ON_CORS_ORIGINS=%ON_CORS_ORIGINS%,http://%ALLOW_HOST%:8502"

REM ---- self-contained environment (children inherit this) -------------------
set "UV=%ROOT%\tools\uv.exe"
set "PATH=%ROOT%\tools\node;%ROOT%\tools\ffmpeg\bin;%ROOT%\tools;%PATH%"
set "UV_PYTHON_INSTALL_DIR=%ROOT%\uv-python"
set "UV_CACHE_DIR=%ROOT%\uv-cache"
set "UV_OFFLINE=1"
set "DATA_FOLDER=%ROOT%\data"
set "TIKTOKEN_CACHE_DIR=%ROOT%\tiktoken-cache"
set "PYTHONPATH=%ROOT%\app"
REM Clear inherited OS env that would override .env. Child commands set the
REM network keys explicitly so stale app\.env values cannot break LAN runs.
set "CORS_ORIGINS="
set "OLLAMA_BASE_URL="
set "API_URL="
set "INTERNAL_API_URL="
set "API_HOST="

if "%DRY_RUN%"=="1" goto :dry_run
if not exist "%ROOT%\app\.venv" (echo [ERR] not installed yet - run 2-airgap-install.bat first & pause & endlocal & exit /b 1)

echo Starting Open Notebook services...
echo   data     : %DATA_FOLDER%
echo   api bind : %ON_API_HOST%:5055
echo   frontend : %ON_FRONTEND_HOST%:8502
echo   API_URL  : %ON_API_URL%
echo   CORS     : %ON_CORS_ORIGINS%
echo.

REM ---- 1) SurrealDB ---------------------------------------------------------
start "ONB SurrealDB" cmd /k "cd /d ""%ROOT%"" && tools\surreal.exe start --user root --pass root rocksdb:data\surrealdb\onb.db"
echo   [1/5] SurrealDB launching... (port 8000)
call :sleep 6

REM ---- 2) API (runs DB migrations on startup) -------------------------------
start "ONB API" cmd /k "cd /d ""%ROOT%\app"" && set ""API_HOST=%ON_API_HOST%"" && set ""API_PORT=5055"" && set ""CORS_ORIGINS=%ON_CORS_ORIGINS%"" && ""%UV%"" run --env-file .env python run_api.py"
echo   [2/5] API launching... (port 5055)
call :wait_http "http://127.0.0.1:5055/health" 90 "API"
if errorlevel 1 goto :fail

REM ---- 3) Worker (background jobs: embeddings, podcasts, ...) ---------------
start "ONB Worker" cmd /k "cd /d ""%ROOT%\app"" && ""%UV%"" run --env-file .env python -m surreal_commands.cli.worker --import-modules commands"
echo   [3/5] Worker launching...
call :sleep 3

REM ---- 4) Frontend ----------------------------------------------------------
start "ONB Frontend" cmd /k "cd /d ""%ROOT%\app\frontend"" && set ""API_URL=%ON_API_URL%"" && set ""INTERNAL_API_URL=http://127.0.0.1:5055"" && call node_modules\.bin\next.cmd start -p 8502 -H %ON_FRONTEND_HOST%"
echo   [4/5] Frontend launching... (port 8502)
call :wait_http "http://127.0.0.1:8502/" 90 "Frontend"
if errorlevel 1 goto :fail

REM ---- 5) Auto-register Ollama models + default assignments -----------------
start "ONB Provision" cmd /c "powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File ""%ROOT%\provision_models.ps1"""
echo   [5/5] Model auto-provision launching... (gemma4:12b chat + nomic-embed-text embedding)

echo.
echo ============================================================================
echo  Open Notebook is ready.
echo    Frontend : http://%ON_PUBLIC_HOST%:8502
echo    API docs : http://%ON_PUBLIC_HOST%:5055/docs
echo  Use stop.bat to shut everything down.
echo ============================================================================
endlocal & exit /b 0

:dry_run
echo [DRY-RUN] Open Notebook services would start from %ROOT%
echo [DRY-RUN] API bind      = %ON_API_HOST%:5055
echo [DRY-RUN] Frontend bind = %ON_FRONTEND_HOST%:8502
echo [DRY-RUN] API_URL       = %ON_API_URL%
echo [DRY-RUN] CORS_ORIGINS  = %ON_CORS_ORIGINS%
echo [DRY-RUN] SurrealDB -^> API health -^> Worker -^> Frontend health -^> Provision
endlocal & exit /b 0

:resolve_auto_host
set "ALLOW_HOST="
for /f "usebackq delims=" %%I in (`powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\detect_lan_ip.ps1"`) do set "ALLOW_HOST=%%I"
if not defined ALLOW_HOST (
  echo [WARN] LAN IPv4 not detected. Serving this PC only. Use --allow-host ^<IP^> to force.
  goto :eof
)
echo [INFO] LAN IPv4 = !ALLOW_HOST! (serving Open Notebook on 0.0.0.0)
goto :eof

:sleep
powershell -NoLogo -NoProfile -Command "Start-Sleep -Seconds %~1"
exit /b %errorlevel%

:wait_http
REM %1 url, %2 timeout seconds, %3 label
powershell -NoLogo -NoProfile -Command "$u='%~1';$t=%~2;$label='%~3';$ok=$false;for($i=0;$i -lt $t;$i++){try{$r=Invoke-WebRequest -UseBasicParsing -TimeoutSec 3 $u; if($r.StatusCode -eq 200){$ok=$true;break}}catch{}; Start-Sleep -Seconds 1}; if($ok){Write-Host ('[READY] '+$label+' reachable at '+$u); exit 0}else{Write-Host ('[ERR] '+$label+' did not become ready with HTTP 200 at '+$u+' within '+$t+'s'); exit 1}"
exit /b %errorlevel%

:fail
echo.
echo *** OPEN NOTEBOOK STARTUP FAILED *** (see service windows above)
echo.
endlocal & exit /b 1

:help
echo Usage: 3-run.bat [--dry-run] [--local] [--allow-host ^<IP-or-host^>]
echo.
echo Starts Open Notebook. By default it auto-detects this PC's LAN IPv4 and
echo binds API/frontend to 0.0.0.0 for LAN access. Use --local for loopback only.
endlocal & exit /b 0
