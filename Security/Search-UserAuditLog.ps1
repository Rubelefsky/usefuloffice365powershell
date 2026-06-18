<#
.SYNOPSIS
    Searches the Unified Audit Log for mailbox and account activity tied to a
    compromised M365 user over the past N days.

.DESCRIPTION
    Pulls Exchange/Purview audit events via Search-UnifiedAuditLog and breaks
    them into persistence-relevant categories: inbox rules, forwarding,
    delegate/permission changes, mailbox logins, and message access/sends.
    Designed for business email compromise (BEC) investigation.

.PARAMETER UserPrincipalName
    UPN of the compromised account.

.PARAMETER Days
    Lookback window. Default 30. UAL retains 90 days (E3) / 1 yr (E5) by default.

.EXAMPLE
    .\Search-UserAuditLog.ps1 -UserPrincipalName jdoe@contoso.com

.NOTES
    Requires: ExchangeOnlineManagement module + View-Only Audit Logs role.
    Auditing must have been enabled at the time of the events.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$UserPrincipalName,

    [int]$Days = 30,

    [string]$OutDir = ".\UAL_$($UserPrincipalName.Split('@')[0])_$(Get-Date -Format 'yyyyMMdd')"
)

# --- Connect ---
if (-not (Get-Module -ListAvailable -Name ExchangeOnlineManagement)) {
    Write-Host "Installing ExchangeOnlineManagement..." -ForegroundColor Yellow
    Install-Module ExchangeOnlineManagement -Scope CurrentUser -Force
}
Import-Module ExchangeOnlineManagement
# -DisableWAM avoids the Windows broker (WAM) code path, which fails with
# "Method not found: ...WithBroker" when an older Microsoft.Identity.Client
# (MSAL) DLL is already loaded in the session (commonly by Microsoft.Graph).
try {
    Connect-ExchangeOnline -ShowBanner:$false -DisableWAM -ErrorAction Stop
} catch {
    Write-Warning "Connect with -DisableWAM failed, retrying with device code auth..."
    Connect-ExchangeOnline -ShowBanner:$false -Device
}

$start = (Get-Date).AddDays(-$Days)
$end   = Get-Date
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null

# --- Helper: paged UAL search (handles >5000 results) ---
function Invoke-UALSearch {
    param([string[]]$Operations, [string]$Label)

    Write-Host "Searching: $Label ..." -ForegroundColor Cyan
    $session = [guid]::NewGuid().ToString()
    $all = @()
    do {
        $page = Search-UnifiedAuditLog -StartDate $start -EndDate $end `
            -UserIds $UserPrincipalName `
            -Operations $Operations `
            -SessionId $session -SessionCommand ReturnLargeSet `
            -ResultSize 5000
        if ($page) { $all += $page }
    } while ($page.Count -eq 5000)

    # ReturnLargeSet can dupe; de-dupe on Identity
    $all = $all | Sort-Object Identity -Unique
    Write-Host "  -> $($all.Count) events" -ForegroundColor Gray
    return $all
}

# --- Helper: expand JSON AuditData into flat objects ---
function Expand-Audit {
    param($Records)
    $Records | ForEach-Object {
        $d = $_.AuditData | ConvertFrom-Json
        [pscustomobject]@{
            TimeUTC      = $_.CreationDate
            Operation    = $d.Operation
            UserId       = $d.UserId
            ClientIP     = $d.ClientIP
            ResultStatus = $d.ResultStatus
            Workload     = $d.Workload
            SiteUrl      = $d.SiteUrl
            SourceFile   = $d.SourceFileName
            FilePath     = $d.ObjectId
            UserAgent    = $d.UserAgent
            Parameters   = ($d.Parameters | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join '; '
            ObjectId     = $d.ObjectId
            Detail       = ($d | ConvertTo-Json -Depth 6 -Compress)
        }
    } | Sort-Object TimeUTC
}

# --- Category 1: Inbox rules (top BEC persistence) ---
$rules = Invoke-UALSearch -Label "Inbox / transport rules" -Operations @(
    'New-InboxRule','Set-InboxRule','Enable-InboxRule','Disable-InboxRule','Remove-InboxRule',
    'UpdateInboxRules','New-TransportRule','Set-TransportRule'
)

# --- Category 2: Forwarding / mailbox config ---
$fwd = Invoke-UALSearch -Label "Forwarding & mailbox config" -Operations @(
    'Set-Mailbox','Set-MailboxAutoReplyConfiguration'
)

# --- Category 3: Delegate / permission changes ---
$perms = Invoke-UALSearch -Label "Delegate & permission changes" -Operations @(
    'Add-MailboxPermission','Remove-MailboxPermission','Add-RecipientPermission',
    'Add-MailboxFolderPermission','Set-MailboxFolderPermission'
)

# --- Category 4: Mailbox logins / access ---
$access = Invoke-UALSearch -Label "Mailbox logins & access" -Operations @(
    'MailboxLogin','UserLoggedIn','UserLoginFailed','MailItemsAccessed'
)

# --- Category 5: Message activity (sent / moved / deleted) ---
$msg = Invoke-UALSearch -Label "Message send / move / delete" -Operations @(
    'Send','SendAs','SendOnBehalf','HardDelete','SoftDelete','MoveToDeletedItems','Move'
)

# --- Category 6: SharePoint / OneDrive access ---
$spo = Invoke-UALSearch -Label "SharePoint / OneDrive access" -Operations @(
    'FileAccessed','FileAccessedExtended','FileDownloaded','FilePreviewed',
    'FileSyncDownloadedFull','FileSyncDownloadedPartial',
    'FileModified','FileUploaded','FileDeleted','FileCopied','FileMoved',
    'SharingSet','SharingInvitationCreated','AnonymousLinkCreated','AnonymousLinkUsed',
    'AddedToSecureLink','SecureLinkCreated','CompanyLinkCreated',
    'SearchQueryPerformed','PageViewed'
)

# --- Export each category ---
$sets = @{
    '1_InboxRules'   = $rules
    '2_Forwarding'   = $fwd
    '3_Permissions'  = $perms
    '4_Logins'       = $access
    '5_Messages'     = $msg
    '6_SharePoint'   = $spo
}
foreach ($k in $sets.Keys) {
    if ($sets[$k]) {
        Expand-Audit $sets[$k] | Export-Csv "$OutDir\$k.csv" -NoTypeInformation -Encoding UTF8
    }
}

# --- Triage summary ---
Write-Host "`n--- TRIAGE SUMMARY ---" -ForegroundColor Green
Write-Host "Inbox rule changes:   $($rules.Count)"   -ForegroundColor $(if($rules){'Red'}else{'Gray'})
Write-Host "Forwarding/config:    $($fwd.Count)"     -ForegroundColor $(if($fwd){'Red'}else{'Gray'})
Write-Host "Permission changes:   $($perms.Count)"   -ForegroundColor $(if($perms){'Red'}else{'Gray'})
Write-Host "Login events:         $($access.Count)"
Write-Host "Message activity:     $($msg.Count)"
Write-Host "SharePoint/OneDrive:  $($spo.Count)"  -ForegroundColor $(if($spo){'Yellow'}else{'Gray'})
Write-Host "`nDistinct client IPs across all events:" -ForegroundColor Cyan
($rules + $fwd + $perms + $access + $msg + $spo |
    ForEach-Object { ($_.AuditData | ConvertFrom-Json).ClientIP } |
    Where-Object {$_} | Sort-Object -Unique) -join "`n"

Write-Host "`nCSVs written to: $OutDir" -ForegroundColor Cyan
Disconnect-ExchangeOnline -Confirm:$false
