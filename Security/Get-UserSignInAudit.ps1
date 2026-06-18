<#
.SYNOPSIS
    Retrieves sign-in session data for a specific user over the past 30 days,
    including session IDs, login type, client app, device, IP, and location.

.DESCRIPTION
    Pulls Entra ID (Azure AD) sign-in logs via Microsoft Graph for breach
    investigation. Falls back to Unified Audit Log (Exchange/Purview) for
    mailbox-specific activity. Flags risky / unusual sign-ins.

.PARAMETER UserPrincipalName
    The UPN of the compromised account (e.g. jdoe@contoso.com).

.PARAMETER Days
    Lookback window in days. Default 30. (Graph sign-in logs retain ~30 days
    on most licenses; Premium P1/P2 extends this.)

.EXAMPLE
    .\Get-UserSignInAudit.ps1 -UserPrincipalName jdoe@contoso.com

.NOTES
    Requires: Microsoft.Graph module, AuditLog.Read.All + Directory.Read.All
    (delegated or app) consent. Entra ID P1/P2 required for sign-in logs.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$UserPrincipalName,

    [int]$Days = 30,

    [string]$OutputPath = ".\SignInAudit_$($UserPrincipalName.Split('@')[0])_$(Get-Date -Format 'yyyyMMdd').csv"
)

# --- Connect ---
$reqModules = @('Microsoft.Graph.Authentication','Microsoft.Graph.Reports')
foreach ($m in $reqModules) {
    if (-not (Get-Module -ListAvailable -Name $m)) {
        Write-Host "Installing $m..." -ForegroundColor Yellow
        Install-Module $m -Scope CurrentUser -Force -AllowClobber
    }
}

Connect-MgGraph -Scopes "AuditLog.Read.All","Directory.Read.All" -NoWelcome

# Raise the HTTP client timeout (default is short; large sign-in queries
# routinely exceed it and surface as "A task was canceled").
$PSDefaultParameterValues['Invoke-MgGraphRequest:Timeout'] = 600
try {
    [Microsoft.Graph.PowerShell.Authentication.GraphSession]::Instance.GraphHttpClient.Timeout = [timespan]::FromMinutes(10)
} catch { Write-Verbose "Could not set GraphHttpClient timeout directly: $_" }

# --- Build filter ---
$startDate = (Get-Date).AddDays(-$Days).ToString('yyyy-MM-ddTHH:mm:ssZ')
$filter = "userPrincipalName eq '$UserPrincipalName' and createdDateTime ge $startDate"

Write-Host "Querying sign-ins for $UserPrincipalName since $startDate..." -ForegroundColor Cyan

# --- Pull sign-in logs (manual paging, smaller batches, retry on cancel) ---
$signIns = [System.Collections.Generic.List[object]]::new()
$pageSize = 200          # smaller pages return before the timeout fires
$maxRetries = 3
try {
    $resp = $null
    $attempt = 0
    while ($true) {
        try {
            if (-not $resp) {
                $resp = Get-MgAuditLogSignIn -Filter $filter -Top $pageSize -ErrorAction Stop
            } else {
                if (-not $resp.AdditionalProperties.'@odata.nextLink') { break }
                $resp = Get-MgAuditLogSignIn -Filter $filter -Top $pageSize `
                        -Skip $signIns.Count -ErrorAction Stop
            }
            $attempt = 0
            if ($resp) { $resp | ForEach-Object { $signIns.Add($_) } }
            Write-Host "  retrieved $($signIns.Count) so far..." -ForegroundColor DarkGray
            if (-not $resp -or $resp.Count -lt $pageSize) { break }
        } catch {
            $attempt++
            if ($attempt -ge $maxRetries) { throw }
            $wait = [math]::Pow(2,$attempt) * 5
            Write-Warning "Page failed ($($_.Exception.Message)). Retry $attempt/$maxRetries in ${wait}s..."
            Start-Sleep -Seconds $wait
        }
    }
} catch {
    $msg = $_.Exception.Message
    if ($msg -match 'cancel|timeout|timed out') {
        Write-Error "Query timed out even after retries. Try a shorter -Days window (e.g. -Days 7) or run during off-peak hours. $msg"
    } elseif ($msg -match '403|Authorization|Forbidden') {
        Write-Error "Authorization failed - this is the licensing/consent case: confirm Entra ID P1/P2 and that AuditLog.Read.All was consented. $msg"
    } else {
        Write-Error "Failed to retrieve sign-in logs: $msg"
    }
    return
}

if (-not $signIns) {
    Write-Warning "No sign-in events found for $UserPrincipalName in the last $Days days."
    return
}

# --- Shape output ---
$report = $signIns | Select-Object `
    @{N='SessionId';        E={$_.AppDisplayName + '|' + $_.CorrelationId}}, `
    @{N='CorrelationId';    E={$_.CorrelationId}}, `
    @{N='SignInId';         E={$_.Id}}, `
    @{N='TimeUTC';          E={$_.CreatedDateTime}}, `
    @{N='UPN';              E={$_.UserPrincipalName}}, `
    @{N='Status';           E={if ($_.Status.ErrorCode -eq 0) {'Success'} else {"Fail($($_.Status.ErrorCode))"}}}, `
    @{N='ClientApp';        E={$_.ClientAppUsed}}, `
    @{N='AppDisplayName';   E={$_.AppDisplayName}}, `
    @{N='DeviceOS';         E={$_.DeviceDetail.OperatingSystem}}, `
    @{N='DeviceBrowser';    E={$_.DeviceDetail.Browser}}, `
    @{N='DeviceName';       E={$_.DeviceDetail.DisplayName}}, `
    @{N='IsManaged';        E={$_.DeviceDetail.IsManaged}}, `
    @{N='IPAddress';        E={$_.IPAddress}}, `
    @{N='City';             E={$_.Location.City}}, `
    @{N='State';            E={$_.Location.State}}, `
    @{N='Country';          E={$_.Location.CountryOrRegion}}, `
    @{N='MFAStatus';        E={$_.AuthenticationRequirement}}, `
    @{N='ConditionalAccess';E={$_.ConditionalAccessStatus}}, `
    @{N='RiskLevel';        E={$_.RiskLevelDuringSignIn}}, `
    @{N='RiskState';        E={$_.RiskState}} |
    Sort-Object TimeUTC

# --- Console summary ---
$report | Format-Table TimeUTC, Status, ClientApp, DeviceOS, IPAddress, Country, RiskLevel -AutoSize

Write-Host "`n--- Quick triage ---" -ForegroundColor Green
Write-Host "Total sign-ins: $($report.Count)"
Write-Host "Distinct IPs:   $(($report.IPAddress | Sort-Object -Unique).Count)"
Write-Host "Distinct countries: $(($report.Country | Where-Object {$_} | Sort-Object -Unique) -join ', ')"
$risky = $report | Where-Object { $_.RiskLevel -and $_.RiskLevel -ne 'none' }
if ($risky) { Write-Host "RISKY sign-ins flagged: $($risky.Count)" -ForegroundColor Red }

# --- Export ---
$report | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
Write-Host "`nExported to: $OutputPath" -ForegroundColor Cyan

Disconnect-MgGraph | Out-Null
