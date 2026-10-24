# sejong-slide Windows bootstrap helper (PowerShell 5.1+).
# Internal setup helper; use sejong-slide.cmd to run Python commands.
$SetupArguments = @($args)
$Mode = if ($SetupArguments.Count -eq 0) { '--prepare' } else { $SetupArguments[0] }
if ($Mode -in @('-h', '--help')) {
    Write-Host 'Usage: sejong-slide.cmd [--setup | --check | <Python arguments>]'
    Write-Host 'First use prepares Python and requirements automatically.'
    exit 0
}
if ($Mode -notin @('--prepare', '--setup', '--check') -or $SetupArguments.Count -gt 1) {
    Write-Error 'Use sejong-slide.cmd for Python tools; setup options must be used alone.'
    exit 2
}
$CheckOnly = $Mode -eq '--check'
$SetupOnly = $Mode -eq '--setup'
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
    $Preference = $ErrorActionPreference
    try {
        # PS 5.1 may wrap captured native stderr as nonterminating errors.
        $ErrorActionPreference = 'Continue'
        & $Executable @Arguments | ForEach-Object { [Console]::Error.WriteLine($_) }
        if ($LASTEXITCODE -ne 0) { throw "Command failed (exit $LASTEXITCODE): $Executable" }
    } finally { $ErrorActionPreference = $Preference }
}

function Find-InstalledPython {
    param([string]$Uv)
    $Preference = $ErrorActionPreference
    $PreviousConsoleEncoding = [Console]::OutputEncoding
    try {
        # Missing Python is an expected probe result, including in Windows PS 5.1.
        $ErrorActionPreference = 'Continue'
        # uv emits UTF-8 paths; PS 5.1 otherwise uses the OEM code page.
        [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
        $Found = & $Uv python find --system --no-python-downloads '>=3.10' 2>$null
        if ($LASTEXITCODE -eq 0 -and $Found) { return ($Found | Select-Object -Last 1).Trim() }
    } finally {
        [Console]::OutputEncoding = $PreviousConsoleEncoding
        $ErrorActionPreference = $Preference
    }
    return $null
}

try {
    if ($env:OS -ne 'Windows_NT') { throw 'Use ./sejong-slide on macOS or Linux.' }
    $Requirements = Join-Path $Root 'requirements.txt'
    $SkillRequirements = Join-Path $Root '.claude\skills\ppt-master\requirements.txt'
    if (-not (Test-Path -LiteralPath $Requirements)) { throw 'Download the complete repository: requirements.txt is missing.' }
    $NeedsSetup = $SetupOnly -or -not (Test-Path -LiteralPath $Python) -or -not (Test-Path -LiteralPath $Ready)
    if (-not $NeedsSetup) {
        $Stamp = (Get-Item -LiteralPath $Ready).LastWriteTimeUtc
        $NeedsSetup = (Get-Item -LiteralPath $Requirements).LastWriteTimeUtc -gt $Stamp -or
            ((Test-Path -LiteralPath $SkillRequirements) -and (Get-Item -LiteralPath $SkillRequirements).LastWriteTimeUtc -gt $Stamp)
    }
    Set-Location -LiteralPath $Root
    if ($CheckOnly) {
        if ($NeedsSetup) {
            throw 'Runtime setup is missing or outdated. Run sejong-slide.cmd --setup.'
        }
        Invoke-Checked $Python @('-I', '-c', $Verify)
        Invoke-Checked $Python @('-m', 'pip', 'check')
        $Stage = 'checking skill connections'
        Invoke-Checked $Python @('.claude/skills/ppt-master/scripts/sync_codex_stubs.py', '--check')
        Invoke-Checked $Python @('.claude/skills/ppt-master/scripts/check_runtime_contracts.py')
        exit 0
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
                $PreviousConsoleEncoding = [Console]::OutputEncoding
                try {
                    $env:UV_PYTHON_PREFERENCE = 'only-managed'
                    $ErrorActionPreference = 'Continue'
                    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
                    $BasePython = & $Uv python find --no-python-downloads 3.12
                    if ($LASTEXITCODE -ne 0) { throw 'Cannot find the downloaded Python. Retry --setup.' }
                    $BasePython = ($BasePython | Select-Object -Last 1).Trim()
                } finally {
                    [Console]::OutputEncoding = $PreviousConsoleEncoding
                    $ErrorActionPreference = 'Stop'
                    $env:UV_PYTHON_PREFERENCE = $OldPreference
                }
            }
            Invoke-Checked $Uv @('venv', '--quiet', '--no-project', '--python', $BasePython, $Venv)
        }
        Invoke-Checked $Python @('--version')
        if (Test-Path -LiteralPath $Ready) { Remove-Item -LiteralPath $Ready }
        $Stage = 'installing Python packages'
        [Console]::Error.WriteLine('[3/4] Installing project requirements...')
        Invoke-Checked $Uv @('pip', 'install', '--quiet', '--python', $Python, 'pip', '-r', $Requirements)
        $Stage = 'verifying the runtime'
        [Console]::Error.WriteLine('[4/4] Verifying Python packages...')
        Invoke-Checked $Python @('-I', '-c', $Verify)
        Invoke-Checked $Uv @('pip', 'check', '--python', $Python)
        New-Item -ItemType File -Force -Path $Ready | Out-Null
        [Console]::Error.WriteLine('Ready. Open this folder in your AI editor and ask it to create a PPT.')
        [Console]::Error.WriteLine('For the bundled slide fonts, see the Pretendard section in README.md.')
    }
    exit 0
} catch {
    if ($CheckOnly) {
        [Console]::Error.WriteLine("Check failed while ${Stage}: $($_.Exception.Message)")
        [Console]::Error.WriteLine('Fix the reported errors above, then run sejong-slide.cmd --check again.')
    } else {
        [Console]::Error.WriteLine("Setup failed while ${Stage}: $($_.Exception.Message)")
        [Console]::Error.WriteLine('Check the error above, then run sejong-slide.cmd --setup again.')
    }
    exit 1
} finally {
    foreach ($Name in $OldEnvironment.Keys) {
        [Environment]::SetEnvironmentVariable($Name, $OldEnvironment[$Name], 'Process')
    }
}
