# Incident Response Playbook — Microsoft 365 / Entra ID Account Compromise (BEC)

| | |
|---|---|
| **Playbook ID** | IRP-001 |
| **Scope** | Compromise of one or more Microsoft 365 / Entra ID (Azure AD) user accounts, including business email compromise (BEC), credential theft, token/session theft, and MFA-fatigue / AiTM phishing. |
| **Out of scope** | On-prem AD-only compromise, ransomware on endpoints, and full tenant/global-admin takeover (escalate those to the major-incident process). This playbook *feeds* those if the blast radius grows. |
| **Owner** | `<IR-LEAD / SECURITY-TEAM>` |
| **Version** | 1.0 |
| **Last updated** | 2026-06-18 |
| **Supporting tooling** | `Get-UserSignInAuditv2.ps1`, `Search-UserAuditLogv2.ps1` |

> Fill in every `<PLACEHOLDER>` with your environment specifics (tenant, contacts, ticketing queue, approver) before this goes into the runbook library.

---

## 1. How to use this playbook

This is organized around the standard IR lifecycle (Preparation → Detection & Triage → Investigation → Containment → Eradication → Recovery → Post-incident). The two PowerShell scripts live in the **Investigation** phase, but containment and eradication contain the commands that actually stop the attacker.

**The golden rule for account compromise: contain before you finish investigating.** If you have a confirmed compromise and an active attacker, revoke sessions and disable the account *first* (Phase 4), then continue scoping. A perfect investigation against a live attacker who is still exfiltrating mail is a failure.

Speed targets (adjust to your SLAs):

| Severity | Trigger | Target time to containment |
|---|---|---|
| **SEV-1** | Finance/exec account, active wire-fraud thread, or admin role held by the account | 15 minutes |
| **SEV-2** | Confirmed compromise, standard user, evidence of persistence (rules/forwarding) | 1 hour |
| **SEV-3** | Suspected compromise, no confirmed attacker action yet | 4 hours |

---

## 2. Roles

| Role | Responsibility |
|---|---|
| **Incident Lead** | Owns the incident, declares severity, approves containment, runs comms cadence. |
| **Investigating Analyst** | Runs the scripts, interprets logs, documents IOCs and timeline. |
| **M365 Admin** | Executes containment/eradication actions requiring privileged access. |
| **Comms / Legal / Privacy** | Breach-notification assessment, regulatory clocks, customer/partner messaging. `<CONTACT>` |
| **Business Owner** | Manager of the affected user; confirms "is this activity legitimate?" |

---

## 3. Prerequisites (verify during Preparation, not during an incident)

**Modules / access**

- `Microsoft.Graph` (specifically `Microsoft.Graph.Authentication`, `Microsoft.Graph.Reports`) — used by `Get-UserSignInAuditv2.ps1`.
- `ExchangeOnlineManagement` — used by `Search-UserAuditLogv2.ps1`.
- Graph scopes: `AuditLog.Read.All`, `Directory.Read.All`. For containment also `User.ReadWrite.All`, `UserAuthenticationMethod.ReadWrite.All`.
- Exchange role: **View-Only Audit Logs** (read) and an admin role capable of mailbox changes for eradication.

**Licensing / retention realities (know these before you trust an empty result)**

- Entra **sign-in logs require Entra ID P1/P2**. Without it the Graph query returns 403 — the script flags this explicitly. An empty sign-in result on a free/standard license is *not* evidence of no activity.
- Sign-in log retention is ~7–30 days depending on license; P1/P2 extends it. The script defaults to a 30-day lookback.
- **Unified Audit Log** retention: ~90 days (E3) / up to 1 year (E5). Critically, **auditing must have been enabled at the time of the events** — if it was off, those events do not exist to be found.
- `MailItemsAccessed` (used to prove what the attacker *read*) requires the right licensing/E5 or add-on and mailbox auditing enabled.

**Pre-staged knowledge**

- Where the scripts live: `<REPO / PATH>`.
- Break-glass admin account and how to invoke it: `<PROCESS>`.
- Known-good corporate egress IP ranges and the org's expected sign-in countries (your "impossible travel" baseline): `<RANGES / COUNTRIES>`.

---

## 4. Phase 1 — Detection & Triage

### 4.1 Common triggers
- User reports they "got logged out," see sent mail they didn't send, or contacts received odd messages from them.
- Entra Identity Protection risk detection (impossible travel, anonymous IP, unfamiliar sign-in).
- Recipient/partner reports a suspicious invoice or banking-change email "from" the user (classic BEC).
- A mail-flow rule or auto-forward alert fires.
- Mass internal phishing originating from the account.

