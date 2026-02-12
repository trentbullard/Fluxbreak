param(
    [Parameter(Mandatory = $true)]
    [string]$GodotExe,

    [ValidateSet("release", "debug")]
    [string]$BuildType = "release",

    [switch]$BuildInstaller
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $GodotExe)) {
    throw "Godot executable was not found: $GodotExe"
}

$projectRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$outputDir = Join-Path $projectRoot "build\windows"
$installerScript = Join-Path $projectRoot "installer\windows\Voidbreaker.iss"

New-Item -ItemType Directory -Path $outputDir -Force | Out-Null

$exePath = Join-Path $outputDir "Voidbreaker.exe"
$pckPath = Join-Path $outputDir "Voidbreaker.pck"
$presetName = "Windows Desktop"
$exportFlag = if ($BuildType -eq "debug") { "--export-debug" } else { "--export-release" }

Write-Host "Exporting $BuildType build using preset '$presetName'..."
& $GodotExe --headless --path $projectRoot $exportFlag $presetName $exePath

if ($LASTEXITCODE -ne 0) {
    throw "Godot export failed with exit code $LASTEXITCODE"
}

if (-not (Test-Path $exePath)) {
    throw "Missing expected export output: $exePath"
}

if (-not (Test-Path $pckPath)) {
    throw "Missing expected export output: $pckPath"
}

Write-Host "Export complete:"
Write-Host " - $exePath"
Write-Host " - $pckPath"

if (-not $BuildInstaller) {
    return
}

$iscc = Get-Command "ISCC.exe" -ErrorAction SilentlyContinue
if (-not $iscc) {
    throw "ISCC.exe was not found in PATH. Install Inno Setup and retry."
}

Write-Host "Building installer with Inno Setup..."
& $iscc.Source $installerScript

if ($LASTEXITCODE -ne 0) {
    throw "Inno Setup failed with exit code $LASTEXITCODE"
}

Write-Host "Installer build complete. Check build\\installer."
