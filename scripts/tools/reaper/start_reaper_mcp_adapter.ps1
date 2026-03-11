# Starts the REAPER MCP adapter, which listens for MCP requests from Codex and forwards them to REAPER via reapy.
# powershell -ExecutionPolicy Bypass -File .\scripts\tools\reaper\start_reaper_mcp_adapter.ps1

param(
    [int]$AdapterPort = 9881,
    [int]$WebInterfacePort = 2307,
    [int]$ReapyServerPort = 2306,
    [string]$AdapterHost = "127.0.0.1",
    [string]$ReaperHost = "127.0.0.1"
)

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\\..\\..")).Path
$toolsDirPath = Join-Path $repoRoot "scripts\\tools\\reaper"
$scriptPath = Join-Path $toolsDirPath "reaper_mcp_adapter.py"
$stdoutLogPath = Join-Path $toolsDirPath "reaper_mcp_adapter.stdout.log"
$stderrLogPath = Join-Path $toolsDirPath "reaper_mcp_adapter.stderr.log"
$pidFilePath = Join-Path $toolsDirPath "reaper_mcp_adapter.pid"

function Get-CommandLineForProcess {
    param(
        [int]$ProcessId
    )

    try {
        $processInfo = Get-CimInstance Win32_Process -Filter "ProcessId = $ProcessId" -ErrorAction Stop
        return $processInfo.CommandLine
    } catch {
        return $null
    }
}

function Test-IsAdapterProcess {
    param(
        [int]$ProcessId
    )

    $commandLine = Get-CommandLineForProcess -ProcessId $ProcessId
    if (-not $commandLine) {
        return $false
    }

    return $commandLine -like "*reaper_mcp_adapter.py*"
}

function Get-ListeningProcessIdForPort {
    param(
        [int]$Port
    )

    try {
        $connection = Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction Stop | Select-Object -First 1
        if ($connection) {
            return [int]$connection.OwningProcess
        }
    } catch {
        return $null
    }

    return $null
}

function Write-PidFile {
    param(
        [string]$Path,
        [int]$ProcessId
    )

    for ($attempt = 0; $attempt -lt 10; $attempt++) {
        try {
            [System.IO.File]::WriteAllText($Path, [string]$ProcessId, [System.Text.Encoding]::ASCII)
            return
        } catch {
            Start-Sleep -Milliseconds 100
        }
    }

    throw "Failed to write PID file at $Path."
}

$existingListenerId = Get-ListeningProcessIdForPort -Port $AdapterPort
if ($existingListenerId) {
    if (Test-IsAdapterProcess -ProcessId $existingListenerId) {
        Write-PidFile -Path $pidFilePath -ProcessId $existingListenerId
        Write-Output "REAPER MCP adapter is already running on http://$AdapterHost`:$AdapterPort/mcp"
        Write-Output "PID: $existingListenerId"
        Write-Output "Stdout log: $stdoutLogPath"
        Write-Output "Stderr log: $stderrLogPath"
        exit 0
    }

    Write-Error "Port $AdapterPort is already in use by process $existingListenerId, and it is not the REAPER MCP adapter."
    exit 1
}

$process = Start-Process `
    -FilePath "python" `
    -ArgumentList @(
        $scriptPath,
        "--host", $AdapterHost,
        "--port", $AdapterPort,
        "--reaper-host", $ReaperHost,
        "--web-interface-port", $WebInterfacePort,
        "--reapy-server-port", $ReapyServerPort
    ) `
    -WorkingDirectory $repoRoot `
    -RedirectStandardOutput $stdoutLogPath `
    -RedirectStandardError $stderrLogPath `
    -WindowStyle Hidden `
    -PassThru

$started = $false
for ($attempt = 0; $attempt -lt 20; $attempt++) {
    Start-Sleep -Milliseconds 250

    $currentListenerId = Get-ListeningProcessIdForPort -Port $AdapterPort
    if ($currentListenerId -and ($currentListenerId -eq $process.Id) -and (Test-IsAdapterProcess -ProcessId $currentListenerId)) {
        $started = $true
        break
    }

    if ($process.HasExited) {
        break
    }
}

if (-not $started) {
    if (-not $process.HasExited) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    }

    Write-Error "Failed to start REAPER MCP adapter on port $AdapterPort. Check the logs for details."
    Write-Output "Stdout log: $stdoutLogPath"
    Write-Output "Stderr log: $stderrLogPath"
    exit 1
}

Write-PidFile -Path $pidFilePath -ProcessId $process.Id

Write-Output "Started REAPER MCP adapter on http://$AdapterHost`:$AdapterPort/mcp"
Write-Output "PID: $($process.Id)"
Write-Output "Stdout log: $stdoutLogPath"
Write-Output "Stderr log: $stderrLogPath"
