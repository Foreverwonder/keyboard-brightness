@echo off
rem Start the brightness hotkey script in this folder.
rem Normally it starts at logon; use this when you change the config and need a restart.
start "" "%~dp0AutoHotkey64.exe" "%~dp0brightness.ahk"
exit
