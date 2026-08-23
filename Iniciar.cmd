@echo off
REM ---------------------------------------------------------------------------
REM  Frutiger Aero - rescate y restauracion
REM  Doble clic aqui para abrir el menu guiado, sin tocar ninguna configuracion
REM  de PowerShell: el Bypass solo afecta a esta ventana.
REM ---------------------------------------------------------------------------
title Frutiger Aero - rescate y restauracion
chcp 65001 >nul 2>&1

if not exist "%~dp0AeroTool.ps1" (
    echo.
    echo  [X] No encuentro AeroTool.ps1 junto a este archivo.
    echo      Manten Iniciar.cmd y los cuatro .ps1 en la misma carpeta.
    echo.
    pause
    exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0AeroTool.ps1" %*

if errorlevel 1 (
    echo.
    echo  La herramienta termino con un error. Revisa el mensaje de arriba.
    echo.
    pause
)