### 4.2 First 5 minutes — capture and classify
1. Open/echo the ticket: `<TICKETING QUEUE>`. Record reporter, time, and the single sentence of "what happened."
2. Identify the account(s): record exact UPN(s).
3. Ask the business owner the one question that resolves many cases: **"Did the user actually do X?"** (travel, new phone, new mail rule).
4. Set provisional severity from the table in §1. Finance/exec/admin = escalate immediately.
5. **Decide the order:** if there is an *active* fraud thread or admin privilege, jump to **Phase 4 (Containment) now**, then return here.

---

## 5. Phase 2 — Investigation & Scoping

Goal: establish **what happened, from where, when, and what the attacker touched/changed.** Run both scripts; they are complementary — sign-in logs tell you *access*, the UAL tells you *actions and persistence*.

> Evidence handling: run from a clean admin workstation, keep all CSV outputs, and note the exact command and timestamp in the ticket. Do not edit the CSVs; analyze copies. These files are your timeline source of truth.

### 5.1 Sign-in analysis — `Get-UserSignInAuditv2.ps1`

```powershell
.\Get-UserSignInAuditv2.ps1 -UserPrincipalName <user>@<domain> -Days 30
```

What it pulls (Entra sign-in logs via Graph) and why it matters in an investigation:

| Field(s) | What you're hunting |
|---|---|
| `IPAddress`, `City`/`State`/`Country` | Sign-ins from countries/IPs outside the user's baseline; hosting/VPN/anonymizer ranges. |
| `Status` (`Success` vs `Fail(<code>)`) | A burst of failures then a success = password spray / brute force / MFA fatigue that landed. |
| `ClientApp` | **Legacy auth** (IMAP/POP/SMTP/"Other clients") bypasses modern MFA — a top compromise vector and a red flag. |
| `MFAStatus` / `ConditionalAccess` | MFA "satisfied" from a strange IP can indicate **token/session theft (AiTM)** rather than a password guess. |
| `RiskLevel` / `RiskState` | Entra's own verdict; the script highlights anything not `none`. |
| `DeviceOS` / `DeviceName` / `IsManaged` | Unmanaged/unfamiliar device = attacker endpoint. |
| `CorrelationId` / `SignInId` | Pivot keys to tie sign-ins to specific sessions and to UAL events. |

Triage moves printed by the script: total sign-ins, distinct IPs, distinct countries, count of risky sign-ins. **Start from the risky/foreign sign-ins and work outward.** Record every attacker IP — it becomes an IOC you search for everywhere else.

Operational notes baked into the script:
- It pages in 200-record batches with exponential-backoff retry because large sign-in queries hit the default Graph HTTP timeout ("A task was canceled"). If it still times out, **shorten the window** (`-Days 7`).
- A **403/Forbidden** is the licensing/consent case (P1/P2 + `AuditLog.Read.All`), not "no activity."

### 5.2 Mailbox & account activity — `Search-UserAuditLogv2.ps1`

```powershell
.\Search-UserAuditLogv2.ps1 -UserPrincipalName <user>@<domain> -Days 30
```

Outputs one CSV per category into a dated folder. Read them in **priority order** — this is the order an attacker establishes persistence and does damage:

| File | Category | Why it's an attacker's first move |
|---|---|---|
| `1_InboxRules.csv` | New/Set/Enable inbox & transport rules | **#1 BEC persistence.** Rules that auto-delete, mark-as-read, or move replies to obscure folders hide the attacker's conversation from the real user. Inspect every rule's parameters. |
| `2_Forwarding.csv` | `Set-Mailbox`, auto-reply config | External auto-forwarding silently exfiltrates all mail. Auto-reply changes can be used for fraud. |
| `3_Permissions.csv` | Delegate / FullAccess / SendAs / folder perms | Grants the attacker (or a second compromised account) standing access even after the password reset. |
| `4_Logins.csv` | MailboxLogin, UserLoggedIn, UserLoginFailed, MailItemsAccessed | Confirms access and (with `MailItemsAccessed`) **which messages were read** — central to breach-notification scope. |
| `5_Messages.csv` | Send / SendAs / SendOnBehalf / delete / move | The fraudulent sends and the cleanup (HardDelete/SoftDelete/MoveToDeletedItems) that hides them. |
| `6_SharePoint.csv` | File access/download/share, anonymous links | Data exfil and lateral movement beyond mail; watch for `AnonymousLinkCreated`, `FileSyncDownloaded*`, bulk `FileDownloaded`. |

Each row is flattened from the JSON `AuditData` to expose `ClientIP`, `UserAgent`, `Operation`, `Parameters`, and the full `Detail` blob. The script's triage summary prints counts per category (rule/forwarding/permission counts in red if non-zero) and a **deduplicated list of every client IP** seen across all categories — cross-check these against the attacker IPs from §5.1.

