function Test-TakeControlFileSignature {
    [CmdletBinding()]
    param(
        [string]$Path,
        [hashtable]$Config
    )
    if (-not (Test-Path $Path)) { return $false }
    try {
        $sig = Get-AuthenticodeSignature -FilePath $Path
        return ($sig.Status -eq 'Valid' -and $sig.SignerCertificate.Subject -eq $Config.ExpectedSubject)
    }
    catch { return $false }
}
