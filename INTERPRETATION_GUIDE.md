# AI Solutions Intelligence Dashboard V27 In Testing - Interpretation Guide

This guide explains how to read the V27 In Testing report, what each signal may
indicate, and what to verify before taking action. It applies to:

- `AI-Solutions-Intelligence-Dashboard V27 In Testing.pbit`
- The 13-file CSV contract documented in
  [DATA_SETUP_START_HERE.md](DATA_SETUP_START_HERE.md)
- The actual Power BI captures in `images/v27-report-pages`

The screenshots use deterministic, fabricated sample data. Their values do not
describe a real tenant and must not be used for operational decisions.

## Start with these safeguards

1. **Confirm data coverage.** Open Tier Comparison and verify which source systems
   are populated. An empty visual can mean no matching activity, a header-only
   stub, unavailable licensing, missing onboarding, or expired retention.
2. **Confirm the reporting period and filters.** The report combines sources with
   different retention windows and grains. A date selection cannot recover data
   that a source no longer retains.
3. **Treat scores as triage signals.** Risk scores, geo anomalies, file proximity,
   estimated prompts, and sanction labels prioritize review. They are not proof of
   misuse, disclosure, policy breach, or malicious intent.
4. **Corroborate before acting.** Review the underlying source event, device,
   account, policy, and business context before personnel, compliance, licensing,
   or security action.
5. **Protect exported data.** CSVs and reports can contain user identifiers, IP
   addresses, locations, user agents, and resource names. They are not
   automatically labeled, encrypted, or access-controlled.

## Recommended analysis sequence

| Step | Page | Decision supported |
| --- | --- | --- |
| 1 | Tier Comparison | Which signals are available and which limitations apply? |
| 2 | Executive Summary | Where are adoption, tool mix, and unmanaged-use indicators moving? |
| 3 | Copilot Deep Dive | Which Copilot surfaces and departments show activity? |
| 4 | Department Intensity and Department Breakdown | Where is adoption broad, deep, growing, or concentrated? |
| 5 | Shadow AI | Which observed third-party tools warrant governance review? |
| 6 | Behavioral Risk | Which cross-signal combinations warrant investigation? |
| 7 | Shadow AI and App Governance Data | What do optional MDA exports add? |
| 8 | Benchmarks and Targets | How do observed values compare with locally chosen targets? |
| 9 | Glossary and Data Dictionary | What does a metric mean and how confident should you be? |

## Page-by-page interpretation

### 1. Executive Summary

[![Executive Summary](images/v27-report-pages/01-executive-summary.png)](images/v27-report-pages/01-executive-summary.png)

**Purpose:** A portfolio-level view of AI adoption, tool mix, monthly direction,
and the split between Microsoft Copilot, licensed third-party tools, and tools
classified as shadow AI.

**How to read it:**

- Compare adoption cards with the monthly adoption trend before drawing a
  conclusion from a single period.
- Use the service breakdown to understand observed activity mix, not procurement
  ownership or security approval.
- Read the non-Microsoft prompt trend as an estimate derived from activity/session
  signals, not a vendor-reported prompt count.
- Open the Filters panel and check the active month, department, solution, and
  other slicers before quoting a value.

**What this may indicate:** An enablement opportunity, expanding tool diversity,
concentrated adoption, or a growing need to review the AI solutions catalog.

**What to do next:** Continue to Copilot Deep Dive for licensed-product adoption,
then Shadow AI and Department Breakdown for tool and organizational context.

### 2. Copilot Deep Dive

[![Copilot Deep Dive](images/v27-report-pages/02-copilot-deep-dive.png)](images/v27-report-pages/02-copilot-deep-dive.png)

**Purpose:** Shows audit-event-derived Copilot activity by surface, month, user,
and department.

**How to read it:**

- Licensed Users is a licensing dimension; Active Users requires observed
  activity in the selected context.
- Prompt counts come from Purview `CopilotInteraction` audit records and retain
  every reported surface. They are directional analysis metrics.
- Per User divides observed prompt activity by active users; small populations can
  produce large averages.
- Inactive Licenses identifies license holders without observed activity in the
  selected report context, not proof that a license has never been used.

**What this may indicate:** Which workloads are being adopted, where enablement
may be needed, and whether activity is broad or concentrated.

**What to do next:** Compare with the official Microsoft 365 Copilot usage report
and Viva Insights Copilot Dashboard where available. Microsoft notes that
audit-log-derived active-user and prompt metrics can differ from official usage
report metrics.