Operational note: it connects with `-DisableWAM` to avoid the MSAL/WAM broker conflict that occurs when the Graph module has already loaded an older identity DLL in the session; it falls back to device-code auth automatically.

### 5.3 Build the timeline & IOC list
Consolidate into the ticket:
- **First malicious sign-in** (time, IP, country, client app, whether MFA was satisfied).
- **Attacker IOCs:** IP addresses, user-agents, any external forwarding addresses, rule names, delegate accounts.
- **Persistence found:** rules, forwarding, delegates, registered MFA methods, OAuth grants (see §6.3–6.5).
- **Impact:** messages sent, files accessed/downloaded, mail read (`MailItemsAccessed`).
- **Blast radius:** did the attacker pivot to other internal users? Search those UPNs the same way.

---

## 6. Phase 4 — Containment & Eradication

Run containment as soon as compromise is confirmed; do not wait for a complete investigation. Commands below are reference — validate cmdlet/module versions in your tenant. Document every action with timestamp and operator.

> Order matters: **revoke sessions in the same change window as the password reset.** A password reset alone does *not* kill an existing stolen refresh token — the attacker stays in until the token is revoked.

### 6.1 Cut off access (Containment)

```powershell
# Block sign-in
Update-MgUser -UserId <user>@<domain> -AccountEnabled:$false

# Force-reset the password (require change at next sign-in via portal or PIM)
# then immediately revoke all refresh/session tokens:
Revoke-MgUserSignInSession -UserId <user>@<domain>
```

- Reset the password to a strong random value; require change at next sign-in.
- If you cannot disable the account (business-critical), at minimum revoke sessions, reset the password, and apply a Conditional Access block on the attacker's location/IP.
- Add confirmed attacker IPs to your block list / CA named-location deny.

### 6.2 Remove mail persistence (Eradication)

```powershell
# Inbox rules — list, inspect, then remove the malicious ones
Get-InboxRule -Mailbox <user>@<domain> | Format-List Name,Enabled,Description,*Forward*,DeleteMessage,MoveToFolder
Remove-InboxRule -Mailbox <user>@<domain> -Identity "<rule name>"

# Forwarding at the mailbox level
Get-Mailbox <user>@<domain> | Format-List ForwardingAddress,ForwardingSmtpAddress,DeliverToMailboxAndForward
Set-Mailbox <user>@<domain> -ForwardingAddress $null -ForwardingSmtpAddress $null -DeliverToMailboxAndForward $false

# Org-level transport rules the attacker may have added (check the whole tenant)
Get-TransportRule | Where-Object { $_.WhenChanged -gt (Get-Date).AddDays(-30) }
```

### 6.3 Remove delegate / mailbox permissions

```powershell
Get-MailboxPermission   <user>@<domain> | Where-Object { $_.User -notlike 'NT AUTHORITY\SELF' }
Remove-MailboxPermission <user>@<domain> -User <attacker/unexpected> -AccessRights FullAccess

Get-RecipientPermission <user>@<domain>   # SendAs
Remove-RecipientPermission <user>@<domain> -Trustee <unexpected> -AccessRights SendAs
```

### 6.4 Kick out attacker-registered MFA — **do not skip this**
A frequent miss: the attacker registers their *own* MFA method, so even after a password reset they can re-authenticate. Review and remove anything the user doesn't recognize.

```powershell
Get-MgUserAuthenticationMethod -UserId <user>@<domain>
# Remove the rogue method with the matching method-specific cmdlet, e.g.:
# Remove-MgUserAuthenticationPhoneMethod / Remove-MgUserAuthenticationMicrosoftAuthenticatorMethod
```

### 6.5 Revoke illicit OAuth / app consent grants
AiTM and consent-phishing attacks often leave a malicious enterprise app with delegated mail permissions — persistence that survives password resets entirely.

```powershell
Get-MgUserOauth2PermissionGrant -UserId <user>@<domain>
# Review consented enterprise apps; remove any unrecognized grant/app.
```

### 6.6 Confirm eradication
Re-run `Search-UserAuditLogv2.ps1` (and re-list rules/perms/forwarding) and confirm no malicious rules, forwarding, delegates, MFA methods, or OAuth grants remain. Confirm no new risky sign-ins after the token revocation timestamp via `Get-UserSignInAuditv2.ps1`.

---

## 7. Phase 5 — Recovery

