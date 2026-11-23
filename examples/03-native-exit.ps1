$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
try {
    & "$env:SystemRoot\System32\cmd.exe" /d /c 'exit 7'
    Write-Output "Continued after native exit $LASTEXITCODE"
}
catch {
    Write-Output "Caught native exit $LASTEXITCODE"
    exit 7
}
