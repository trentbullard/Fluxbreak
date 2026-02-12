param(
    [switch]$Major,
    [switch]$Minor,
    [switch]$Revision,
    [switch]$Hotfix,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

$selected = @()
if ($Major.IsPresent) { $selected += "Major" }
if ($Minor.IsPresent) { $selected += "Minor" }
if ($Revision.IsPresent) { $selected += "Revision" }
if ($Hotfix.IsPresent) { $selected += "Hotfix" }

if ($selected.Count -ne 1) {
    throw "Specify exactly one increment switch: -Major, -Minor, -Revision, or -Hotfix."
}

$incrementKind = $selected[0]
$projectRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")

$projectFile = Join-Path $projectRoot "project.godot"
$exportFile = Join-Path $projectRoot "export_presets.cfg"
$installerFile = Join-Path $projectRoot "installer\windows\Voidbreaker.iss"
$readmeFile = Join-Path $projectRoot "docs\release\README.txt"

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Read-Text {
    param([string]$Path)
    if (-not (Test-Path $Path)) {
        throw "Missing required file: $Path"
    }
    return [System.IO.File]::ReadAllText($Path)
}

function Write-Text {
    param(
        [string]$Path,
        [string]$Content
    )
    if ($DryRun) {
        return
    }
    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

function Replace-OrThrow {
    param(
        [string]$Content,
        [string]$Pattern,
        [string]$Replacement,
        [string]$Label
    )
    if (-not [System.Text.RegularExpressions.Regex]::IsMatch($Content, $Pattern, [System.Text.RegularExpressions.RegexOptions]::Multiline)) {
        throw "Could not find expected pattern for $Label."
    }

    return [System.Text.RegularExpressions.Regex]::Replace(
        $Content,
        $Pattern,
        $Replacement,
        [System.Text.RegularExpressions.RegexOptions]::Multiline
    )
}

$projectText = Read-Text -Path $projectFile
$versionMatch = [System.Text.RegularExpressions.Regex]::Match(
    $projectText,
    '(?m)^config/version="(?<version>\d+\.\d+\.\d+(?:\.\d+)?)"'
)

if (-not $versionMatch.Success) {
    throw 'Could not parse version from project.godot (expected config/version="x.y.z" or "x.y.z.w").'
}

$rawVersion = $versionMatch.Groups["version"].Value
$parts = $rawVersion.Split(".")
if ($parts.Count -eq 3) {
    $parts += "0"
}

$majorValue = [int]$parts[0]
$minorValue = [int]$parts[1]
$revisionValue = [int]$parts[2]
$hotfixValue = [int]$parts[3]

switch ($incrementKind) {
    "Major" {
        $majorValue += 1
        $minorValue = 0
        $revisionValue = 0
        $hotfixValue = 0
    }
    "Minor" {
        $minorValue += 1
        $revisionValue = 0
        $hotfixValue = 0
    }
    "Revision" {
        $revisionValue += 1
        $hotfixValue = 0
    }
    "Hotfix" {
        $hotfixValue += 1
    }
}

$shortVersion = "$majorValue.$minorValue.$revisionValue"
$displayVersion = if ($hotfixValue -gt 0) { "$shortVersion.$hotfixValue" } else { $shortVersion }
$fileVersion = "$majorValue.$minorValue.$revisionValue.$hotfixValue"

$projectUpdated = Replace-OrThrow -Content $projectText -Pattern '(?m)^config/version="[^"]+"' -Replacement "config/version=""$displayVersion""" -Label "project.godot config/version"
Write-Text -Path $projectFile -Content $projectUpdated

$exportText = Read-Text -Path $exportFile
$exportUpdated = Replace-OrThrow -Content $exportText -Pattern '(?m)^application/file_version="[^"]+"' -Replacement "application/file_version=""$fileVersion""" -Label "export_presets.cfg application/file_version"
$exportUpdated = Replace-OrThrow -Content $exportUpdated -Pattern '(?m)^application/product_version="[^"]+"' -Replacement "application/product_version=""$fileVersion""" -Label "export_presets.cfg application/product_version"
Write-Text -Path $exportFile -Content $exportUpdated

$installerText = Read-Text -Path $installerFile
$installerUpdated = Replace-OrThrow -Content $installerText -Pattern '(?m)^#define AppVersion "[^"]+"' -Replacement "#define AppVersion ""$displayVersion""" -Label "installer/windows/Voidbreaker.iss AppVersion"
Write-Text -Path $installerFile -Content $installerUpdated

$readmeText = Read-Text -Path $readmeFile
$readmeUpdated = Replace-OrThrow -Content $readmeText -Pattern '(?m)^Version:\s+.+' -Replacement "Version: $displayVersion" -Label "docs/release/README.txt Version"
Write-Text -Path $readmeFile -Content $readmeUpdated

if ($DryRun) {
    Write-Host "Dry run complete."
}

Write-Host "Version updated ($incrementKind): $rawVersion -> $displayVersion"
Write-Host "Windows file/product version: $fileVersion"
