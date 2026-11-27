@echo off
rem ==================================================================
rem  ChiikawaDesktop Windows Builder (.NET 8 SDK)
rem
rem  NOTE: This file must keep Windows (CRLF) line endings and ASCII-only
rem  text. cmd.exe misparses LF-only / UTF-8 batch files (labels are not
rem  found, lines get garbled on Korean CP949 consoles). .gitattributes
rem  pins this file to CRLF.
rem ==================================================================
setlocal EnableExtensions EnableDelayedExpansion

echo ==================================================
echo   ChiikawaDesktop Windows Builder (.NET 8 SDK)
echo ==================================================
echo.

set "ROOT=%~dp0"
set "PROJECT_DIR=%ROOT%Windows\ChiikawaDesktopWin"
set "OUT_DIR=%ROOT%build_windows"
set "OUT_EXE=%OUT_DIR%\ChiikawaDesktop.exe"

set "RID=win-x64"
if /i "%PROCESSOR_ARCHITECTURE%"=="ARM64" set "RID=win-arm64"
if /i "%PROCESSOR_ARCHITEW6432%"=="ARM64" set "RID=win-arm64"

set "DOTNET_CMD=dotnet"
call :check_sdk
if "%HAS_NET8_SDK%"=="1" goto build_app

echo [INFO] The .NET 8 SDK is required to build from source.
echo        (It is not installed, or only the .NET Runtime is installed.)
echo        TIP: You do not need to build anything to just use the app.
echo             Download ChiikawaDesktop-Windows-x64.exe from the Releases page:
echo             https://github.com/hope9901/chiikawa-desktop/releases
echo.

where winget >nul 2>nul
if errorlevel 1 (
    echo [ERROR] WinGet was not found, so the SDK cannot be installed automatically.
    echo         Please install the .NET 8 SDK manually and run this file again:
    echo         https://dotnet.microsoft.com/en-us/download/dotnet/8.0
    echo.
    pause
    exit /b 1
)

set "INSTALL_CHOICE="
set /p "INSTALL_CHOICE=Install the .NET 8 SDK with WinGet now? (Y/N): "
if /i not "%INSTALL_CHOICE%"=="Y" (
    echo.
    echo [CANCELED] SDK installation was canceled. Build stopped.
    echo            Manual download: https://dotnet.microsoft.com/en-us/download/dotnet/8.0
    echo.
    pause
    exit /b 1
)

echo.
echo [INSTALL] Installing Microsoft.DotNet.SDK.8 ...
winget install --id Microsoft.DotNet.SDK.8 --exact --source winget --accept-package-agreements --accept-source-agreements
if errorlevel 1 (
    echo.
    echo [ERROR] Automatic installation of the .NET 8 SDK failed.
    echo         Please install it manually and run this file again:
    echo         https://dotnet.microsoft.com/en-us/download/dotnet/8.0
    echo.
    pause
    exit /b 1
)

rem Re-detect dotnet.exe in this console session right after installation.
if exist "%ProgramFiles%\dotnet\dotnet.exe" (
    set "DOTNET_CMD=%ProgramFiles%\dotnet\dotnet.exe"
    set "PATH=%ProgramFiles%\dotnet;%PATH%"
)

call :check_sdk
if not "%HAS_NET8_SDK%"=="1" (
    echo.
    echo [ERROR] The .NET 8 SDK still cannot be detected after installation.
    echo         Open a new terminal and run this file again, or check:
    echo         https://dotnet.microsoft.com/en-us/download/dotnet/8.0
    echo.
    pause
    exit /b 1
)

:build_app
echo.
echo [BUILD] Publishing ChiikawaDesktop (%RID%, Release, self-contained single EXE) ...
if exist "%OUT_DIR%" rmdir /s /q "%OUT_DIR%"
pushd "%PROJECT_DIR%" || (
    echo [ERROR] Project folder not found: %PROJECT_DIR%
    pause
    exit /b 1
)
"%DOTNET_CMD%" publish -c Release -r %RID% -o "%OUT_DIR%"
set "PUBLISH_RC=%ERRORLEVEL%"
popd
if not "%PUBLISH_RC%"=="0" (
    echo.
    echo [ERROR] dotnet publish failed. See the messages above.
    echo.
    pause
    exit /b 1
)

if not exist "%OUT_EXE%" (
    echo.
    echo [ERROR] Build finished, but the output file was not found: %OUT_EXE%
    echo.
    pause
    exit /b 1
)

echo.
echo Done! Executable is at: %OUT_EXE%
echo This single EXE runs on Windows 10/11 without installing .NET.
echo.
pause
exit /b 0

:check_sdk
set "HAS_NET8_SDK=0"
"%DOTNET_CMD%" --list-sdks >nul 2>nul
if errorlevel 1 (
    if exist "%ProgramFiles%\dotnet\dotnet.exe" (
        set "DOTNET_CMD=%ProgramFiles%\dotnet\dotnet.exe"
    ) else (
        exit /b 0
    )
)
for /f "tokens=1" %%v in ('call "%DOTNET_CMD%" --list-sdks 2^>nul') do (
    echo %%v| findstr /b "8." >nul
    if not errorlevel 1 set "HAS_NET8_SDK=1"
)
exit /b 0
