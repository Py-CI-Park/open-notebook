@echo off
REM ============================================================================
REM  Open Notebook - PUBLISH air-gapped bundle as a GitHub Release asset
REM ----------------------------------------------------------------------------
REM  Run on the ONLINE PC after 1-online-package.bat has produced the ZIP.
REM  Requires GitHub CLI (gh) authenticated for this repo.
REM
REM  Usage:  release.bat [tag]
REM          tag defaults to  airgap-win-x64
REM ============================================================================
setlocal EnableExtensions
pushd "%~dp0.." || (echo [ERR] cannot enter repo root & exit /b 1)
set "REPO=%CD%"
popd
set "ZIP=%REPO%\dist\AeroOne-bundle.zip"

set "TAG=%~1"
if "%TAG%"=="" set "TAG=airgap-win-x64"

set "TITLE=Open Notebook - Air-Gapped Windows x64 Bundle"
set "NOTES=Self-contained, Docker-free offline bundle (Windows x64). Download AeroOne-bundle.zip, unzip into any empty no-spaces folder on the closed network, run 2-airgap-install.bat once, then 3-run.bat. See airgap/README.md."

echo.
echo === Publishing air-gapped bundle ===
echo Tag : %TAG%
echo Zip : %ZIP%
echo.

where gh >nul 2>nul || (echo [ERR] GitHub CLI ^(gh^) not found - install it and run: gh auth login & exit /b 1)
if not exist "%ZIP%" (echo [ERR] ZIP not found. Run 1-online-package.bat first. & exit /b 1)

gh release view "%TAG%" >nul 2>nul
if errorlevel 1 (
    echo Creating release %TAG% ...
    gh release create "%TAG%" "%ZIP%" --title "%TITLE%" --notes "%NOTES%"
) else (
    echo Release %TAG% exists - uploading/replacing asset ...
    gh release upload "%TAG%" "%ZIP%" --clobber
)
if errorlevel 1 (echo [ERR] gh release failed & exit /b 1)

echo.
echo ============================================================================
echo  Published. Download page:
gh release view "%TAG%" --json url -q ".url" 2>nul
echo ============================================================================
endlocal & exit /b 0
