# AI Solutions Dashboard V27 In Testing Walkthrough Transcript

This transcript matches
`AI-Solutions-Dashboard-V27-In-Testing-Walkthrough.mp4`.

## 1. Executive Summary

Welcome to the AI Solutions Intelligence Dashboard, version 27 In Testing. This
walkthrough uses fabricated sample data and actual Power BI captures. Start on the
Executive Summary to review adoption, tool mix, and monthly direction. Always
check the active filters and reporting period. The dashboard combines available
source signals; it does not guarantee complete tenant coverage, and its sample
values are not recommendations or operational findings.

## 2. Copilot Deep Dive

The Copilot Deep Dive summarizes Copilot interaction audit events by surface,
month, user, and department. Licensed users and active users answer different
questions. Prompt counts are directional metrics derived from Purview audit
records. Microsoft notes that audit-log-derived active-user and prompt metrics can
differ from the official Microsoft 365 Copilot usage report and Viva Insights
Copilot Dashboard. Use this page to find enablement patterns, then confirm them
with official product reports where available.

## 3. Behavioral Risk and File Activity

Behavioral Risk combines configured signals into investigation priorities. The AI
Risk Score is a heuristic composite, not a probability or severity rating.
Sensitive proximity events are selected file create, modify, rename, or copy
events observed shortly after an AI-domain network connection. That timing does
not prove upload, disclosure, or causation. Geo anomalies can also reflect travel,
VPNs, proxies, or network routing. Validate the original Entra, Defender, device,
and consent records before taking action.

## 4. Shadow AI and Third-Party Tools

The Shadow AI page summarizes observed third-party activity and the classifications
in the local AI solutions catalog. A tool appears as shadow AI because of that
catalog classification, not because the report independently proves a policy
violation. Session bins and estimated prompts approximate activity; they are not
vendor prompt logs or content inspection. Use the page to identify popular tools
for review with security, privacy, legal, procurement, and business owners.

## 5. AI Solutions Intensity by Department

The department intensity view compares breadth and depth of adoption. Weekly
active days are on the horizontal axis and are capped at seven. Weekly actions are
on the vertical axis, and bubble size represents user count. A small,
high-intensity bubble can be a specialist group, while a larger moderate bubble
can indicate broad adoption. Select a department, then continue to Department
Breakdown for context.

## 6. Department Breakdown

Department Breakdown separates activity volume, user reach, tool diversity, and
monthly solution mix. High volume can come from only a few users, so compare bars
with user counts and averages. Greatest growth is a period-over-period result in
the current filter context, not a forecast. Confirm department mappings in the
Entra users file, then use business-owner interviews before setting training,
license, or governance actions.

## 7. Shadow AI and App Governance Data

This optional page adds Defender for Cloud Apps exports. Alert severity should
remain the originating source severity. Upload megabytes is network traffic volume
attributed by Cloud Discovery; it does not identify transferred content and is
not proof of data exfiltration. Missing visuals can reflect licensing, regional
availability, an unconfigured connector, retention, or a header-only placeholder.
Open the source alert or Cloud Discovery record before escalation.

## 8. Benchmarks and Targets

Benchmarks and Targets compares observed metrics with local what-if assumptions.
These targets are not Microsoft benchmarks. Gap cards are arithmetic differences,
so interpret whether higher or lower is desirable for each measure. Logins without
Conditional Access means the Entra record reports Conditional Access as not
applied. It does not prove that MFA, device, network, or location protections were
absent. Month-over-month cards compare available report periods; check period
completeness before quoting the change.

## 9. Glossary and Data Dictionary

Use the glossary before sharing any metric. Verified means calculated from a named
source event or dimension; it does not establish intent or causality. Exact plus
estimated combines source values with modeled activity. Approximate and behavioral
signals require corroboration. Include the confidence label, reporting period, and
filters whenever a value is exported or discussed outside the report.

## 10. Data Coverage by License and Source

Finish with Data Coverage by License and Source. This matrix is a planning aid,
not a licensing entitlement statement. Product ownership alone does not guarantee
data. Onboarding, connectors, permissions, retention, and regional availability
also matter. Entra sign-in hunting requires Entra ID P2. Cloud app events require
Defender for Cloud Apps and its Microsoft 365 activities connector. Version 27 is
experimental and In Testing. Protect customer exports, corroborate every risk
signal, and read the interpretation guide before operational use.
