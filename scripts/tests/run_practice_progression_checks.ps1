param(
    [string]$GodotExe = $env:GODOT_EXE,
    [switch]$SkipImport,
    [int]$TimeoutSeconds = 120
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
$validationRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('fluxbreak-practice-progression-' + $validationId)
New-Item -ItemType Directory -Path $validationRoot | Out-Null
$configText = Get-Content -LiteralPath (Join-Path $repoRoot 'project.godot') -Raw
$configText = [regex]::Replace($configText, '(?m)^config/name=.*$', 'config/name="Fluxbreak Practice Progression Validation"')
$configText = [regex]::Replace($configText, '(?m)^config/(use_custom_user_dir|custom_user_dir_name)=.*\r?\n', '')
$isolatedApplication = "[application]`r`nconfig/use_custom_user_dir=true`r`nconfig/custom_user_dir_name=`"Fluxbreak Validation/$validationId`""
$configText = $configText.Replace('[application]', $isolatedApplication)
[System.IO.File]::WriteAllText((Join-Path $validationRoot 'project.godot'), $configText)
foreach ($folder in @('assets', 'content', 'scenes', 'scripts', 'systems', '.godot')) {
    New-Item -ItemType Junction -Path (Join-Path $validationRoot $folder) -Target (Join-Path $repoRoot $folder) | Out-Null
}
Write-Output "Isolated validation project: $validationRoot"
$logPath = Join-Path $validationRoot 'practice_progression_checks.log'
$errorPath = Join-Path $validationRoot 'practice_progression_checks.stderr.log'
$arguments = @('--headless', '--path', ('"' + $validationRoot + '"'), '--fixed-fps', '60', '--quit-after', '1800', '--scene', 'res://scripts/tests/practice_progression_checks.tscn')
$process = Start-Process -FilePath $GodotExe -ArgumentList $arguments -WindowStyle Hidden -PassThru -RedirectStandardOutput $logPath -RedirectStandardError $errorPath
$processHandle = $process.Handle
if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
    Stop-Process -Id $process.Id
    throw "Practice progression validation exceeded $TimeoutSeconds seconds. Logs: $validationRoot"
}
$process.WaitForExit()
Get-Content -LiteralPath $logPath
Get-Content -LiteralPath $errorPath
if ($process.ExitCode -ne 0) { throw "Practice progression checks failed. Logs: $validationRoot" }
if (Select-String -LiteralPath @($logPath, $errorPath) -Pattern 'SCRIPT ERROR:|ERROR:|WARNING:|leaked' -Quiet) {
    throw 'Practice progression checks emitted an engine error, warning, or leak.'
}
if (-not (Select-String -LiteralPath $logPath -Pattern 'PRACTICE_PROGRESSION_CHECKS: PASS' -Quiet)) {
    throw 'Practice progression checks did not reach their success marker.'
}
