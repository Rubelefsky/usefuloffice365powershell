# usefuloffice365powershell
Useful Office 365 Powershell scripts

<h2>Please read each script and test before using in production</h2>

<h4>AllGroupsAndMailboxes.ps1</h4>
<p>Connects to Exchange Online and exports memberships and permissions for Distribution Lists, Microsoft 365 Groups, and Shared Mailboxes to <em>C:\Temp\AllGroupsAndMailboxes.csv</em>.</p>

<h4>addusertocalendars.ps1</h4>
<p>Connects to Exchange Online and adds one user to a list of mailbox calendars using the specified mailbox folder permission role (for example, <em>Editor</em>).</p>

<h4>removefromdl.ps1</h4>
<p>Connects to Exchange Online and removes a specified user from a provided list of distribution lists, then disconnects from Exchange Online.</p>
