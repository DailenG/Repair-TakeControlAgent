function Test-TakeControlGatewayConnection {
    [CmdletBinding()]
    param(
        [hashtable]$Config
    )
    Write-TakeControlLog -Message "Testing connectivity to Take Control Gateway..." -Level Info -LogPath $Config.LogPath
    try {
        $tcpClient = New-Object System.Net.Sockets.TcpClient
        $connectOp = $tcpClient.BeginConnect($Config.GatewayHost, 443, $null, $null)
        $success = $connectOp.AsyncWaitHandle.WaitOne(3000, $false)
        if ($success) {
            Write-TakeControlLog -Message "Gateway Connection (TCP 443): Success" -Level Info -LogPath $Config.LogPath
        }
        else {
            Write-TakeControlLog -Message "Gateway Connection (TCP 443): Failed (Timeout)" -Level Warning -LogPath $Config.LogPath
        }
        $tcpClient.Close()
    }
    catch {
        Write-TakeControlLog -Message "Gateway Connection (TCP 443): Error - $_" -Level Warning -LogPath $Config.LogPath
    }
}
