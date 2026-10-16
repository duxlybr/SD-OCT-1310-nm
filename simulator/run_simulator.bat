@echo off
rem Abre la GUI del simulador OCE.
cd /d "%~dp0"
if not exist .venv\Scripts\pythonw.exe (
  echo Primero ejecute setup_venv.bat
  pause
  exit /b 1
)
start "" .venv\Scripts\pythonw.exe -m octsim
