function ConvertTo-HtmlText($Value) {
    [Net.WebUtility]::HtmlEncode([string]$Value)
}

function New-ObservationHtml($Observation) {
    $lines = @(foreach ($name in 'Stdout','Stderr') {
        if ($Observation.$name.Length) {
            '<div class="output-label">' + $name + '</div><pre>' + (ConvertTo-HtmlText $Observation.$name) + '</pre>'
        }
    })
    $files = @(foreach ($file in $Observation.Files) {
        $tail = if ($file.Bytes -gt 32) { ' &hellip;' } else { '' }
        '<div class="file"><div class="fileline"><strong>' + (ConvertTo-HtmlText $file.Path) +
            '</strong><span>' + $file.Bytes + ' bytes</span></div><code>' + $file.Hex + $tail +
            '</code><details><summary>SHA-256</summary><code>' + $file.SHA256 + '</code></details></div>'
    })
    $empty = if (!$lines.Count -and !$files.Count) { '<p class="empty">No text or files produced.</p>' } else { '' }
    ($lines -join '') + ($files -join '') + $empty
}

function New-ComparisonHtml($Report) {
    $changed = @($Report.Cases | Where-Object { $_.Changes.Count -gt 0 }).Count
    $cards = @(foreach ($case in $Report.Cases) {
        $changedFields = @($case.Changes | ForEach-Object {
            switch ($_) { 'Stdout' {'stdout'} 'Stderr' {'stderr'} 'ExitCode' {'exit code'} 'Files' {'files'} }
        })
        $badge = if ($changedFields.Count) { '<span class="diff">Diff &middot; ' + ($changedFields -join ', ') + '</span>' }
                 else { '<span class="same">Same observations</span>' }
        $panes = @(foreach ($side in 'Left','Right') {
            $engineTitle = if ($side -eq 'Left') { 'Windows PowerShell ' + $Report.LeftVersion } else { 'PowerShell ' + $Report.RightVersion }
            $data = $case.$side
            '<div class="pane"><div class="engine"><strong>' + (ConvertTo-HtmlText $engineTitle) +
                '</strong><span>exit ' + $data.ExitCode + '</span></div>' + (New-ObservationHtml $data) + '</div>'
        })
        '<section id="' + (ConvertTo-HtmlText $case.Id) + '"><div class="casehead"><h2>' +
            (ConvertTo-HtmlText $case.Title) + '</h2>' + $badge + '</div><p class="hint">' +
            (ConvertTo-HtmlText $case.Hint) + '</p><div class="split">' + ($panes -join '') + '</div></section>'
    })
    $template = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'report-template.html'))
    $template.Replace('<!--COUNT-->', [string]$Report.Cases.Count).Replace('<!--CHANGED-->', [string]$changed).Replace('<!--CASES-->', ($cards -join [Environment]::NewLine))
}
