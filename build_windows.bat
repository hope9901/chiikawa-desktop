@echo off
setlocal EnableDelayedExpansion

echo ==================================================
echo   ChiikawaDesktop Windows Builder (.NET 8 SDK)
echo ==================================================
echo.

set "DOTNET_CMD=dotnet"
call :check_sdk
if "%HAS_NET8_SDK%"=="1" goto :build_app

echo [안내] Windows 소스 빌드를 위해 .NET 8 SDK가 필요합니다.
echo (현재 PC에 .NET 8 SDK가 설치되어 있지 않거나 Runtime만 설치되어 있습니다.)
echo.

where winget >nul 2>nul
if errorlevel 1 (
    echo [오류] WinGet을 찾을 수 없어 자동 설치를 진행할 수 없습니다.
    echo 아래 공식 페이지에서 .NET 8 SDK를 직접 설치한 뒤 다시 실행해 주세요:
    echo   https://dotnet.microsoft.com/en-us/download/dotnet/8.0
    echo.
    pause
    exit /b 1
)

set /p "INSTALL_CHOICE=WinGet으로 .NET 8 SDK를 자동 설치할까요? (Y/N): "
if /i not "%INSTALL_CHOICE%"=="Y" (
    echo.
    echo [취소] SDK 설치가 취소되어 빌드를 중단합니다.
    echo 수동 설치 링크: https://dotnet.microsoft.com/en-us/download/dotnet/8.0
    echo.
    pause
    exit /b 1
)

echo.
echo [설치] Microsoft.DotNet.SDK.8 설치 중...
winget install --id Microsoft.DotNet.SDK.8 --exact --source winget --accept-package-agreements --accept-source-agreements
if errorlevel 1 (
    echo.
    echo [오류] .NET 8 SDK 자동 설치에 실패했습니다.
    echo 아래 공식 링크에서 수동으로 설치한 뒤 다시 실행해 주세요:
    echo   https://dotnet.microsoft.com/en-us/download/dotnet/8.0
    echo.
    pause
    exit /b 1
)

rem 설치 직후 현재 배치 프로세스에서 dotnet.exe 경로 재탐색
if exist "%ProgramFiles%\dotnet\dotnet.exe" (
    set "DOTNET_CMD=%ProgramFiles%\dotnet\dotnet.exe"
    set "PATH=%ProgramFiles%\dotnet;%PATH%"
)

call :check_sdk
if not "%HAS_NET8_SDK%"=="1" (
    echo.
    echo [오류] .NET 8 SDK 설치 후에도 SDK를 감지하지 못했습니다.
    echo 터미널을 새로 열거나 아래 링크에서 수동 설치 상태를 확인해 주세요:
    echo   https://dotnet.microsoft.com/en-us/download/dotnet/8.0
    echo.
    pause
    exit /b 1
)

:build_app
echo.
echo [빌드] ChiikawaDesktop (Windows x64 Release) 게시 중...
cd /d "%~dp0Windows\ChiikawaDesktopWin"
"%DOTNET_CMD%" publish -c Release -r win-x64 --self-contained false -o "%~dp0build_windows"
if errorlevel 1 (
    echo.
    echo [오류] dotnet publish 빌드에 실패했습니다. 위 오류 메시지를 확인해 주세요.
    echo.
    pause
    exit /b 1
)

set "OUT_EXE=%~dp0build_windows\ChiikawaDesktop.exe"
if not exist "%OUT_EXE%" (
    echo.
    echo [오류] 빌드가 완료되었으나 출력 파일(%OUT_EXE%)을 찾을 수 없습니다.
    echo.
    pause
    exit /b 1
)

echo.
echo Done! Executable is at: %OUT_EXE%
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
for /f "tokens=1" %%v in ('"%DOTNET_CMD%" --list-sdks 2^>nul') do (
    echo %%v | findstr /b "8." >nul
    if not errorlevel 1 set "HAS_NET8_SDK=1"
)
exit /b 0