### 3. Behavioral Risk and File Activity

[![Behavioral Risk and File Activity](images/v27-report-pages/03-behavioral-risk.png)](images/v27-report-pages/03-behavioral-risk.png)

**Purpose:** Combines several observed behaviors into investigation-priority
signals by user and department.

**How to read it:**

- AI Risk Score is a composite heuristic, not a probability or severity rating.
- Sensitive Proximity Events are selected file create, modify, rename, or copy
  events observed shortly after a network connection to a configured AI domain.
  Temporal proximity does not prove upload, disclosure, or causation.
- Geo Anomaly Events flag country patterns defined by the model's heuristic.
  Travel, VPNs, proxies, mobile carriers, and shared infrastructure can affect the
  result.
- OAuth risk weights consented permissions. It does not determine that an
  application is malicious.

**What this may indicate:** Accounts or departments where multiple signals justify
review, especially when the pattern is new, repeated, or increasing.

**What to do next:** Validate the original Entra, Defender, and consent records;
confirm identity and device context; then follow the organization's incident,
privacy, and acceptable-use procedures.

### 4. Shadow AI and Third-Party Tools

[![Shadow AI and Third-Party Tools](images/v27-report-pages/04-shadow-ai.png)](images/v27-report-pages/04-shadow-ai.png)

**Purpose:** Summarizes observed third-party AI activity and the report catalog's
sanction classification.

**How to read it:**

- A tool is "shadow AI" because of its row in `ai_solutions_catalog.csv`, not
  because the report independently proves that it violates policy.
- Session bins and estimated prompts approximate activity. They are not content
  inspection and are not equivalent to vendor prompt logs.
- A tool can be observed through connected telemetry without identifying the
  user's purpose or the data entered.

**What this may indicate:** Popular tools that may need procurement review,
sanctioning, user guidance, blocking, or a supported alternative.

**What to do next:** Confirm the catalog classification with security, legal,
privacy, procurement, and business owners; validate domains and app names; then
review policy options.

### 5. AI Solutions Intensity by Department

[![AI Solutions Intensity by Department](images/v27-report-pages/05-dept-intensity.png)](images/v27-report-pages/05-dept-intensity.png)

**Purpose:** Compares breadth and intensity of observed AI activity across
departments.

**How to read it:**

- The horizontal axis is weekly active days and is capped at seven.
- The vertical axis is weekly actions.
- Bubble size represents user count.
- A high-intensity, small bubble can reflect a concentrated specialist group;
  a larger, moderate-intensity bubble can reflect broad adoption.

**What this may indicate:** Departments suited for enablement, champion programs,
deeper qualitative research, or governance review.

**What to do next:** Select a department, inspect Department Breakdown, and compare
tool mix and user counts before setting an intervention.

### 6. Department Breakdown

[![Department Breakdown](images/v27-report-pages/06-department-breakdown.png)](images/v27-report-pages/06-department-breakdown.png)

**Purpose:** Explains department-level activity, tool diversity, user reach, and
monthly solution mix.

**How to read it:**

- Separate activity volume from user count; a high volume can come from a small
  number of users.
- Greatest Growth is a period-over-period comparison in the current filter
  context, not a forecast.
- Top self-acquired tools depend on the local catalog classification.
- Weekly Actions per User is an average; inspect population size before comparing
  departments.

**What this may indicate:** Where one tool dominates, where tool sprawl is
increasing, or where adoption is broad enough to support formal enablement.

**What to do next:** Validate department mappings in `EntraUsers.csv`, speak with
business owners, and compare the department with enterprise baselines.

### 7. Shadow AI and App Governance Data

[![Shadow AI and App Governance Data](images/v27-report-pages/07-shadow-ai-catalog.png)](images/v27-report-pages/07-shadow-ai-catalog.png)

**Purpose:** Adds optional Defender for Cloud Apps exports for App Governance
alerts and Cloud Discovery traffic.

**How to read it:**

- Alerts are source-system alerts; severity and descriptions should remain those
  supplied by the originating alert.
- AI Upload MB is network traffic volume attributed by Cloud Discovery. It does
  not identify the transferred content and is not proof of data exfiltration.
- Missing data can reflect unavailable licensing, an unconfigured connector,
  unsupported region, retention, or a header-only placeholder.

