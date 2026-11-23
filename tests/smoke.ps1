$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$output = Join-Path ([IO.Path]::GetTempPath()) ('twinrun smoke ' + [guid]::NewGuid().ToString('N'))
& (Join-Path $root 'compare.cmd') -NoOpen -OutputDirectory $output
if ($LASTEXITCODE -ne 0) { throw "Launcher exited $LASTEXITCODE" }
$run = @(Get-ChildItem -LiteralPath $output -Directory)
if ($run.Count -ne 1) { throw 'Expected one report directory' }
$report = Get-Content -LiteralPath (Join-Path $run[0].FullName 'report.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if ($report.Cases.Count -ne 3) { throw 'Expected three comparisons' }
$encoding, $argv, $exit = $report.Cases
if (($encoding.Changes -join ',') -ne 'Files' -or $encoding.Left.Files[0].Hex -ne 'FF FE 2D 4E 87 65 0D 00 0A 00' -or $encoding.Right.Files[0].Hex -ne 'E4 B8 AD E6 96 87 0D 0A') {
    throw 'Unexpected default file bytes'
}
if (($argv.Changes -join ',') -ne 'Stdout' -or $argv.Left.Stdout -notmatch 'argc = 2' -or $argv.Right.Stdout -notmatch 'argc = 3' -or !$argv.Right.Stdout.Contains('argv[2] = <say "hello">')) {
    throw 'Unexpected native argument vector'
}
if (($exit.Changes -join ',') -ne 'ExitCode,Stdout' -or $exit.Left.ExitCode -ne 0 -or $exit.Right.ExitCode -ne 7) {
    throw 'Unexpected native error behavior'
}
$html = [IO.File]::ReadAllText((Join-Path $run[0].FullName 'report.html'))
if (!$html.Contains('3 / 3') -or !$html.Contains('&lt;say &quot;hello&quot;&gt;')) { throw 'Missing HTML evidence' }
Write-Host 'All three comparisons matched the expected observations.'
