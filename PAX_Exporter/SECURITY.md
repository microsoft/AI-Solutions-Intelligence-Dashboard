# Security & responsible use

## This tool exports sensitive data

`Export-DefenderAdvancedHunting.ps1` produces CSVs of raw Microsoft Defender
Advanced Hunting audit data. Depending on your query, that output can include
**user identifiers** (object IDs, display names), **IP addresses**,
**geolocation**, **user agents**, and **resource/object names**.

Treat all exported output as **Highly Confidential**:

- **You are responsible** for storing, transmitting, and disposing of exported
  data securely, in line with your organization's policies and applicable law.
- **Never commit exported CSVs, tokens, or secrets** to source control. The
  bundled [.gitignore](.gitignore) helps keep `*.csv`, `*.log`, and temp files
  out of git, but you are the last line of defense.
- **Pass credentials at runtime only.** No tenant id, client id, secret, or
  token is ever hardcoded or logged by the tool — keep it that way.
- Grant the identity **only** the `ThreatHunting.Read.All` permission it needs,
  and store any client secret in a vault (e.g. Azure Key Vault).

## Reporting security issues

**Do not** report security vulnerabilities through public GitHub issues.

Please report them to the Microsoft Security Response Center (MSRC) at
<https://msrc.microsoft.com/create-report>. If you prefer to submit without
logging in, send email to <secure@microsoft.com>.

You can find more information — including the MSRC PGP key — on the
[MSRC website](https://www.microsoft.com/msrc).
