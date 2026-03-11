# Stops the Blender MCP adapter if it is running.
# powershell -ExecutionPolicy Bypass -File .\scripts\tools\blender\stop_blender_mcp_adapter.ps1

param(
    [int]$AdapterPort = 9877
)

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\\..\\..")).Path
$toolsDirPath = Join-Path $repoRoot "scripts\\tools\\blender"
$pidFilePath = Join-Path $toolsDirPath "blender_mcp_adapter.pid"

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

    return $commandLine -like "*blender_mcp_adapter.py*"
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

$adapterProcessId = $null

if (Test-Path $pidFilePath) {
    $pidValue = Get-Content $pidFilePath -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($pidValue -and ($pidValue -match '^\d+$')) {
        $candidateId = [int]$pidValue
        if (Test-IsAdapterProcess -ProcessId $candidateId) {
            $adapterProcessId = $candidateId
        }
    }
}

if (-not $adapterProcessId) {
    $listeningProcessId = Get-ListeningProcessIdForPort -Port $AdapterPort
    if ($listeningProcessId -and (Test-IsAdapterProcess -ProcessId $listeningProcessId)) {
        $adapterProcessId = $listeningProcessId
    } elseif ($listeningProcessId) {
        Write-Error "Port $AdapterPort is in use by process $listeningProcessId, and it is not the Blender MCP adapter."
        exit 1
    }
}

if (-not $adapterProcessId) {
    Remove-Item $pidFilePath -ErrorAction SilentlyContinue
    Write-Output "Blender MCP adapter is not running."
    exit 0
}

Stop-Process -Id $adapterProcessId -Force -ErrorAction Stop

for ($attempt = 0; $attempt -lt 20; $attempt++) {
    Start-Sleep -Milliseconds 250

    if (-not (Get-Process -Id $adapterProcessId -ErrorAction SilentlyContinue)) {
        break
    }
}

Remove-Item $pidFilePath -ErrorAction SilentlyContinue
Write-Output "Stopped Blender MCP adapter (PID $adapterProcessId)."
