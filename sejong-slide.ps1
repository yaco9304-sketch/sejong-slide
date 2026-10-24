# sejong-slide Windows bootstrap and Python launcher (PowerShell 5.1+).
# Arguments after the launcher are passed directly to the local Python.
$PythonArguments = @($args)
$CheckOnly = $false
$SetupOnly = $false
if ($PythonArguments.Count -gt 0) {
    switch ($PythonArguments[0]) {
        { $_ -in @('-h', '--help') } {
            Write-Host 'Usage: sejong-slide.cmd [--setup | --check | <Python arguments>]'
            Write-Host 'First use prepares Python and requirements automatically.'
            exit 0
        }
        '--check' { $CheckOnly = $true }
        '--setup' { $SetupOnly = $true }
    }
    if (($CheckOnly -or $SetupOnly) -and $PythonArguments.Count -ne 1) {
        Write-Error 'Use --setup or --check alone.'
        exit 2
    }
}
$ErrorActionPreference = 'Stop'
$Root = $PSScriptRoot
$Tools = Join-Path $Root '.sejong-tools'
$Python = Join-Path $Root '.venv\Scripts\python.exe'
$Ready = Join-Path $Tools 'ready'
$Verify = "import sys; assert sys.version_info >= (3, 10), 'Python 3.10+ required'; import pptx, flask, PIL, fitz, requests, numpy; print('Python and core packages: OK')"
$Stage = 'checking the installation'
$OldEnvironment = @{}

function Invoke-Checked {
    param([string]$Executable, [string[]]$Arguments)
    & $Executable @Arguments | ForEach-Object { [Console]::Error.WriteLine($_) }
    if ($LASTEXITCODE -ne 0) { throw "Command failed (exit $LASTEXITCODE): $Executable" }
}

function Find-InstalledPython {
    param([string]$Uv)
    $Preference = $ErrorActionPreference
    try {
        # Missing Python is an expected probe result, including in Windows PS 5.1.
        $ErrorActionPreference = 'Continue'
        $Found = & $Uv python find --system --no-python-downloads '>=3.10' 2>$null
        if ($LASTEXITCODE -eq 0 -and $Found) { return ($Found | Select-Object -Last 1).Trim() }
    } finally { $ErrorActionPreference = $Preference }
    return $null
}

