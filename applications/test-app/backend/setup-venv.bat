@echo off
REM Windows batch file to run the setup script in WSL

echo Running virtual environment setup in WSL...
echo.
wsl bash -c "cd /mnt/e/CI/backend && chmod +x setup-venv.sh && ./setup-venv.sh"
echo.
echo Done!
pause


