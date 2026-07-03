@echo off
title TOMCAT MISSION CONTROL - DASHBOARD
color 0A
cls
echo ==================================================
echo   TOMCAT MISSION CONTROL - SISTEMA DE TELEMETRIA
echo ==================================================
echo.
echo  [*] Iniciando servidor local de telemetria...
echo  [*] Captura de camara KSP activada (Pillow + pywin32)
echo.

:: Usar el Python correcto
set PYTHON_EXE=C:\Users\olano\AppData\Local\Python\bin\python.exe

:: Verificar que Python exista
if not exist "%PYTHON_EXE%" (
    echo [!] ERROR: No se encontro Python en %PYTHON_EXE%
    pause
    exit /b 1
)

:: Abrir el navegador automaticamente despues de 2 segundos
start "" cmd /c "timeout /t 2 /nobreak > nul && start http://localhost:8080"

:: Iniciar el servidor
"%PYTHON_EXE%" web_dashboard.py

if %errorlevel% neq 0 (
    echo.
    echo [!] ERROR: El servidor fallo al iniciar.
    echo     Asegurate de haber instalado las dependencias:
    echo     python -m pip install pillow pywin32 requests
    pause
)
pause
