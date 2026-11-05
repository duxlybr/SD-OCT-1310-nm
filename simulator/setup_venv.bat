@echo off
rem Crea el entorno virtual del simulador e instala dependencias (GPU opcional).
cd /d "%~dp0"
if not exist .venv (
  py -3.14 -m venv .venv 2>nul || py -3 -m venv .venv
)
.venv\Scripts\python.exe -m pip install --upgrade pip
.venv\Scripts\python.exe -m pip install -r requirements.txt
.venv\Scripts\python.exe -m pip install -r requirements-gpu.txt || echo GPU no disponible: el simulador usara la CPU (mas lento).
.venv\Scripts\python.exe -c "from octsim.backend import get_backend; print(get_backend().describe())"
pause
