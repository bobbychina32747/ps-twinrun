[CmdletBinding()]
param(
    [string]$Script,
    [string]$OutputDirectory = (Join-Path ([IO.Path]::GetTempPath()) 'ps-twinrun'),
    [switch]$NoOpen,
    [switch]$FailOnDifference
)

Set-StrictMode -Version 2
$ErrorActionPreference = 'Stop'
$project = Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot 'Report.ps1')

function Get-Engine($Path, $Name, [int]$Major) {
    $probe = & $Path -NoLogo -NoProfile -NonInteractive -Command '$PSVersionTable.PSVersion.ToString() + [char]124 + [Console]::OutputEncoding.CodePage'
    if ($LASTEXITCODE -ne 0 -or "$probe" -notmatch '^(\d+\.\d+[.\d]*)\|(\d+)$') {
        throw "Could not read the version from $Name."
    }
    $version = [version]$Matches[1]
    $codePage = [int]$Matches[2]
    if ($version.Major -ne $Major -or ($Major -eq 7 -and $version -lt [version]'7.4') -or
        ($Major -eq 5 -and $version.Minor -ne 1)) {
        throw "Found $Name $version. This demo requires Windows PowerShell 5.1 and PowerShell 7.4 or newer (7.x)."
    }
    [pscustomobject]@{ Name = $Name; Version = $version.ToString(); Path = $Path; CodePage = $codePage }
}

function Get-OutputFiles([string]$Root) {
    $directories = New-Object 'System.Collections.Generic.Stack[string]'
    $directories.Push($Root)
    while ($directories.Count -gt 0) {
        foreach ($entry in [IO.DirectoryInfo]::new($directories.Pop()).GetFileSystemInfos()) {
            if ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw "Cannot compare a link in the output tree: $($entry.Name)"
            }
            if ($entry -is [IO.DirectoryInfo]) {
                $directories.Push($entry.FullName)
                continue
            }
            $stream = $entry.OpenRead()
            $sha = [Security.Cryptography.SHA256]::Create()
            try {
                $hash = [BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-', '').ToLowerInvariant()
                $stream.Position = 0
                $prefix = New-Object byte[] ([int][Math]::Min(32L, $stream.Length))
                $read = $stream.Read($prefix, 0, $prefix.Length)
                [pscustomobject][ordered]@{
                    Path = $entry.FullName.Substring($Root.Length + 1).Replace('\', '/')
                    Bytes = $stream.Length
                    SHA256 = $hash
                    Hex = [BitConverter]::ToString($prefix, 0, $read).Replace('-', ' ')
                }
            } finally { $stream.Dispose(); $sha.Dispose() }
        }
    }
}

function Invoke-Case($Engine, [string]$Target, [string]$Work, [string]$ModernShell) {
    [void][IO.Directory]::CreateDirectory($Work)
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = $Engine.Path
    $start.Arguments = '-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + $Target + '"'
    $start.WorkingDirectory = $Work
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.StandardOutputEncoding = [Text.Encoding]::GetEncoding($Engine.CodePage)
    $start.StandardErrorEncoding = $start.StandardOutputEncoding
    $start.EnvironmentVariables['TWINRUN_PWSH'] = $ModernShell
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $start
    try {
        [void]$process.Start()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        [pscustomobject][ordered]@{
            ExitCode = $process.ExitCode
            Stdout = $stdout.GetAwaiter().GetResult()
            Stderr = $stderr.GetAwaiter().GetResult()
            Files = @(Get-OutputFiles $Work | Sort-Object -Property Path)
        }
    } finally { $process.Dispose() }
}

function Open-Report([string]$Path) {
    if (!$NoOpen) {
        try { Start-Process -FilePath $Path -ErrorAction Stop }
        catch { Write-Warning "Could not start the default browser. Open the report at the path above." }
    }
}

try {
    $legacy = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $modern = Get-Command pwsh.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    $installed = Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe'
    $modernPath = if ($modern) { $modern.Source } elseif ([IO.File]::Exists($installed)) { $installed }
    try {
        if (!$modernPath) { throw 'PowerShell 7 was not found. Install PowerShell 7.4+ to run a live comparison.' }
        $left = Get-Engine $legacy 'Windows PowerShell' 5
        $right = Get-Engine $modernPath 'PowerShell' 7
    } catch {
        [Console]::Error.WriteLine($_.Exception.Message)
        $preview = Join-Path $project 'docs\example.html'
        if (!$Script -and [IO.File]::Exists($preview)) {
            Write-Host "Recorded example (no live run): $preview"
            Open-Report $preview
        }
        exit 2
    }

    if ($Script) {
        $source = Get-Item -LiteralPath $Script
        if ($source -isnot [IO.FileInfo] -or $source.Extension -ine '.ps1') { throw 'Supply a .ps1 file with -Script.' }
        $cases = @(@{ Id='custom'; Title=$source.Name; File=$source.FullName; Hint='Both processes ran the same script in separate working directories.' })
    } else {
        $examples = Join-Path $project 'examples'
        $cases = @(
            @{ Id='encoding'; Title='Default file encoding'; File=(Join-Path $examples '01-file-encoding.ps1'); Hint='Write the same two Chinese characters with Out-File. Compare the bytes of message.txt.' }
            @{ Id='arguments'; Title='Native argument passing'; File=(Join-Path $examples '02-native-arguments.ps1'); Hint='Pass a path with spaces, an empty string and quoted text to the same native receiver.' }
            @{ Id='exit-code'; Title='Native failure handling'; File=(Join-Path $examples '03-native-exit.ps1'); Hint='A native command exits with code 7. Both scripts request terminating errors and enable native error handling.' }
        )
    }
    $parent = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputDirectory)
    $run = Join-Path $parent ((Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0,12))
    [void][IO.Directory]::CreateDirectory($run)
    $results = foreach ($case in $cases) {
        $work = Join-Path $run $case.Id
        $a = Invoke-Case $left $case.File (Join-Path $work 'ps5') $right.Path
        $b = Invoke-Case $right $case.File (Join-Path $work 'ps7') $right.Path
        $changes = @(foreach ($field in 'ExitCode','Stdout','Stderr','Files') {
            $v1 = ConvertTo-Json -Compress -Depth 5 -InputObject $a.$field
            $v2 = ConvertTo-Json -Compress -Depth 5 -InputObject $b.$field
            if (![string]::Equals($v1, $v2, [StringComparison]::Ordinal)) { $field }
        })
        $status = if ($changes.Count) { 'DIFF: ' + ($changes -join ', ') } else { 'SAME' }
        Write-Host ("[{0}] {1}" -f $status, $case.Title)
        [pscustomobject][ordered]@{ Id=$case.Id; Title=$case.Title; Hint=$case.Hint; Changes=$changes; Left=$a; Right=$b }
    }
    $report = [ordered]@{ LeftVersion=$left.Version; RightVersion=$right.Version; Cases=@($results) }
    $utf8 = New-Object Text.UTF8Encoding($false)
    [IO.File]::WriteAllText((Join-Path $run 'report.json'), (ConvertTo-Json -Depth 9 -InputObject $report), $utf8)
    $htmlPath = Join-Path $run 'report.html'
    [IO.File]::WriteAllText($htmlPath, (New-ComparisonHtml $report), $utf8)
    Write-Host "Report: $htmlPath"
    Open-Report $htmlPath
    if ($FailOnDifference -and ($report.Cases | Where-Object { $_.Changes.Count -gt 0 })) {
        exit 3
    }
    exit 0
} catch {
    [Console]::Error.WriteLine('PS TwinRun: ' + $_.Exception.Message)
    exit 1
}
