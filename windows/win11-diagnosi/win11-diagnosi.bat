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

:: Ask for optional test label
set "TEST_LABEL="
set /p TEST_LABEL="  Etichetta test (A, B, o invio per nessuna): "

:: Ask for disk scan mode
echo.
echo  Scansione disco:
echo    1 = Rapida (solo cache note, pochi secondi)
echo    2 = Completa (tutte le cartelle + file grandi, puo' richiedere minuti)
set "DISK_MODE=1"
set /p DISK_MODE="  Scegli [1]: "

:: Build optional arguments
set "PS_LABEL="
if defined TEST_LABEL set "PS_LABEL=-TestLabel %TEST_LABEL%"
set "PS_DEEP="
if "%DISK_MODE%"=="2" set "PS_DEEP=-DeepDiskScan"

echo.

:: Run the PowerShell script
powershell.exe -ExecutionPolicy Bypass -NoProfile -File "%SCRIPT_DIR%win11-diagnosi.ps1" -OutputPath "%CD%" %PS_LABEL% %PS_DEEP%

set "PS_EXIT=%ERRORLEVEL%"
echo.
if "%PS_EXIT%"=="0" (
    echo  [OK] Diagnosi completata con successo.
) else if "%PS_EXIT%"=="2" (
    echo  [OK] Diagnosi completata con dati parziali.
    echo       Per risultati completi, eseguire come Amministratore.
) else (
    echo  [ERRORE] Diagnosi fallita. Exit code: %PS_EXIT%
)
echo.
echo  Premi un tasto per chiudere...
pause >nul
exit /b %PS_EXIT%
