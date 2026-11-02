@echo off
chcp 65001 > nul
echo ============================================================
echo   KHOI DONG BACKEND C# (.NET 9) THERMOGUARD IOT API
echo ============================================================
cd /d "%~dp0\ThermoGuard.Api"
dotnet run
pause
