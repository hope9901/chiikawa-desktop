@echo off
echo Building ChiikawaDesktop for Windows (.NET 8)...
cd /d "%~dp0Windows\ChiikawaDesktopWin"
dotnet publish -c Release -r win-x64 --self-contained false -o "%~dp0build_windows"
echo.
echo Done! Executable is at: %~dp0build_windows\ChiikawaDesktop.exe
pause
