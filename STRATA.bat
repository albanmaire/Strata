@echo off
rem Strata (Windows): the first run installs everything and starts the model; later runs just start it.
rem Options: --setup (install another model / change settings), --update (fetch the newest code and refresh
rem the install without starting), --no-start, --calibrate, --model/--context/--gpus ... (setup.py passes them on).
rem All the logic lives in scripts\strata-bootstrap.ps1; this file only launches it.
rem The whole body is one block: cmd reads a .bat while it runs it, and setup.py --update can pull a new
rem version of this very file - the block is parsed before anything runs, so a pull can never corrupt it.
(
  powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\strata-bootstrap.ps1" %*
  if errorlevel 1 pause
)