**What this may indicate:** Domains or applications with unusual traffic volume or
alert patterns that warrant source-level review.

**What to do next:** Open the originating Defender alert or Cloud Discovery
record, validate connector scope, and investigate the underlying session before
escalation.

### 8. Benchmarks and Targets

[![Benchmarks and Targets](images/v27-report-pages/08-benchmarks-targets.png)](images/v27-report-pages/08-benchmarks-targets.png)

**Purpose:** Compares observed metrics with locally selected what-if targets and
shows month-over-month direction.

**How to read it:**

- Targets are user-entered planning assumptions, not Microsoft benchmarks.
- Gaps are arithmetic differences in percentage points or counts. A positive gap
  is not automatically good or bad; interpret the metric direction.
- "AI Logins Without CA" counts successful AI sign-ins whose Entra record does
  not report Conditional Access as successfully applied. The collector preserves
  successful-CA and other sign-ins in separate aggregates. This does not prove
  that all other protections were absent; MFA, device, network, or location
  controls can exist outside that result.
- Month-over-month cards compare the current report period with the prior period
  available to the measure.

**What this may indicate:** Enablement or governance areas that are above or below
an organization-defined target.

**What to do next:** Document who owns each target, the review cadence, the
rationale, and the action threshold. Do not treat the sample target settings as
recommended values.

### 9. Glossary and Data Dictionary

[![Glossary and Data Dictionary](images/v27-report-pages/09-glossary-data-dictionary.png)](images/v27-report-pages/09-glossary-data-dictionary.png)

**Purpose:** Provides in-report definitions, calculations, source descriptions,
and confidence labels.

**How to read it:**

- **Verified** means the value is calculated from a named source event or
  dimension. It does not establish intent or causality.
- **Exact + estimated** combines event-derived values with modeled activity.
- **Approximate** and **Behavioral signal** require additional corroboration.
- Source-table definitions describe the report input, not guaranteed tenant
  coverage.

**What to do next:** Use this page before exporting a screenshot or repeating a
metric outside the report. Include the confidence label and reporting period.

### 10. Data Coverage by License and Source

[![Data Coverage by License and Source](images/v27-report-pages/10-tier-comparison.png)](images/v27-report-pages/10-tier-comparison.png)

**Purpose:** Explains which capabilities can be populated by each product and
data-source combination.

**How to read it:**

- The matrix is a planning aid, not a licensing entitlement statement.
- Product ownership alone does not guarantee data. Onboarding, connector
  selection, permissions, regional availability, policy configuration, and
  retention also matter.
- `EntraIdSignInEvents` requires Microsoft Entra ID P2 and Defender XDR advanced
  hunting access.
- `CloudAppEvents` requires Defender for Cloud Apps data and the Microsoft 365
  activities connector; MDE Plan 2 alone does not supply this table.

**What to do next:** Resolve missing coverage before interpreting an empty visual.
Use the role and source matrix in
[INSTRUCTIONS_v26.md](INSTRUCTIONS_v26.md).

## Core metric definitions and cautions

| Metric | Interpretation | Required caution |
| --- | --- | --- |
| AI Users | Distinct users observed in any configured AI activity source | Limited to available telemetry and identity resolution |
| Workforce Adoption % | Observed AI users divided by the report's workforce denominator | Denominator quality depends on `EntraUsers.csv` |
| Copilot Adoption % | Licensed users with observed Copilot activity divided by licensed users | Audit-derived and can differ from official usage reports |
| Copilot Prompts | `CopilotInteraction` audit events summarized by surface and period | Directional; not guaranteed equivalent to product-report prompt metrics |
| Non-Microsoft Activity (estimated) | Modeled activity for configured third-party AI tools | Not an actual prompt count |
| Active Days | Distinct dates with observed activity | Source and timezone definitions affect the value |
| Weekly Actions per User | Observed actions normalized by active users and weeks | Average can hide concentration and population size |
| AI Risk Score | Composite of configured behavioral signals | Triage score, not probability, proof, or severity |
| OAuth Risk | Permission-weighted consent events | High weight does not prove malicious behavior |
| Sensitive Proximity Event | Selected file event shortly after an AI-domain connection | Correlation only; not proof of upload or disclosure |
| Geo Anomaly Event | Country pattern that meets the model's anomaly rule | VPN, travel, proxies, and network routing can create false positives |
| Session Bin | A time bucket containing observed network activity | Approximation, not a user prompt or conversation |
| MDA Alert | App Governance or Defender alert represented in the import | Investigate the source alert; do not derive a new severity |
| AI Upload MB | Cloud Discovery network-traffic volume for a domain | Does not identify content or prove exfiltration |
| Gap vs Target | Actual minus a locally configured target | Target is an organizational choice, not a Microsoft benchmark |
| Month-over-Month Change | Current-period value minus the prior-period value | Check period completeness and filter context |

