# Authentication

The Defender portion of the exporter calls the Microsoft Graph endpoint `security/runHuntingQuery`, which requires **`ThreatHunting.Read.All`**. A full 13-file export also requires **`User.Read.All`**, **`LicenseAssignment.Read.All`**, and **`AuditLog.Read.All`**, plus an interactive Exchange Online/Purview session for Copilot audit data. You prove your Graph identity in one of two ways. Pick the one that fits.

| Path | Best when | You supply |
| --- | --- | --- |
| **A — Bring your own access token** | A quick, one-off export | `-AccessToken` |
| **B — App registration (client credentials)** | Repeatable or automated runs | `-TenantId`, `-ClientId`, `-ClientSecret` |

> **Golden rule:** never paste tokens or secrets into files. Pass them **at runtime only**. The tool never logs or stores them.

---

## Path A — bring your own access token

An access token is a short-lived string that says "Graph, let me in." It's the fastest way to get going.

**Where to get one quickly:**

- From the [Microsoft Graph Explorer](https://developer.microsoft.com/graph/graph-explorer) after signing in (copy the access token from the **Access token** tab), or
- From the Azure CLI, or
- From any existing tool in your environment that already mints Graph tokens.

For the full 13-file export, the delegated token must contain all four Graph
permissions listed above, and the signed-in user must have a supported Entra or
Defender read role for the requested data. Tenant admin consent is required. The
Copilot collector separately needs an interactive Exchange Online session whose
user has **View-Only Audit Logs** or **Audit Logs**:

```powershell
Connect-ExchangeOnline
```

**Use it (single-line, paste directly into PowerShell):**

```powershell
.\Invoke-AISolutionsExport.ps1 -StartDate '2026-01-01' -EndDate '2026-07-01' -OutputDirectory 'C:\AI_Usage_Data' -AccessToken '<YOUR_ACCESS_TOKEN>' -IncludeSectionA
```

Replace `2026-01-01` / `2026-07-01` with your date window and `C:\AI_Usage_Data` with your data folder. Replace `<YOUR_ACCESS_TOKEN>` with the token you copied.

> ⏱️ **Tokens expire after ~1 hour.** If a long export dies partway with a `401`, your token likely expired — get a fresh one and re-run. See [troubleshooting.md](troubleshooting.md).

---

## Path B — app registration (client credentials)

An app registration is a reusable identity for unattended runs. Set it up once, then reuse it.

<details>
<summary><strong>One-time setup (click to expand)</strong></summary>

1. **Register an app** in the Microsoft Entra admin center → *App registrations* → *New registration*. Give it a name; leave redirect URI blank.
2. **Add the permissions:** in the app's *API permissions* → *Add a permission* → *Microsoft Graph* → **Application permissions** → add `ThreatHunting.Read.All`, `User.Read.All`, `LicenseAssignment.Read.All`, and `AuditLog.Read.All`.
3. **Grant admin consent** for all four permissions. For Microsoft Graph application permissions, a **Privileged Role Administrator** or **Global Administrator** must grant tenant-wide consent. Every status must show a green check.
4. **Create a client secret:** *Certificates & secrets* → *New client secret* → copy the **Value** immediately (you can't see it again).
5. **Note three values:** the **Directory (tenant) ID**, the **Application (client) ID**, and the **secret value**.

</details>

**Use it — establish the Purview session, then run the two commands below:**

```powershell
Connect-ExchangeOnline
```

The interactive session is separate from the Graph app credentials and is
required by `Search-UnifiedAuditLog`. Assign its user **View-Only Audit Logs**
(read/export) or **Audit Logs** in Exchange Online. Purview **Audit Reader** or
**Audit Manager** supports portal search/export, but eDiscovery roles alone do not
satisfy the cmdlet prerequisite.

**Command 1** — prompts you to type your secret (nothing appears on screen as you type, that's normal):
```powershell
$secret = Read-Host -AsSecureString 'Client secret'
```

**Command 2** — runs the full export (replace the four `<PLACEHOLDERS>` with your real values):
```powershell
.\Invoke-AISolutionsExport.ps1 -StartDate '2026-01-01' -EndDate '2026-07-01' -OutputDirectory 'C:\AI_Usage_Data' -TenantId '<TENANT_ID>' -ClientId '<CLIENT_ID>' -ClientSecret $secret -IncludeSectionA
```

| Placeholder | Where to find it |
|---|---|
| `2026-01-01` / `2026-07-01` | Your reporting date window (change these dates) |
| `C:\AI_Usage_Data` | The folder where you want the 13 CSV files saved |
| `<TENANT_ID>` | Entra admin center → your app registration → **Directory (tenant) ID** |
| `<CLIENT_ID>` | Entra admin center → your app registration → **Application (client) ID** |
| `$secret` | Already set by Command 1 — do not replace this |

`Read-Host -AsSecureString` keeps the secret out of your command history and off the screen. The tool acquires a token behind the scenes and never logs the secret or the token.

For a tenant without Defender for Cloud Apps or `CloudAppEvents`, add
`-SkipActivitySessions` to the export command. The other three Advanced
Hunting presets still run and the required activity file is created with its
exact header.

---

## Which parameters go together?

| You provide | Result |
| --- | --- |
| `-AccessToken` | Used directly. `-TenantId/-ClientId/-ClientSecret` are ignored. |
| `-TenantId` **+** `-ClientId` **+** `-ClientSecret` (and no `-AccessToken`) | Tool acquires a token via client credentials. |
| None of the above (and no `-QueryExecutor`) | The tool stops with an error telling you to supply credentials. |

> `-QueryExecutor` is a testing-only injection seam that bypasses Graph entirely — see [parameters.md](parameters.md).

---

## Security reminders

- Store the client secret in a vault (e.g. Azure Key Vault), not in scripts.
- Rotate secrets regularly and delete unused app registrations.
- Grant only the four required Graph permissions listed above.
- Never commit tokens, secrets, or exported CSVs. The bundled [.gitignore](../.gitignore) helps.
