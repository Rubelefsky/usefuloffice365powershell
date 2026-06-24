# Useful Office 365 PowerShell Scripts

A collection of handy PowerShell scripts for managing Microsoft Office 365, Exchange Online, and local Windows environments, organized by category.

> **⚠️ Warning:** Please read each script and test in a non-production environment before using it in production.

---

## 📜 Repository Structure

### Root Directory (General Utilities)

#### `AllGroupsAndMailboxes.ps1`
Connects to Exchange Online and exports memberships and permissions for Distribution Lists, Microsoft 365 Groups, and Shared Mailboxes to `C:\Temp\AllGroupsAndMailboxes.csv`.

#### `addusertocalendars.ps1`
Connects to Exchange Online and adds a specific user to a defined list of mailbox calendars, assigning them a specified mailbox folder permission role (e.g., *Editor*).

#### `removefromdl.ps1`
Connects to Exchange Online and removes a specified user from a provided array of distribution lists, then gracefully disconnects from Exchange Online.

#### `Get-UserProfiles.ps1`
Finds all user profiles on the local PC using WMI/CIM and displays key information about each one, including the Username, SID, Profile Path, Last Used Time, and whether the profile is currently loaded.

---

### 📂 Exchange

Scripts specific to Exchange Online mailbox and routing management.

#### `Get-MailboxStatistics.ps1`
A simple one-liner script to retrieve mailbox statistics for a specific user, including DisplayName, TotalItemSize, and ItemCount.

---

### 📂 Security

Scripts and playbooks for incident response, auditing, and investigating compromised accounts.

#### `Get-UserSignInAudit.ps1`
Retrieves Entra ID (Azure AD) sign-in session data for a specific user over the past 30 days via Microsoft Graph. Useful for breach investigation, flagging risky or unusual sign-ins.

#### `Search-UserAuditLog.ps1`
Searches the Unified Audit Log (Exchange/Purview) for mailbox and account activity tied to a compromised M365 user over the past N days. Designed for business email compromise (BEC) investigations.

#### `Incidentresponseplaybook.md`
A comprehensive incident response playbook for Microsoft 365 / Entra ID account compromise (BEC). Covers detection, triage, investigation, containment, eradication, and recovery.
