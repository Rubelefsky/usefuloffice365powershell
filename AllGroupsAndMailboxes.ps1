Connect-ExchangeOnline -ShowBanner:$false

$results = [System.Collections.Generic.List[PSObject]]::new()

# --- Distribution Lists ---
Write-Host "[*] Processing Distribution Lists..." -ForegroundColor Cyan
foreach ($dl in (Get-DistributionGroup -ResultSize Unlimited)) {
    Get-DistributionGroupMember $dl.Identity -ResultSize Unlimited | ForEach-Object {
        $results.Add([PSCustomObject]@{
            ObjectType  = "DistributionList"
            GroupName   = $dl.DisplayName
            GroupEmail  = $dl.PrimarySmtpAddress
            MemberName  = $_.DisplayName
            MemberEmail = $_.PrimarySmtpAddress
            AccessType  = "Member"
        })
    }
}

# --- Microsoft 365 Groups ---
Write-Host "[*] Processing Microsoft 365 Groups..." -ForegroundColor Cyan
foreach ($grp in (Get-UnifiedGroup -ResultSize Unlimited)) {
    Get-UnifiedGroupLinks $grp.Identity -LinkType Members | ForEach-Object {
        $results.Add([PSCustomObject]@{
            ObjectType  = "M365Group"
            GroupName   = $grp.DisplayName
            GroupEmail  = $grp.PrimarySmtpAddress
            MemberName  = $_.DisplayName
            MemberEmail = $_.PrimarySmtpAddress
            AccessType  = "Member"
        })
    }
    Get-UnifiedGroupLinks $grp.Identity -LinkType Owners | ForEach-Object {
        $results.Add([PSCustomObject]@{
            ObjectType  = "M365Group"
            GroupName   = $grp.DisplayName
            GroupEmail  = $grp.PrimarySmtpAddress
            MemberName  = $_.DisplayName
            MemberEmail = $_.PrimarySmtpAddress
            AccessType  = "Owner"
        })
    }
}

# --- Shared Mailboxes ---
Write-Host "[*] Processing Shared Mailboxes..." -ForegroundColor Cyan
foreach ($mbx in (Get-Mailbox -RecipientTypeDetails SharedMailbox -ResultSize Unlimited)) {
    Get-MailboxPermission $mbx.Identity |
        Where-Object { $_.AccessRights -contains "FullAccess" -and $_.User -notlike "NT AUTHORITY\*" -and !$_.IsInherited } |
        ForEach-Object {
            $results.Add([PSCustomObject]@{
                ObjectType  = "SharedMailbox"
                GroupName   = $mbx.DisplayName
                GroupEmail  = $mbx.PrimarySmtpAddress
                MemberName  = $_.User
                MemberEmail = $_.User
                AccessType  = "FullAccess"
            })
        }
    Get-RecipientPermission $mbx.Identity |
        Where-Object { $_.AccessRights -contains "SendAs" -and $_.Trustee -notlike "NT AUTHORITY\*" } |
        ForEach-Object {
            $results.Add([PSCustomObject]@{
                ObjectType  = "SharedMailbox"
                GroupName   = $mbx.DisplayName
                GroupEmail  = $mbx.PrimarySmtpAddress
                MemberName  = $_.Trustee
                MemberEmail = $_.Trustee
                AccessType  = "SendAs"
            })
        }
}

$results | Export-Csv "C:\Temp\AllGroupsAndMailboxes.csv" -NoTypeInformation -Encoding UTF8
Write-Host "[+] Exported $($results.Count) rows to C:\Temp\AllGroupsAndMailboxes.csv" -ForegroundColor Green
