@echo off
setlocal
if "%~1"=="--help" goto setup_option
if "%~1"=="-h" goto setup_option
if "%~1"=="--check" goto setup_option
if "%~1"=="--setup" goto setup_option

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0sejong-slide.ps1" --prepare 1>&2
set "SEJONG_EXIT=%ERRORLEVEL%"
if not "%SEJONG_EXIT%"=="0" goto done
if "%~1"=="" goto ready

rem Forward the original command line directly; PowerShell 5.1 strips quotes.
"%~dp0.venv\Scripts\python.exe" %*
set "SEJONG_EXIT=%ERRORLEVEL%"
goto done

:ready
echo sejong-slide is ready. Open this folder in your AI editor and ask for a PPT.
pause
set "SEJONG_EXIT=0"

:done
exit /b %SEJONG_EXIT%

:setup_option
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0sejong-slide.ps1" %*
exit /b %ERRORLEVEL%
