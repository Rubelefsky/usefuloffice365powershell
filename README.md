# Useful Office 365 PowerShell Scripts

A collection of handy PowerShell scripts for managing Microsoft Office 365, Exchange Online, and local Windows environments.

> **⚠️ Warning:** Please read each script and test in a non-production environment before using it in production.

---

## 📜 Available Scripts

### General Management

#### `AllGroupsAndMailboxes.ps1`
Connects to Exchange Online and exports memberships and permissions for Distribution Lists, Microsoft 365 Groups, and Shared Mailboxes to `C:\Temp\AllGroupsAndMailboxes.csv`.

#### `addusertocalendars.ps1`
Connects to Exchange Online and adds a specific user to a defined list of mailbox calendars, assigning them a specified mailbox folder permission role (e.g., *Editor*).

#### `removefromdl.ps1`
Connects to Exchange Online and removes a specified user from a provided array of distribution lists, then gracefully disconnects from Exchange Online.

#### `Get-UserProfiles.ps1`
Finds all user profiles on the local PC using WMI/CIM and displays key information about each one, including the Username, SID, Profile Path, Last Used Time, and whether the profile is currently loaded.

### Security

#### `Security/Get-UserSignInAudit.ps1`
Retrieves sign-in session data for a specific user over the past 30 days, including session IDs, login type, client app, device, IP, and location. Pulls Entra ID (Azure AD) sign-in logs via Microsoft Graph for breach investigation.

#### `Security/Search-UserAuditLog.ps1`
Searches the Unified Audit Log for mailbox and account activity tied to a compromised M365 user over the past N days. Designed for business email compromise (BEC) investigation.
