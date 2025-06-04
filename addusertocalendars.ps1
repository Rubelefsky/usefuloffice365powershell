# Connect to Exchange Online (if not already connected)
Connect-ExchangeOnline

# Define the list of existing calendar owners
$ExistingUsers = @('user@domain.com', 'user@domain.com')

# Define the user to add to all calendars
$UserToAdd = 'user@domain.com'

# Define the access rights (e.g., Reviewer, Editor, etc.)
$AccessRights = 'Editor'

foreach ($CalendarOwner in $ExistingUsers) {
    $CalendarIdentity = $CalendarOwner + ":\Calendar"
    Add-MailboxFolderPermission -Identity $CalendarIdentity -User $UserToAdd -AccessRights $AccessRights
    Write-Host "Added $UserToAdd as $AccessRights to $CalendarIdentity"
}
