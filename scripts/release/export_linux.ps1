param(
    [Parameter(Mandatory = $true)]
    [string]$GodotExe,

    [ValidateSet("release", "debug")]
    [string]$BuildType = "release"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $GodotExe)) {
    throw "Godot executable was not found: $GodotExe"
}

$projectRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$outputDir = Join-Path $projectRoot "build\linux"

New-Item -ItemType Directory -Path $outputDir -Force | Out-Null

$binaryPath = Join-Path $outputDir "Fluxbreak.x86_64"
$pckPath = Join-Path $outputDir "Fluxbreak.pck"
$presetName = "Linux/BSD"
$exportFlag = if ($BuildType -eq "debug") { "--export-debug" } else { "--export-release" }

Write-Host "Exporting $BuildType build using preset '$presetName'..."
& $GodotExe --headless --path $projectRoot $exportFlag $presetName $binaryPath

if ($LASTEXITCODE -ne 0) {
    throw "Godot export failed with exit code $LASTEXITCODE"
}

if (-not (Test-Path $binaryPath)) {
    throw "Missing expected export output: $binaryPath"
}

if (-not (Test-Path $pckPath)) {
    throw "Missing expected export output: $pckPath"
}

Write-Host "Export complete:"
Write-Host " - $binaryPath"
Write-Host " - $pckPath"
