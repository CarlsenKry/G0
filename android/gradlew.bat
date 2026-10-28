@echo off
setlocal
set "GRADLE_VERSION=8.14"
set "BOOTSTRAP_DIR=%USERPROFILE%\.gradle\aether-bootstrap"
set "GRADLE_HOME=%BOOTSTRAP_DIR%\gradle-%GRADLE_VERSION%"
set "ARCHIVE=%BOOTSTRAP_DIR%\gradle-%GRADLE_VERSION%-all.zip"
if not exist "%GRADLE_HOME%\bin\gradle.bat" (
  if not exist "%BOOTSTRAP_DIR%" mkdir "%BOOTSTRAP_DIR%"
  if not exist "%ARCHIVE%" (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; Invoke-WebRequest -Uri 'https://services.gradle.org/distributions/gradle-%GRADLE_VERSION%-all.zip' -OutFile '%ARCHIVE%'"
    if errorlevel 1 exit /b 1
  )
  powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; Expand-Archive -LiteralPath '%ARCHIVE%' -DestinationPath '%BOOTSTRAP_DIR%' -Force"
  if errorlevel 1 exit /b 1
)
call "%GRADLE_HOME%\bin\gradle.bat" %*
exit /b %errorlevel%
