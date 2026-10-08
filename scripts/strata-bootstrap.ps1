# strata-bootstrap.ps1 - Strata's Windows bootstrap: uv does everything.
# Finds uv (PATH, or the .uvbin folder), installs it with its official installer when it is nowhere (pinned,
# into .uvbin, no PATH edit, no admin rights), then 'uv venv' makes .venv: uv uses a Python 3.10+ already on
# the PC and downloads its own CPython only when none is found (a folder of its own, no admin rights).
# winget and the python.org installer are gone.  STRATA.bat is the thin entry; this file holds the whole logic.
# Written for Windows PowerShell 5.1 - what every Windows 10/11 ships: no '&&', no ternary.

$ErrorActionPreference = 'Continue'
Set-Location (Split-Path -Parent $PSScriptRoot)

$UvVersion = '0.12.23'          # the same pin setup.py uses
$UvDir = Join-Path (Get-Location) '.uvbin'
$UvExe = Join-Path $UvDir 'uv.exe'

function Find-StrataUv {
    # uv on PATH, else the uv the installer put into .uvbin
    $cmd = Get-Command uv -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    if (Test-Path $UvExe) { return $UvExe }
    return $null
}

function Install-StrataUv {
    Write-Host ''
    Write-Host "  Installing uv $UvVersion (Python and packages manager) into .uvbin ..."
    $env:UV_INSTALL_DIR = $UvDir
    $env:UV_NO_MODIFY_PATH = '1'
    try { irm https://astral.sh/uv/$UvVersion/install.ps1 | iex } catch { }
    if (Test-Path $UvExe) { return $UvExe }
    return $null
}

$venvPy = Join-Path (Get-Location) '.venv\Scripts\python.exe'
if (-not (Test-Path $venvPy)) {
    $uv = Find-StrataUv
    if (-not $uv) { $uv = Install-StrataUv }
    if (-not $uv) {
        Write-Host ''
        Write-Host '  uv could not be installed automatically (no internet, or PowerShell was blocked).'
        Write-Host "  Install uv $UvVersion from https://docs.astral.sh/uv/ and double-click STRATA.bat again."
        exit 1
    }
    # uv makes the environment: a Python 3.10+ already on the PC is used as it is; only when none is found
    # does uv download its own CPython - no admin rights, nothing installed into the system.
    & $uv venv --python '>=3.10' .venv
    if (-not (Test-Path $venvPy)) {
        Write-Host '  Could not create the Python environment in .venv'
        Write-Host '  (a half-made .venv from an earlier run: delete the .venv folder and try again)'
        exit 1
    }
    # 64-bit, like the old START-HERE.bat probe guaranteed (a 32-bit Python cannot hold the model)
    & $venvPy -c 'import sys; sys.exit(0 if sys.maxsize > 2**32 else 1)'
    if ($LASTEXITCODE -ne 0) {
        Write-Host '  Strata needs 64-bit Python; the environment in .venv is 32-bit.'
        exit 1
    }
}
& $venvPy setup.py @args
exit $LASTEXITCODE
