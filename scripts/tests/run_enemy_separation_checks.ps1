param(
    [string]$GodotExe = $env:GODOT_EXE,
    [switch]$SkipImport
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($GodotExe) -or -not (Test-Path -LiteralPath $GodotExe)) {
    throw 'Set GODOT_EXE to the Godot console executable or pass -GodotExe.'
}

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
if (-not $SkipImport) {
    & $GodotExe --headless --path $repoRoot --import --quit
    if ($LASTEXITCODE -ne 0) { throw 'Godot import failed.' }
}

# Synthetic actors and progression resets use a separate save namespace.
$validationRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('fluxbreak-separation-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $validationRoot | Out-Null
$configText = Get-Content -LiteralPath (Join-Path $repoRoot 'project.godot') -Raw
$configText = [regex]::Replace($configText, '(?m)^config/name=.*$', 'config/name="Fluxbreak Separation Validation"')
[System.IO.File]::WriteAllText((Join-Path $validationRoot 'project.godot'), $configText)
foreach ($folder in @('assets', 'content', 'scenes', 'scripts', 'systems', '.godot')) {
    New-Item -ItemType Junction -Path (Join-Path $validationRoot $folder) -Target (Join-Path $repoRoot $folder) | Out-Null
}
Write-Output "Isolated validation project: $validationRoot"

$logPath = Join-Path $validationRoot 'enemy_separation_checks.log'
& $GodotExe --headless --path $validationRoot --fixed-fps 60 --quit-after 3600 --scene 'res://scripts/tests/enemy_separation_checks.tscn' *> $logPath
$checkExit = $LASTEXITCODE
Get-Content -LiteralPath $logPath
if ($checkExit -ne 0) { throw 'Enemy separation checks failed.' }
if (Select-String -LiteralPath $logPath -Pattern 'SCRIPT ERROR:|ERROR:|WARNING:|leaked' -Quiet) {
    throw 'Enemy separation checks emitted an engine error, warning, or leak.'
}
if (-not (Select-String -LiteralPath $logPath -Pattern 'ENEMY_SEPARATION_CHECKS: PASS' -Quiet)) {
    throw 'Enemy separation checks did not reach their success marker.'
}
