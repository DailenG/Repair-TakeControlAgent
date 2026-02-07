function Wait-TakeControlAnimation {
    <#
    .SYNOPSIS
        Blocking wait loop with visual feedback (KITT Scanner).
    .DESCRIPTION
        Polls the provided condition scriptblock.
        Falls back to simple logging if running in RMM (Headless) or Remote PSSession.
    #>
    [CmdletBinding()]
    param(
        [string]$Activity = "Processing...",
        [ScriptBlock]$Condition,
        [int]$TimeoutSeconds = 60,
        [hashtable]$Config
    )

    # Detect Headless (RMM) or Remote Sessions to avoid log spam/cursor errors
    if ([Console]::IsOutputRedirected -or $Host.Name -match 'Remote') {
        Write-TakeControlLog -Message "$Activity (Waiting up to $TimeoutSeconds seconds)..." -Level Info -LogPath $Config.LogPath
        $timer = [System.Diagnostics.Stopwatch]::StartNew()
        while ($timer.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
            if (& $Condition) { return $true }
            Start-Sleep -Seconds 2
        }
        return $false
    }

    # Visual Animation Setup
    $Width = 20; $pos = 0; $direction = 1; $bar = "■■■" 
    
    # Try/Catch on Cursor manipulation because it fails in ISE/VSCode
    try { [Console]::CursorVisible = $false } catch {}

    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    $success = $false

    try {
        while ($timer.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
            if (& $Condition) { $success = $true; break }

            # Render Frame
            Write-Host "`r" -NoNewline
            $leftPadding = " " * $pos
            $rightPadding = " " * ($Width - $pos)
            Write-Host "$Activity [$leftPadding" -NoNewline
            Write-Host $bar -ForegroundColor Red -NoNewline
            Write-Host "$rightPadding] " -NoNewline

            # Update Physics
            $pos += $direction
            if ($pos -ge ($Width - $bar.Length) -or $pos -le 0) { $direction *= -1 }
            
            Start-Sleep -Milliseconds 50
        }
    }
    finally {
        # Ensure cursor is restored even if script crashes/Ctrl+C
        Write-Host "`r" -NoNewline
        Write-Host (" " * ($Width + $Activity.Length + 10)) -NoNewline # Clear Line
        Write-Host "`r" -NoNewline
        try { [Console]::CursorVisible = $true } catch {}
    }

    return $success
}
