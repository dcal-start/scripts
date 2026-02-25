@echo off
:: =============================================
::  DIAGNOSI SISTEMA WINDOWS 11 - Launcher
:: =============================================
::  Esegue lo script PowerShell di diagnostica
::  e salva il report nella cartella corrente.
::
::  CONSIGLIO: eseguire come Amministratore
::  per risultati completi (tasto destro >
::  "Esegui come amministratore").
:: =============================================

echo.
echo  =============================================
echo   DIAGNOSI SISTEMA WINDOWS 11
echo  =============================================
echo.

:: Check if running as admin
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo  [!] NON stai eseguendo come Amministratore.
    echo      Alcuni dati potrebbero non essere disponibili.
    echo      Per risultati completi, chiudi e riesegui con
    echo      tasto destro ^> "Esegui come amministratore".
    echo.
    pause
)

:: Get the directory where this bat file is located
set "SCRIPT_DIR=%~dp0"

:: Run the PowerShell script
powershell.exe -ExecutionPolicy Bypass -NoProfile -File "%SCRIPT_DIR%win11-diagnosi.ps1" -OutputPath "%CD%"

echo.
echo  Premi un tasto per chiudere...
pause >nul
