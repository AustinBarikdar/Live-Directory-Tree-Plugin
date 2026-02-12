@echo off
REM Start the Live Directory Tree server

cd /d "%~dp0server"
echo Starting Live Directory Tree server...
node server.js
pause
