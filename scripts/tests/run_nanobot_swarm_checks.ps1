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
$validationId = [guid]::NewGuid().ToString('N')
$validationRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('fluxbreak-nanobot-swarm-' + $validationId)
New-Item -ItemType Directory -Path $validationRoot | Out-Null
$configText = Get-Content -LiteralPath (Join-Path $repoRoot 'project.godot') -Raw
$configText = [regex]::Replace($configText, '(?m)^config/name=.*$', 'config/name="Fluxbreak Nanobot Swarm Validation"')
$configText = [regex]::Replace($configText, '(?m)^config/(use_custom_user_dir|custom_user_dir_name)=.*\r?\n', '')
$isolatedApplication = "[application]`r`nconfig/use_custom_user_dir=true`r`nconfig/custom_user_dir_name=`"Fluxbreak Validation/$validationId`""
$configText = $configText.Replace('[application]', $isolatedApplication)
[System.IO.File]::WriteAllText((Join-Path $validationRoot 'project.godot'), $configText)
foreach ($folder in @('assets', 'content', 'scenes', 'scripts', 'systems', '.godot')) {
    New-Item -ItemType Junction -Path (Join-Path $validationRoot $folder) -Target (Join-Path $repoRoot $folder) | Out-Null
}
Write-Output "Isolated validation project: $validationRoot"
$logPath = Join-Path $validationRoot 'nanobot_swarm_checks.log'
& $GodotExe --headless --path $validationRoot --fixed-fps 60 --quit-after 1800 --scene 'res://scripts/tests/nanobot_swarm_checks.tscn' *> $logPath
$checkExit = $LASTEXITCODE
Get-Content -LiteralPath $logPath
if ($checkExit -ne 0) { throw 'Nanobot swarm checks failed.' }
if (Select-String -LiteralPath $logPath -Pattern 'SCRIPT ERROR:|ERROR:|WARNING:|leaked' -Quiet) {
    throw 'Nanobot swarm checks emitted an engine error, warning, or leak.'
}
if (-not (Select-String -LiteralPath $logPath -Pattern 'NANOBOT_SWARM_CHECKS: PASS' -Quiet)) {
    throw 'Nanobot swarm checks did not reach their success marker.'
}
