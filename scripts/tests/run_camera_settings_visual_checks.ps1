param(
    [string]$GodotExe = $env:GODOT_EXE,
    [switch]$SkipImport,
    [string]$OutputDirectory = '',
    [int]$TimeoutSeconds = 180
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
$validationRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('fluxbreak-camera-settings-visual-' + $validationId)
New-Item -ItemType Directory -Path $validationRoot | Out-Null
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $validationRoot 'artifacts'
}
$OutputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$configText = Get-Content -LiteralPath (Join-Path $repoRoot 'project.godot') -Raw
$configText = [regex]::Replace($configText, '(?m)^config/name=.*$', 'config/name="Fluxbreak Camera Settings Visual Validation"')
$configText = [regex]::Replace($configText, '(?m)^config/(use_custom_user_dir|custom_user_dir_name)=.*\r?\n', '')
$isolatedApplication = "[application]`r`nconfig/use_custom_user_dir=true`r`nconfig/custom_user_dir_name=`"Fluxbreak Validation/$validationId`""
$configText = $configText.Replace('[application]', $isolatedApplication)
[System.IO.File]::WriteAllText((Join-Path $validationRoot 'project.godot'), $configText)
foreach ($folder in @('assets', 'content', 'scenes', 'scripts', 'systems', '.godot')) {
    New-Item -ItemType Junction -Path (Join-Path $validationRoot $folder) -Target (Join-Path $repoRoot $folder) | Out-Null
}
Write-Output "Isolated rendered validation project: $validationRoot"
Write-Output "Rendered artifacts: $OutputDirectory"
$logPath = Join-Path $validationRoot 'camera_settings_visual_checks.log'
$errorPath = Join-Path $validationRoot 'camera_settings_visual_checks.stderr.log'
# Render the real camera settings panels through the game renderer.
# Keep the render window off the desktop and the launcher console hidden.
$arguments = @('--path', ('"' + $validationRoot + '"'), '--rendering-method', 'forward_plus', '--rendering-driver', 'vulkan', '--resolution', '1280x720', '--position', '-32000,-32000', '--disable-vsync', '--max-fps', '240', '--scene', 'res://scripts/tests/camera_settings_visual_checks.tscn', '--', ('"--output=' + $OutputDirectory + '"'))

$process = Start-Process -FilePath $GodotExe -ArgumentList $arguments -WindowStyle Hidden -PassThru -RedirectStandardOutput $logPath -RedirectStandardError $errorPath
# Retain the process handle before it exits so Windows PowerShell can read its
# actual exit code after WaitForExit, including very short successful runs.
$processHandle = $process.Handle
if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
    Stop-Process -Id $process.Id
    throw "Rendered camera settings validation exceeded $TimeoutSeconds seconds. Logs: $validationRoot"
}
$process.WaitForExit()
Get-Content -LiteralPath $logPath
Get-Content -LiteralPath $errorPath
if ($process.ExitCode -ne 0) { throw "Rendered camera settings checks failed. Logs: $validationRoot" }
if (Select-String -LiteralPath @($logPath, $errorPath) -Pattern 'SCRIPT ERROR:|ERROR:|WARNING:|leaked' -Quiet) {
    throw 'Rendered camera settings checks emitted an engine error, warning, or leak.'
}
if (-not (Select-String -LiteralPath $logPath -Pattern 'CAMERA_SETTINGS_VISUAL_CHECKS: PASS' -Quiet)) {
    throw 'Rendered camera settings checks did not reach their success marker.'
}
