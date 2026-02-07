function Get-TakeControlDownloadUrl {
    [CmdletBinding()]
    param(
        [hashtable]$Config,
        [string]$TargetVersion
    )
    if ($TargetVersion) {
        return "https://swi-rc.cdn-sw.net/n-central/updates/json/TakeControlCheckAndReInstall_$TargetVersion.json"
    }
    return $Config.ManifestUrl
}
