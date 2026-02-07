function Write-TakeControlLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Message,
        [ValidateSet('Info', 'Warning', 'Error', 'Success', 'Verbose', 'Diagnosis')] [string]$Level = 'Info',
        [string]$LogPath
    )
    
    $timestamp = Get-Date -Format "HH:mm:ss"
    $logLine = "[$timestamp] [$Level] $Message"
    
    if ($LogPath) {
        $logLine | Out-File -FilePath $LogPath -Append -Encoding UTF8
    }
    
    switch ($Level) {
        'Info' { Write-Host $logLine -ForegroundColor Gray }
        'Success' { Write-Host $logLine -ForegroundColor Green }
        'Warning' { Write-Warning $Message }
        'Error' { Write-Error $Message }
        'Verbose' { Write-Verbose $Message }
        'Diagnosis' { Write-Host $logLine -ForegroundColor Cyan }
    }
}
