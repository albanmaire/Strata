# strata-bootstrap.ps1 - Strata's Windows bootstrap (the former START-HERE.bat, as functions).
# Finds 64-bit Python 3.10+ (or installs it for the user account), makes the project's .venv, then runs
# setup.py with every option. Written for Windows PowerShell 5.1 - what every Windows 10/11 ships:
# no '&&', no ternary. STRATA.bat is the thin entry; this file holds the whole logic.

$ErrorActionPreference = 'Continue'
Set-Location (Split-Path -Parent $PSScriptRoot)

function Invoke-StrataPython {
    # run the found interpreter with arguments (works for 'py -3', 'python' and a full path alike)
    param([string[]]$Py, [string[]]$CmdArgs)
    $rest = @()
    if ($Py.Count -gt 1) { $rest = $Py[1..($Py.Count - 1)] }
    & $Py[0] ($rest + $CmdArgs)
}

function Test-StrataPython {
    param([string[]]$Py)
    # 64-bit and 3.10+ (the same probe START-HERE.bat used; it also rejects the Microsoft Store stub)
    $probe = 'import sys; sys.exit(0 if sys.version_info >= (3, 10) and sys.maxsize > 2**32 else 1)'
    Invoke-StrataPython $Py @('-c', $probe) 2>$null | Out-Null
    return ($LASTEXITCODE -eq 0)
}

function Find-StrataPython {
    # the py launcher first, then python on PATH (not the Microsoft Store stub), then the usual per-user folders
    if (Get-Command py -ErrorAction SilentlyContinue) {
        $py = @('py', '-3')
        if (Test-StrataPython $py) { return ,$py }
    }
    if (Get-Command python -ErrorAction SilentlyContinue) {
        $py = @('python')
        if (Test-StrataPython $py) { return ,$py }
    }
    foreach ($v in '313', '312', '311', '310') {
        $p = Join-Path $env:LOCALAPPDATA ('Programs\Python\Python' + $v + '\python.exe')
        if (Test-Path $p) { return ,@($p) }
    }
    return $null
}

function Install-StrataPython {
    Write-Host ''
    Write-Host '  Python 3.10 or newer is not installed. Installing Python 3.12 for your user account ...'
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        winget install -e --id Python.Python.3.12 --scope user --silent --source winget `
            --accept-package-agreements --accept-source-agreements --disable-interactivity
        $py = Find-StrataPython
        if ($py) { return $py }
    }
    Write-Host '  Downloading the Python installer from python.org ...'
    $setupExe = Join-Path $env:TEMP 'strata-python-setup.exe'
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -UseBasicParsing 'https://www.python.org/ftp/python/3.12.10/python-3.12.10-amd64.exe' -OutFile $setupExe
    } catch { }
    if (Test-Path $setupExe) {
        Start-Process -FilePath $setupExe -Wait -ArgumentList `
            '/quiet', 'InstallAllUsers=0', 'PrependPath=1', 'Include_launcher=1', 'Include_test=0'
        Remove-Item $setupExe -ErrorAction SilentlyContinue
        return Find-StrataPython
    }
    return $null
}

$venvPy = Join-Path (Get-Location) '.venv\Scripts\python.exe'
if (-not (Test-Path $venvPy)) {
    $py = Find-StrataPython
    if (-not $py) { $py = Install-StrataPython }
    if (-not $py) {
        Write-Host ''
        Write-Host '  Python could not be installed automatically.'
        Write-Host '  Install 64-bit Python 3.12 from https://www.python.org/downloads/ ("Add python.exe to PATH"),'
        Write-Host '  then double-click STRATA.bat again.'
        exit 1
    }
    # a private environment inside this folder, so nothing is installed into the system Python
    Invoke-StrataPython $py @('-m', 'venv', '.venv')
    if (-not (Test-Path $venvPy)) {
        Write-Host '  Could not create the Python environment in .venv'
        exit 1
    }
}
& $venvPy setup.py @args
exit $LASTEXITCODE
