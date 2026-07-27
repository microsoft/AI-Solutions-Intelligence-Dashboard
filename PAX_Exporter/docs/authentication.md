# Authentication

The exporter talks to the Microsoft Graph endpoint `security/runHuntingQuery`, which requires the permission **`ThreatHunting.Read.All`**. You prove who you are in one of two ways. Pick the one that fits.

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

Whatever the identity behind the token is, it must hold **`ThreatHunting.Read.All`**.

**Use it:**

```powershell
.\Export-DefenderAdvancedHunting.ps1 `
    -Query      $kql `
    -StartDate  '<START_DATE>' `
    -EndDate    '<END_DATE>' `
    -OutputPath '<OUTPUT.csv>' `
    -AccessToken '<YOUR_ACCESS_TOKEN>'
```

> ⏱️ **Tokens expire after ~1 hour.** If a long export dies partway with a `401`, your token likely expired — get a fresh one and re-run. See [troubleshooting.md](troubleshooting.md).

---

## Path B — app registration (client credentials)

An app registration is a reusable identity for unattended runs. Set it up once, then reuse it.

<details>
<summary><strong>One-time setup (click to expand)</strong></summary>

1. **Register an app** in the Microsoft Entra admin center → *App registrations* → *New registration*. Give it a name; leave redirect URI blank.
2. **Add the permission:** in the app's *API permissions* → *Add a permission* → *Microsoft Graph* → **Application permissions** → search **`ThreatHunting.Read.All`** → add it.
3. **Grant admin consent** for `ThreatHunting.Read.All` (a tenant admin must click *Grant admin consent*). The status must show a green check.
4. **Create a client secret:** *Certificates & secrets* → *New client secret* → copy the **Value** immediately (you can't see it again).
5. **Note three values:** the **Directory (tenant) ID**, the **Application (client) ID**, and the **secret value**.

</details>

**Use it (pass the secret securely, never inline):**

```powershell
$secret = Read-Host -AsSecureString 'Client secret'

.\Export-DefenderAdvancedHunting.ps1 `
    -Query      $kql `
    -StartDate  '<START_DATE>' `
    -EndDate    '<END_DATE>' `
    -OutputPath '<OUTPUT.csv>' `
    -TenantId   '<TENANT_ID>' `
    -ClientId   '<CLIENT_ID>' `
    -ClientSecret $secret
```

`Read-Host -AsSecureString` keeps the secret out of your command history and off the screen. The tool acquires a token behind the scenes and never logs the secret or the token.

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
- Grant **only** `ThreatHunting.Read.All` — nothing broader.
- Never commit tokens, secrets, or exported CSVs. The bundled [.gitignore](../.gitignore) helps.
