:: Automated Install batch script by Syuugo

@echo off
%~d0
cd "%~dp0"
if not exist Install.ps1 (
    echo "Install.ps1" is not found.
    echo Press any key to exit
    pause>nul
    exit 1
) else (
    start powershell.exe -ExecutionPolicy Bypass -File .\Install.ps1
    exit
)
