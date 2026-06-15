# Useful Office 365 PowerShell Scripts

A collection of handy PowerShell scripts for managing Microsoft Office 365, Exchange Online, and local Windows environments.

> **⚠️ Warning:** Please read each script and test in a non-production environment before using it in production.

---

## 📜 Available Scripts

### `AllGroupsAndMailboxes.ps1`
Connects to Exchange Online and exports memberships and permissions for Distribution Lists, Microsoft 365 Groups, and Shared Mailboxes to `C:\Temp\AllGroupsAndMailboxes.csv`.

### `addusertocalendars.ps1`
Connects to Exchange Online and adds a specific user to a defined list of mailbox calendars, assigning them a specified mailbox folder permission role (e.g., *Editor*).

### `removefromdl.ps1`
Connects to Exchange Online and removes a specified user from a provided array of distribution lists, then gracefully disconnects from Exchange Online.

### `Get-UserProfiles.ps1`
Finds all user profiles on the local PC using WMI/CIM and displays key information about each one, including the Username, SID, Profile Path, Last Used Time, and whether the profile is currently loaded.