try {
    if ($env:OS -ne 'Windows_NT') { throw 'Use ./sejong-slide on macOS or Linux.' }
    if ($CheckOnly) {
        if (-not (Test-Path -LiteralPath $Python -PathType Leaf)) {
            throw 'Not installed. Run sejong-slide.cmd to set up Python automatically.'
        }
        Invoke-Checked $Python @('-I', '-c', $Verify)
        Invoke-Checked $Python @('-m', 'pip', 'check')
        exit 0
    }
    Set-Location -LiteralPath $Root
    $Requirements = Join-Path $Root 'requirements.txt'
    $SkillRequirements = Join-Path $Root '.claude\skills\ppt-master\requirements.txt'
    if (-not (Test-Path -LiteralPath $Requirements)) { throw 'Download the complete repository: requirements.txt is missing.' }
    $NeedsSetup = $SetupOnly -or -not (Test-Path -LiteralPath $Python) -or -not (Test-Path -LiteralPath $Ready)
    if (-not $NeedsSetup) {
        $Stamp = (Get-Item -LiteralPath $Ready).LastWriteTimeUtc
        $NeedsSetup = (Get-Item -LiteralPath $Requirements).LastWriteTimeUtc -gt $Stamp -or
            (Get-Item -LiteralPath $SkillRequirements).LastWriteTimeUtc -gt $Stamp
    }
    if ($NeedsSetup) {
        [Console]::Error.WriteLine('sejong-slide: preparing a local runtime (no administrator access needed).')
        [Console]::Error.WriteLine('Downloads use Astral uv and PyPI; system Python and PATH stay unchanged.')
        New-Item -ItemType Directory -Force -Path (Join-Path $Tools 'bin') | Out-Null
        $Environment = @{
            UV_UNMANAGED_INSTALL = (Join-Path $Tools 'bin')
            UV_PYTHON_INSTALL_DIR = (Join-Path $Tools 'python')
            UV_PYTHON_BIN_DIR = (Join-Path $Tools 'bin')
            UV_CACHE_DIR = (Join-Path $Tools 'cache')
            UV_NO_CONFIG = '1'
        }
        foreach ($Name in $Environment.Keys) {
            $OldEnvironment[$Name] = [Environment]::GetEnvironmentVariable($Name, 'Process')
            [Environment]::SetEnvironmentVariable($Name, $Environment[$Name], 'Process')
        }
        $Stage = 'installing uv'
        $Uv = Join-Path $Tools 'bin\uv.exe'
        if (-not (Test-Path -LiteralPath $Uv -PathType Leaf)) {
            [Console]::Error.WriteLine('[1/4] Downloading the Python bootstrap tool...')
            $Installer = Join-Path $Tools 'uv-install.ps1'
            $OldProtocol = [Net.ServicePointManager]::SecurityProtocol
            try {
                [Net.ServicePointManager]::SecurityProtocol = $OldProtocol -bor [Net.SecurityProtocolType]::Tls12
                Invoke-WebRequest -UseBasicParsing -Uri 'https://astral.sh/uv/0.13.5/install.ps1' -OutFile $Installer
                & $Installer
                if (-not (Test-Path -LiteralPath $Uv -PathType Leaf)) {
                    throw 'uv installer failed. Check the network and retry.'
                }
            } finally { [Net.ServicePointManager]::SecurityProtocol = $OldProtocol }
        }
        Invoke-Checked $Uv @('--version')
        $Stage = 'preparing Python'
        [Console]::Error.WriteLine('[2/4] Checking Python and the local environment...')
        $Venv = Join-Path $Root '.venv'
        if (Test-Path -LiteralPath $Venv) {
            if (-not (Test-Path -LiteralPath $Python -PathType Leaf)) { throw 'The existing .venv is unusable. Rename .venv, then retry.' }
            Invoke-Checked $Python @('-c', 'import sys; sys.exit(sys.version_info < (3, 10))')
        } else {
            $BasePython = Find-InstalledPython $Uv
            if ($BasePython) {
                [Console]::Error.WriteLine("Using installed Python: $BasePython")
            } else {
                [Console]::Error.WriteLine('Python 3.10+ not found. Downloading local Python 3.12...')
                Invoke-Checked $Uv @('python', 'install', '--no-bin', '3.12')
                $OldPreference = $env:UV_PYTHON_PREFERENCE
                try {
                    $env:UV_PYTHON_PREFERENCE = 'only-managed'
                    $BasePython = & $Uv python find --no-python-downloads 3.12
                    if ($LASTEXITCODE -ne 0) { throw 'Cannot find the downloaded Python. Retry --setup.' }
                    $BasePython = ($BasePython | Select-Object -Last 1).Trim()
                } finally { $env:UV_PYTHON_PREFERENCE = $OldPreference }
            }
            Invoke-Checked $Uv @('venv', '--quiet', '--no-project', '--python', $BasePython, $Venv)
        }
        Invoke-Checked $Python @('--version')
        if (Test-Path -LiteralPath $Ready) { Remove-Item -LiteralPath $Ready }
        $Stage = 'installing Python packages'
        [Console]::Error.WriteLine('[3/4] Installing project requirements...')
        Invoke-Checked $Uv @('pip', 'install', '--quiet', '--python', $Python, 'pip', '-r', $Requirements)
        $Stage = 'verifying the runtime'
        [Console]::Error.WriteLine('[4/4] Verifying packages and skill connections...')
        Invoke-Checked $Python @('-I', '-c', $Verify)
        Invoke-Checked $Uv @('pip', 'check', '--python', $Python)
        Invoke-Checked $Python @('.claude/skills/ppt-master/scripts/sync_codex_stubs.py', '--check')
        Invoke-Checked $Python @('.claude/skills/ppt-master/scripts/check_runtime_contracts.py')
        New-Item -ItemType File -Force -Path $Ready | Out-Null
        [Console]::Error.WriteLine('Ready. Open this folder in your AI editor and ask it to create a PPT.')
        [Console]::Error.WriteLine('For the bundled slide fonts, see the Pretendard section in README.md.')
    }
    if ($SetupOnly) { exit 0 }
    if ($PythonArguments.Count -eq 0) {
        [Console]::Error.WriteLine('sejong-slide is ready. Python tools: sejong-slide.cmd <script.py> [arguments]')
        exit 0
    }
    $Stage = 'running the Python tool'
    & $Python @PythonArguments
    exit $LASTEXITCODE
} catch {
    [Console]::Error.WriteLine("Setup failed while ${Stage}: $($_.Exception.Message)")
    [Console]::Error.WriteLine('Check the error above, then run sejong-slide.cmd --setup again.')
    exit 1
} finally {
    foreach ($Name in $OldEnvironment.Keys) {
        [Environment]::SetEnvironmentVariable($Name, $OldEnvironment[$Name], 'Process')
    }
}
