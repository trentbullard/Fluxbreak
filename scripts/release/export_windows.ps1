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

function Get-TemplateVersionFromGodot {
    param([string]$ExePath)

    $versionLine = (& $ExePath --version 2>&1 | Select-Object -First 1 | Out-String).Trim()
    if ([string]::IsNullOrWhiteSpace($versionLine)) {
        return $null
    }

    $match = [System.Text.RegularExpressions.Regex]::Match(
        $versionLine,
        '^(?:Godot Engine\s+v)?(?<version>\d+\.\d+\.[A-Za-z0-9]+(?:\.mono)?)'
    )

    if ($match.Success) {
        return $match.Groups["version"].Value
    }

    return $null
}

$projectRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$outputDir = Join-Path $projectRoot "build\windows"
$installerScript = Join-Path $projectRoot "installer\windows\Fluxbreak.iss"

New-Item -ItemType Directory -Path $outputDir -Force | Out-Null

$exePath = Join-Path $outputDir "Fluxbreak.exe"
$presetName = "Windows Desktop"
$exportFlag = if ($BuildType -eq "debug") { "--export-debug" } else { "--export-release" }

$templateVersion = Get-TemplateVersionFromGodot -ExePath $GodotExe
if ($templateVersion) {
    $templateRoot = Join-Path $env:APPDATA "Godot\export_templates\$templateVersion"
    $requiredTemplates = @(
        (Join-Path $templateRoot "windows_debug_x86_64.exe"),
        (Join-Path $templateRoot "windows_release_x86_64.exe")
    )
    $missingTemplates = $requiredTemplates | Where-Object { -not (Test-Path $_) }

    if ($missingTemplates.Count -gt 0) {
        $missingList = ($missingTemplates -join "`n - ")
        throw @"
Missing Godot export templates for version '$templateVersion'.
Expected files:
 - $missingList

Install matching export templates in Godot:
Editor -> Manage Export Templates -> Install/Download (same version as your editor, including mono).
"@
    }
}

Write-Host "Exporting $BuildType build using preset '$presetName'..."
& $GodotExe --headless --path $projectRoot $exportFlag $presetName $exePath

if ($LASTEXITCODE -ne 0) {
    throw "Godot export failed with exit code $LASTEXITCODE"
}

if (-not (Test-Path $exePath)) {
    throw "Missing expected export output: $exePath"
}

Write-Host "Export complete:"
Write-Host " - $exePath"

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
