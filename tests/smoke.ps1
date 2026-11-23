$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$output = Join-Path ([IO.Path]::GetTempPath()) ('twinrun smoke ' + [guid]::NewGuid().ToString('N'))
$launcher = Join-Path $root 'compare.cmd'

function Get-ReportDirectory([string]$Parent) {
    $runs = @(Get-ChildItem -LiteralPath $Parent -Directory)
    if ($runs.Count -ne 1) { throw "Expected one report directory under $Parent" }
    $runs[0].FullName
}

& $launcher -NoOpen -OutputDirectory $output
if ($LASTEXITCODE -ne 0) { throw "Launcher exited $LASTEXITCODE" }
$run = Get-ReportDirectory $output
$report = Get-Content -LiteralPath (Join-Path $run 'report.json') -Raw -Encoding UTF8 | ConvertFrom-Json
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
$html = [IO.File]::ReadAllText((Join-Path $run 'report.html'))
if (!$html.Contains('3 / 3') -or !$html.Contains('&lt;say &quot;hello&quot;&gt;')) { throw 'Missing HTML evidence' }

$differentOutput = Join-Path $output 'different'
$differentScript = Join-Path $root 'examples\01-file-encoding.ps1'
& $launcher -NoOpen -FailOnDifference -OutputDirectory $differentOutput -Script $differentScript
if ($LASTEXITCODE -ne 3) { throw "Expected exit 3 for different files, got $LASTEXITCODE" }
$run = Get-ReportDirectory $differentOutput
$report = Get-Content -LiteralPath (Join-Path $run 'report.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if (($report.Cases[0].Changes -join ',') -ne 'Files') { throw 'Expected the JSON report to identify different files' }
$html = [IO.File]::ReadAllText((Join-Path $run 'report.html'))
if (!$html.Contains('1 / 1')) { throw 'Expected the HTML report to show one difference' }

$sameOutput = Join-Path $output 'same'
$sameScript = Join-Path $output 'same exit.ps1'
[IO.File]::WriteAllText($sameScript, 'exit 7')
& $launcher -NoOpen -FailOnDifference -OutputDirectory $sameOutput -Script $sameScript
if ($LASTEXITCODE -ne 0) { throw "Expected exit 0 for matching child exits, got $LASTEXITCODE" }
$run = Get-ReportDirectory $sameOutput
$report = Get-Content -LiteralPath (Join-Path $run 'report.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$case = $report.Cases[0]
if ($case.Left.ExitCode -ne 7 -or $case.Right.ExitCode -ne 7 -or $case.Changes.Count -ne 0) {
    throw 'Expected both children to exit 7 with matching observations'
}
Write-Host 'All comparisons and launcher exit codes matched the expected observations.'
