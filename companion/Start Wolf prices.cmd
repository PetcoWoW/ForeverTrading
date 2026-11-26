@echo off
rem The Wolf of Booty Bay - prices companion: starts it by the clock (no window stays open)
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0WolfPrices.ps1"
