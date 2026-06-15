# Get-UserProfiles.ps1
# Finds all user profiles on the local PC and displays key information about each one.

$profiles = Get-CimInstance -ClassName Win32_UserProfile | Where-Object { -not $_.Special }

$results = foreach ($profile in $profiles) {
    $sid = $profile.SID
    $localPath = $profile.LocalPath
    $lastUseTime = $profile.LastUseTime
    $loaded = $profile.Loaded

    # Attempt to resolve SID to a username
    try {
        $objSID = New-Object System.Security.Principal.SecurityIdentifier($sid)
        $username = $objSID.Translate([System.Security.Principal.NTAccount]).Value
    } catch {
        $username = "Unknown / Orphaned SID"
    }

    [PSCustomObject]@{
        Username    = $username
        SID         = $sid
        ProfilePath = $localPath
        LastUsed    = $lastUseTime
        Loaded      = $loaded
    }
}

$results | Sort-Object LastUsed -Descending | Format-Table -AutoSize
