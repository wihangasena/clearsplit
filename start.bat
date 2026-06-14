@echo off
REM Double-click launcher for the full ClearSplit stack (database check -> backend -> frontend).
REM Pass a mode if you want just one piece, e.g.  start.bat backend
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tool\start.ps1" %*
pause
