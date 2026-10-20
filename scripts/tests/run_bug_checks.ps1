param(
    [string]$GodotExe = $env:GODOT_EXE
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($GodotExe) -or -not (Test-Path -LiteralPath $GodotExe)) {
    throw 'Set GODOT_EXE to the Godot 4.6.3 console executable or pass -GodotExe.'
}

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
& $GodotExe --headless --path $repoRoot --import --quit
if ($LASTEXITCODE -ne 0) { throw 'Godot import failed.' }

# Keep test progression separate from the player's normal game data.
$validationRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('fluxbreak-bug-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $validationRoot | Out-Null
$configText = Get-Content -LiteralPath (Join-Path $repoRoot 'project.godot') -Raw
$configText = [regex]::Replace($configText, '(?m)^config/name=.*$', 'config/name="Fluxbreak Bug Validation"')
[System.IO.File]::WriteAllText((Join-Path $validationRoot 'project.godot'), $configText)
foreach ($folder in @('assets','content','scenes','scripts','systems','.godot')) {
    New-Item -ItemType Junction -Path (Join-Path $validationRoot $folder) -Target (Join-Path $repoRoot $folder) | Out-Null
}
Write-Output "Isolated validation project: $validationRoot"

foreach ($scene in @('bug_regular_checks','bug_boss_checks','bug_practice_checks')) {
    & $GodotExe --headless --path $validationRoot --fixed-fps 60 --scene "res://scripts/tests/$scene.tscn"
    if ($LASTEXITCODE -ne 0) { throw "Bug check failed: $scene" }
}