1. Re-enable the account once it is confirmed clean: `Update-MgUser -UserId <user>@<domain> -AccountEnabled:$true`.
2. Walk the user through **re-registering MFA from scratch** on a trusted device.
3. Restore legitimate mail flow / rules the user actually needs.
4. Verify with the user and business owner that mailbox, files, and sent items look correct.
5. **Heightened monitoring** for 14–30 days: re-run the sign-in script periodically; watch for the attacker's IPs/user-agents reappearing or a re-compromise.
6. Close only when no recurrence and all persistence is confirmed gone.

---

## 8. Phase 6 — Post-incident

- **Breach-notification assessment:** use `MailItemsAccessed` and SharePoint/OneDrive access (`4_Logins.csv`, `6_SharePoint.csv`) to determine whether regulated/PII data was exposed. Loop in `<LEGAL/PRIVACY>` and start any regulatory clocks early.
- **Lessons learned** within `<N>` business days: root cause (phishing? legacy auth? no MFA? token theft?), detection gap, time-to-contain vs target.
- **Hardening actions** that prevent the repeat:
  - Block **legacy authentication** tenant-wide (Conditional Access) — kills the IMAP/POP/SMTP bypass seen in §5.1.
  - Enforce phishing-resistant MFA for high-value roles; tighten Identity Protection risk policies.
  - Disable/alert on **external auto-forwarding** at the org level.
  - Confirm **Unified Audit Log and mailbox auditing are enabled tenant-wide** (so the next investigation isn't blind).
  - Restrict user consent to OAuth apps; require admin approval.
- **Update this playbook** with anything the incident taught you.

---

## 9. Appendix A — Script quick reference

| Script | Purpose | Key params | Output | Needs |
|---|---|---|---|---|
| `Get-UserSignInAuditv2.ps1` | Entra sign-in audit (access: IP, geo, device, MFA, risk) | `-UserPrincipalName` (req), `-Days` (def 30), `-OutputPath` | Single CSV + console triage | Microsoft.Graph; `AuditLog.Read.All`, `Directory.Read.All`; **Entra P1/P2** |
| `Search-UserAuditLogv2.ps1` | Unified Audit Log (actions/persistence: rules, fwd, perms, logins, messages, files) | `-UserPrincipalName` (req), `-Days` (def 30), `-OutDir` | 6 categorized CSVs + console triage | ExchangeOnlineManagement; **View-Only Audit Logs**; auditing enabled at event time |

**Common gotchas**
- 403 from the sign-in script = licensing/consent (P1/P2 + scope), *not* "clean."
- "A task was canceled" / timeout = window too large → use `-Days 7` or off-peak.
- Empty UAL result may mean auditing was disabled at the time, not that nothing happened.
- Sign-in log retention can be shorter than your `-Days`; older events may simply be gone.

## 10. Appendix B — Sign-in interpretation cheat sheet

| Observation | Likely meaning |
|---|---|
| Many `Fail` then a `Success` from same IP | Password spray / brute force that succeeded |
| `Success` + MFA satisfied from foreign IP, no failures | Token/session theft (AiTM phishing) — password may be unknown to attacker |
| `ClientApp` = legacy / "Other clients" | Legacy-auth MFA bypass |
| New `DeviceName`, `IsManaged = false` | Attacker-controlled endpoint |
| `RiskLevel` ≠ none | Entra Identity Protection flagged it — investigate first |

## 11. Appendix C — IOC tracker (fill during incident)

| Type | Value | First seen | Notes |
|---|---|---|---|
| IP | | | |
| User-agent | | | |
| Forwarding address | | | |
| Inbox rule name | | | |
| Delegate / SendAs account | | | |
| OAuth app / grant | | | |

## 12. Appendix D — Containment command index

| Action | Command |
|---|---|
| Disable sign-in | `Update-MgUser -UserId <upn> -AccountEnabled:$false` |
| Revoke tokens/sessions | `Revoke-MgUserSignInSession -UserId <upn>` |
| List inbox rules | `Get-InboxRule -Mailbox <upn>` |
| Remove inbox rule | `Remove-InboxRule -Mailbox <upn> -Identity "<name>"` |
| Kill forwarding | `Set-Mailbox <upn> -ForwardingAddress $null -ForwardingSmtpAddress $null -DeliverToMailboxAndForward $false` |
| List/remove FullAccess | `Get-MailboxPermission <upn>` / `Remove-MailboxPermission` |
| List/remove SendAs | `Get-RecipientPermission <upn>` / `Remove-RecipientPermission` |
| List MFA methods | `Get-MgUserAuthenticationMethod -UserId <upn>` |
| List OAuth grants | `Get-MgUserOauth2PermissionGrant -UserId <upn>` |
| Re-enable account | `Update-MgUser -UserId <upn> -AccountEnabled:$true` |

---

*End of playbook. Validate all commands against your current module versions and tenant configuration before relying on them in a live incident.*