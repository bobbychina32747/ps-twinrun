# Use the same native receiver in both shells so only the caller changes.
$receiver = Join-Path $PSScriptRoot 'helpers\show-argv.ps1'
& $env:TWINRUN_PWSH -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $receiver 'folder with spaces' '' 'say "hello"'
exit $LASTEXITCODE
