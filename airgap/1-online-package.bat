@echo off
REM ============================================================================
REM  Open Notebook - [1] ONLINE PACKAGE  (run on an INTERNET-connected Windows PC)
REM ----------------------------------------------------------------------------
REM  Produces a fully self-contained, Docker-free bundle under:
REM      <repo>\dist\AeroOne-bundle\
REM  containing: app source, python deps cache, bundled Python/uv/Node,
REM  SurrealDB, ffmpeg, prebuilt frontend and tiktoken cache.
REM  Copy that folder to the closed network, then run 2-airgap-install.bat.
REM ============================================================================
setlocal EnableExtensions EnableDelayedExpansion

REM ---- pinned versions (bump here when needed) -------------------------------
set "SURREAL_VER=2.3.7"
set "NODE_VER=20.18.1"

REM ---- paths ----------------------------------------------------------------
pushd "%~dp0.." || (echo [ERR] cannot enter repo root & goto :fail)
set "REPO=%CD%"
popd
set "BROOT=%REPO%\dist\AeroOne-bundle"
set "TOOLS=%BROOT%\tools"

echo.
echo === Open Notebook offline packager ===
echo Repo   : %REPO%
echo Output : %BROOT%
echo.

if not exist "%REPO%\pyproject.toml" (echo [ERR] run from repo\airgap\ ^(pyproject.toml not found^) & goto :fail)

REM ---- clean / create layout ------------------------------------------------
if exist "%BROOT%" rmdir /s /q "%BROOT%"
mkdir "%TOOLS%\node"        2>nul
mkdir "%TOOLS%\ffmpeg\bin"  2>nul
mkdir "%BROOT%\uv-python"   2>nul
mkdir "%BROOT%\uv-cache"    2>nul
mkdir "%BROOT%\tiktoken-cache" 2>nul

REM ===========================================================================
echo [1/7] Downloading uv (python package manager)...
call :dl "https://github.com/astral-sh/uv/releases/latest/download/uv-x86_64-pc-windows-msvc.zip" "%TEMP%\uv.zip" || goto :fail
call :unzip "%TEMP%\uv.zip" "%TOOLS%" || goto :fail
if not exist "%TOOLS%\uv.exe" (echo [ERR] uv.exe missing after extract & goto :fail)

REM ===========================================================================
echo [2/7] Downloading portable Node.js v%NODE_VER%...
call :dl "https://nodejs.org/dist/v%NODE_VER%/node-v%NODE_VER%-win-x64.zip" "%TEMP%\node.zip" || goto :fail
call :unzip "%TEMP%\node.zip" "%TEMP%\node-x" || goto :fail
robocopy "%TEMP%\node-x\node-v%NODE_VER%-win-x64" "%TOOLS%\node" /E /NFL /NDL /NJH /NJS >nul
if not exist "%TOOLS%\node\node.exe" (echo [ERR] node.exe missing after extract & goto :fail)
rmdir /s /q "%TEMP%\node-x" 2>nul

REM ===========================================================================
echo [3/7] Downloading SurrealDB v%SURREAL_VER%...
call :dl "https://download.surrealdb.com/v%SURREAL_VER%/surreal-v%SURREAL_VER%.windows-amd64.exe" "%TOOLS%\surreal.exe" || goto :fail

REM ===========================================================================
echo [4/7] Downloading ffmpeg (essentials)...
call :dl "https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip" "%TEMP%\ffmpeg.zip" || goto :fail
call :unzip "%TEMP%\ffmpeg.zip" "%TEMP%\ff-x" || goto :fail
for /d %%D in ("%TEMP%\ff-x\ffmpeg-*") do (
    copy /y "%%D\bin\ffmpeg.exe"  "%TOOLS%\ffmpeg\bin\" >nul
    copy /y "%%D\bin\ffprobe.exe" "%TOOLS%\ffmpeg\bin\" >nul
)
rmdir /s /q "%TEMP%\ff-x" 2>nul
if not exist "%TOOLS%\ffmpeg\bin\ffmpeg.exe" (echo [ERR] ffmpeg.exe missing after extract & goto :fail)

REM ---- tool env for the build -----------------------------------------------
set "UV=%TOOLS%\uv.exe"
set "PATH=%TOOLS%\node;%PATH%"
set "UV_PYTHON_INSTALL_DIR=%BROOT%\uv-python"
set "UV_CACHE_DIR=%BROOT%\uv-cache"

REM ===========================================================================
echo [5/7] Copying source into app folder ...
robocopy "%REPO%" "%BROOT%\app" /E /NFL /NDL /NJH /NJS ^
    /XD ".git" "dist" ".venv" "node_modules" ".next" "__pycache__" ".mypy_cache" ".ruff_cache" ".pytest_cache" "airgap" ^
    /XF "*.pyc" >nul
if errorlevel 8 (echo [ERR] source copy failed & goto :fail)

REM ===========================================================================
echo [6/7] Installing Python + seeding deps cache + frontend build...
"%UV%" python install 3.12 || (echo [ERR] uv python install failed & goto :fail)
pushd "%BROOT%\app"
"%UV%" sync --frozen || (echo [ERR] uv sync failed & popd & goto :fail)

echo     - prebaking tiktoken encoding (offline safe)...
set "TIKTOKEN_CACHE_DIR=%BROOT%\tiktoken-cache"
"%UV%" run python -c "import tiktoken; tiktoken.get_encoding('o200k_base')" || (echo [ERR] tiktoken prebake failed & popd & goto :fail)

echo     - building frontend (npm ci + build)...
pushd "%BROOT%\app\frontend"
call "%TOOLS%\node\npm.cmd" ci || (echo [ERR] npm ci failed & popd & popd & goto :fail)
call "%TOOLS%\node\npm.cmd" run build || (echo [ERR] npm build failed & popd & popd & goto :fail)
popd

REM venv is rebuilt offline on the target from uv-cache; drop it to save space
rmdir /s /q "%BROOT%\app\.venv" 2>nul
popd

REM ===========================================================================
echo [7/7] Adding install/run scripts...
copy /y "%~dp02-airgap-install.bat" "%BROOT%\2-airgap-install.bat" >nul
copy /y "%~dp03-run.bat"            "%BROOT%\3-run.bat"            >nul
copy /y "%~dp0stop.bat"             "%BROOT%\stop.bat"             >nul

> "%BROOT%\BUNDLE-INFO.txt" echo Open Notebook offline bundle
>>"%BROOT%\BUNDLE-INFO.txt" echo built: %DATE% %TIME%
>>"%BROOT%\BUNDLE-INFO.txt" echo surrealdb v%SURREAL_VER%  node v%NODE_VER%  python 3.12

echo.
echo ============================================================================
echo  DONE. Bundle ready at:
echo    %BROOT%
echo  Copy the WHOLE folder to the closed network (e.g. D:\Chanil_Park\Project\Programming\AeroOne),
echo  then run 2-airgap-install.bat once, then 3-run.bat to start.
echo ============================================================================
endlocal & exit /b 0

REM ---------------------------------------------------------------------------
:dl
REM %1=url %2=outfile
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference='Stop'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -UseBasicParsing -Uri '%~1' -OutFile '%~2'"
if errorlevel 1 (echo [ERR] download failed: %~1 & exit /b 1)
exit /b 0

:unzip
REM %1=zip %2=destdir
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference='Stop'; Expand-Archive -Force -LiteralPath '%~1' -DestinationPath '%~2'"
if errorlevel 1 (echo [ERR] extract failed: %~1 & exit /b 1)
exit /b 0

:fail
echo.
echo *** PACKAGING FAILED *** (see error above)
endlocal & exit /b 1
