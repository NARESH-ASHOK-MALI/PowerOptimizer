# Smarter parser for PowerOptimizer.bat
# Re-combines caret-continued lines before analysis to avoid parsing issues with multiline PowerShell commands.
$content = Get-Content 'd:\Personal_Projects\Testing\PowerOptimizer.bat'

$logicalLines = @()
$currentLine = ""
$currentLineNumStart = 1
$lineMapping = @() # maps logical line index to source line number start

for ($i = 0; $i -lt $content.Count; $i++) {
    $raw = $content[$i]
    $trimmed = $raw.TrimEnd()
    
    if ($currentLine -eq "") {
        $currentLineNumStart = $i + 1
    }
    
    if ($trimmed -match '\^$') {
        # remove the caret and trailing spaces, append with space
        $currentLine += ($trimmed -replace '\^$', '') + " "
    } else {
        $currentLine += $raw
        $logicalLines += $currentLine
        $lineMapping += $currentLineNumStart
        $currentLine = ""
    }
}

# Now analyze logical lines
$depth = 0
$issues = @()

for ($i = 0; $i -lt $logicalLines.Count; $i++) {
    $line = $logicalLines[$i]
    $trimmed = $line.Trim()
    $lineNum = $lineMapping[$i]
    
    if ($trimmed -eq "") { continue }
    if ($trimmed -match '^::' -or $trimmed -match '^REM' -or $trimmed -match '^#') { continue }
    
    # Check for block open / close on the logical line
    # (Since multiline commands are combined, parens in powershell strings won't end the line with '(' or ')' as CMD block markers)
    
    # In batch files, parenthesized blocks always start with '(' at the end of a command
    # e.g., if "%VAR%"=="1" (
    # or ) else (
    if ($trimmed -match '\(\s*$') {
        $depth++
    }
    
    # Check for commands inside block
    if ($depth -gt 0) {
        if ($trimmed -match '^call\s+:') {
            $issues += [PSCustomObject]@{
                Line = $lineNum
                Type = "call :label inside block"
                Content = $trimmed
            }
        }
        if ($trimmed -match '^::') {
            $issues += [PSCustomObject]@{
                Line = $lineNum
                Type = ":: comment inside block"
                Content = $trimmed
            }
        }
        if ($trimmed -match '^goto\s') {
            # Note: goto is allowed inside blocks in some cases, but can be problematic depending on label location.
            # Usually call :label is the one that breaks if /b or goto :eof is used inside the label.
            $issues += [PSCustomObject]@{
                Line = $lineNum
                Type = "goto inside block"
                Content = $trimmed
            }
        }
    }
    
    if ($trimmed -match '^\s*\)\s*(else\s*\()?$') {
        # Check if the line closes the block or opens an else block
        if ($trimmed -match 'else\s*\(') {
            # keeps the same depth (closes one, opens another)
        } else {
            $depth--
            if ($depth -lt 0) { $depth = 0 }
        }
    } elseif ($trimmed -match '^\s*\)\s*$') {
        $depth--
        if ($depth -lt 0) { $depth = 0 }
    }
}

Write-Host "=== SMARTER DEEP SCAN RESULTS ==="
Write-Host "Total issues found: $($issues.Count)"
Write-Host ""
foreach ($issue in $issues) {
    Write-Host ("Line {0} [{1}]:" -f $issue.Line, $issue.Type)
    Write-Host ("  {0}" -f ($issue.Content -replace '\s+', ' '))
    Write-Host ""
}
