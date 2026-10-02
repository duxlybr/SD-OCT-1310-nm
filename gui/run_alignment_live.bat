@echo off
cd /d "%~dp0PYTHON_GUI"
py -3.11 run_alignment_live.py %*
