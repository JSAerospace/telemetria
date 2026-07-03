@echo off
title J.S. AEROSPACE TELEMETRY UPLINK
color 0A
cls
echo ==================================================
echo   J.S. AEROSPACE - MISSION CONTROL UPLINK
echo ==================================================
echo.
echo  [*] Iniciando sistema de sincronizacion con la nube...
echo  [*] Asegurate de tener internet conectado.
echo.
python cloud_sync.py
if %errorlevel% neq 0 (
    echo.
    echo [!] ERROR: No se pudo iniciar Python.
    echo Asegurate de tener Python instalado y en el PATH.
    echo Tambien asegurate de instalar las dependencias:
    echo pip install requests
    pause
)
pause