## Data, licensing, and refresh limitations

- Microsoft Purview Audit Standard supports audit search with license-dependent
  retention; Audit Premium is needed for Premium retention and features.
- Native Defender Advanced Hunting commonly exposes a limited retention window.
  Requesting a wider date range cannot restore expired events.
- Advanced Hunting service limits include result-count and result-size quotas.
  The supplied exporter uses conservative time partitioning, but users must review
  saturation warnings and output completeness.
- Power BI Desktop is required on Windows. macOS users need a supported Windows
  environment or a separately published Power BI Service artifact.
- A model using a local or UNC Folder source needs an on-premises data gateway for
  Power BI Service refresh. Publishing it does not convert the query into a
  SharePoint or OneDrive connector.
- Desktop-only use does not require Power BI Pro. Publishing and sharing require
  the appropriate Power BI license or qualifying capacity; PPU workspace content
  requires PPU access.

## Usage and compliance disclaimer

This V27 template is experimental and **In Testing**. It is provided as a
customizable analysis aid, without warranties or guarantees of completeness,
fitness, or accuracy. It is not a sole source of truth for licensing, security,
privacy, legal, compliance, personnel, or procurement decisions.

This public template does not upload customer-supplied data to this GitHub
repository. Customers choose and control the collection, storage, Power BI
deployment, and sharing path, and remain responsible for lawful collection and
use, notices and consent, role assignments, least-privilege access, retention,
data residency, sensitivity labels, storage protection, and compliance with
organizational policies and applicable law.

Coverage depends on enabled products, licenses, onboarding, connectors, configured
domains and app names, source retention, permissions, query limits, and local
catalog choices. Signals can contain false positives and false negatives. Risk
scores prioritize investigation and are not proof of misuse or data leakage.
File proximity is temporal correlation, not proof of upload or disclosure.

The sample package is entirely fabricated and is unsuitable for operational
decisions. This community template is not supported through standard Microsoft
support channels. Report defects or documentation issues through the repository's
[GitHub Issues](https://github.com/microsoft/AI-Solutions-Intelligence-Dashboard/issues).

## Microsoft references

- [Microsoft 365 Copilot usage report](https://learn.microsoft.com/microsoft-365/admin/activity-reports/microsoft-365-copilot-usage)
- [Search the audit log](https://learn.microsoft.com/purview/audit-search)
- [Get started with Microsoft Purview Audit](https://learn.microsoft.com/purview/audit-get-started)
- [Advanced hunting overview and quotas](https://learn.microsoft.com/defender-xdr/advanced-hunting-overview)
- [EntraIdSignInEvents table](https://learn.microsoft.com/defender-xdr/advanced-hunting-entraidsigninevents-table)
- [CloudAppEvents table](https://learn.microsoft.com/defender-xdr/advanced-hunting-cloudappevents-table)
- [Power BI refresh](https://learn.microsoft.com/power-bi/connect-data/refresh-data)
- [Power BI on-premises gateway](https://learn.microsoft.com/power-bi/connect-data/service-gateway-onprem)
- [Power BI licenses and capacity](https://learn.microsoft.com/power-bi/fundamentals/service-features-license-type)
- [Microsoft Graph list users permissions](https://learn.microsoft.com/graph/api/user-list)
- [Microsoft Graph subscribed SKUs permissions](https://learn.microsoft.com/graph/api/subscribedsku-list)
- [Microsoft Graph directory audits permissions](https://learn.microsoft.com/graph/api/directoryaudit-list)
- [Microsoft Graph sign-ins permissions](https://learn.microsoft.com/graph/api/signin-list)
- [Microsoft Graph Advanced Hunting permissions](https://learn.microsoft.com/graph/api/security-security-runhuntingquery)
- [Grant tenant-wide admin consent](https://learn.microsoft.com/entra/identity/enterprise-apps/grant-admin-consent)
- [Power BI workspace roles](https://learn.microsoft.com/power-bi/collaborate-share/service-roles-new-workspaces)
