@echo off
title J.S. AEROSPACE - LANDER SYNC
color 0A
cls
cd /d "%~dp0"
echo ==================================================
echo   J.S. AEROSPACE - MUNAR LANDER TELEMETRY SYNC
echo ==================================================
echo.
echo  [*] Script dedicado al Munar Lander.
echo  [*] Ejecutar en paralelo con RUN_TELEMETRY.bat
echo.
py lander_sync.py
echo.
echo [!] Script terminado o cerrado.
pause
