@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0sejong-slide.ps1" %*
set "SEJONG_EXIT=%ERRORLEVEL%"
if "%~1"=="" pause
exit /b %SEJONG_EXIT%
