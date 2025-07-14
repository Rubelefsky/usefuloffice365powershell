# Connect to Exchange Online
Connect-ExchangeOnline

# Specify the user's email address
$userEmail = "user@email.com"

# List of DLs to remove the user from (can be group names or email addresses)
$distributionLists = @(
    "dl@email.com",
    "dl@email.com"
    
)

foreach ($dl in $distributionLists) {
    try {
        Remove-DistributionGroupMember -Identity $dl -Member $userEmail -Confirm:$false
        Write-Host "Removed $userEmail from $dl"
    } catch {
        Write-Host "Failed to remove $userEmail from $dl. Error: $_"
    }
}

# Disconnect from Exchange Online
Disconnect-ExchangeOnline
