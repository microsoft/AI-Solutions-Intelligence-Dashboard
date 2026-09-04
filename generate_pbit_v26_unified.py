#!/usr/bin/env python3
"""Build the validated V26 PBIT from the committed V26 package.

The transformer is deterministic and uses only the Python standard library. It
preserves every unmodified package entry and its ZIP metadata, updates the
semantic model and Power Query metadata together, removes stale report
formatting selectors, and corrects embedded report guidance. The source PBIT is
never modified.
"""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import os
import tempfile
import textwrap
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path


BASE_DIR = Path(__file__).resolve().parent
DEFAULT_SOURCE = BASE_DIR / "AI-Solutions-Intelligence-Dashboard V26.pbit"
DEFAULT_OUTPUT = BASE_DIR / "AI-Solutions-Intelligence-Dashboard V26 Validated.pbit"

MODEL_ENTRY = "DataModelSchema"
UNAPPLIED_ENTRY = "UnappliedChanges"
CONTENT_TYPES_ENTRY = "[Content_Types].xml"
SECURITY_BINDINGS_ENTRY = "SecurityBindings"
CUSTOM_PROPERTIES_ENTRY = "docProps/custom.xml"
SECURITY_BINDINGS_OVERRIDE = (
    b'<Override PartName="/SecurityBindings" ContentType=""/>'
)
CUSTOM_PROPERTIES_NAMESPACE = (
    "http://schemas.openxmlformats.org/officeDocument/2006/custom-properties"
)
CUSTOM_PROPERTY_TYPES_NAMESPACE = (
    "http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes"
)
MSIP_LABEL_PROPERTY_PREFIX = "MSIP_Label_"
FORBIDDEN_PUBLIC_METADATA = (
    b"MSIP_Label_",
    b"f42aa342-8706-4288-bd11-ebb85995028c",
    b"72f988bf-86f1-41af-91ab-2d7cd011db47",
    b">Internal<",
)
FILE_QUERY_COUNT = 13
RAW_FILE_PATH_PREFIX = 'File.Contents(AI_Data_Folder_Path & "'
NORMALIZED_FILE_PATH_PREFIX = 'File.Contents(DataFolder & "'
DATA_FOLDER_M = (
    '    DataFolder = Text.TrimEnd(AI_Data_Folder_Path, {"\\", "/"}) '
    '& (if Text.Contains(AI_Data_Folder_Path, "\\") then "\\" else "/"),'
)
STALE_VISUAL_IDS = (
    "ad0ace11a5cabb220001",
    "7ab8b2a4d329b1304ddc",
)
STALE_SELECTOR_TOKENS = (
    "Table.PersonId",
    "Organization (Aggregated)",
    "Ravi Vedula",
)
COPILOT_SURFACE_VISUAL_ID = "d4ad1baae2904be3d5a9"
REPORT_VISUAL_REPLACEMENTS = {
    "5b6ef3da7ecc060150c7": (
        (
            " / User  =  composite risk score (OAuth weight + sensitive-file proximity + off-hours + geo anomaly + CA bypass) divided by distinct AI users.",
            " / User  =  average per active user of the seven-signal score: session volume, file proximity, sensitive-name matches, high-risk OAuth grants, tool diversity, off-hours sessions, and geo anomalies.",
        ),
        (
            " (File proximity): Count of file events on managed devices where a file with a sensitive name pattern or a file located in a sensitive folder was opened within ±10 minutes of an AI-tool session on the same device. Each row is counted once, even if both signals match.",
            " (File proximity): Count of file events on managed devices where a sensitive filename or folder pattern was observed within five minutes after an AI-site visit on the same device. This is a correlation signal, not proof that the file was uploaded.",
        ),
    ),
    "a5394392663acd52d853": (
        (
            'AI Logins Without CA" = the number of times employees signed into an AI app without Conditional Access (CA) enforcing. ',
            '"AI Logins Without CA" counts AI-app sign-ins where the Entra record reports Conditional Access as not applied. It does not prove that other protections were absent.',
        ),
        (
            "No MFA was required",
            "MFA may still be enforced outside Conditional Access",
        ),
        (
            "No device compliance was checked",
            "Device controls may exist outside this result",
        ),
        (
            "No location restriction was applied",
            "Location controls may exist outside this result",
        ),
        (
            'Essentially, the sign-in went through "unprotected"',
            "Review the sign-in details before treating it as unprotected",
        ),
    ),
    "731f42d7816e349c8ea3": (
        (
            "on managed devices.",
            "in connected Defender for Cloud Apps data sources.",
        ),
    ),
    "d2805b76e6e533113cc6": (
        (
            "Shadow AI and OAuth Anomaly Alerts ",
            "Shadow AI and App Governance Data ",
        ),
    ),
    "f4c5f96c-8fc": (
        (
            "This chart ranks AI domains by total upload volume (in MB) detected through MDA Cloud Discovery. Higher upload volumes may indicate greater data exfiltration risk. Upload volume captures data sent from your organization to these AI services, including: files, prompts, code snippets, or any content pasted or uploaded into AI tools. Domains with unusually high upload volume warrant further investigation to determine if sensitive data is leaving the organization. ",
            "This chart ranks AI domains by uploaded network-traffic volume (MB) reported by Defender for Cloud Apps Cloud Discovery. It is a volume signal only: it does not identify the content or prove data exfiltration. Investigate unusually high volumes in context. ",
        ),
    ),
    "f6859d190b907183e3e7": (
        (
            "🛡️  Microsoft Defender + MDA for Cloud Apps required",
            "🛡️  Defender for Cloud Apps exports required for MDA visuals",
        ),
    ),
    "fc755080-947": (
        (
            "Alerts are triggered when an AI app shows suspicious behavior such as: ",
            "The ai_appgov_alerts.csv dataset requires an external Defender for Cloud Apps App Governance export. ",
        ),
        (
            "Requesting high-level permissions (e.g., full access to mail or sites)",
            "The included exporter writes a header-only placeholder for this dataset",
        ),
        (
            "Sudden spikes in data access or API activity",
            "Populate it only from a supported App Governance export",
        ),
        (
            "Accessing data from unexpected locations or outside normal scope",
            "Keep severity and description from the originating alert",
        ),
        (
            "Receiving bulk admin consent shortly after being registered",
            "Do not present derived OAuth risk as a native App Governance alert",
        ),
        (
            "Rapid increase in activity that suggests large-scale data extraction",
            "Treat alerts as investigation signals, not proof of data exfiltration",
        ),
    ),
    "f7112f8014c7dd902acd": (
        (
            "Tier Comparison - MDA vs No MDA Enabled",
            "Data Coverage by License and Source",
        ),
    ),
    "3135b370d72d0d5b3d3b": (
        (
            "E5 + Defender +  MDA",
            "E5 + Defender + MDA",
        ),
    ),
    "334b9e8f4c3801dc5134": (
        (
            "M365 E5 (full)",
            "M365 E5 + Copilot + MDA",
        ),
    ),
    "334f458103961b633c87": (
        (
            "OAuth consent risk on AI plugins",
            "OAuth consent risk for AI apps",
        ),
    ),
    "39fdf04a73e4643d8781": (("✓ Verified", "— requires Copilot"),),
    "ed89c1472906cbbedd0a": (("✓ Verified", "— requires Copilot"),),
    "04a9b043aebca37ca2cc": (
        (
            "Unsanctioned 3P AI on managed devices",
            "Unsanctioned third-party AI activity",
        ),
    ),
    "473c8600798167459d62": (("✓ Verified", "— requires MDA"),),
    "d97ad90281b9ed2c9635": (
        (
            "File activity near AI prompt",
            "File activity near AI site visit",
        ),
    ),
    "91a306421c1ccd141000": (("✓ Verified", "✓ Behavioral"),),
    "f5e431a996b77d030b35": (("✓ Verified", "✓ Behavioral"),),
    "5bbac4059cb8370298d7": (("✓ Verified", "✓ Behavioral"),),
    "1e90c8c99ac4cc16c200": (
        (
            "Behavioral Risk composite (8 signals)",
            "Behavioral Risk composite (7 signals)",
        ),
    ),
    "15ace83076b8d08bb452": (
        (
            "OAuth anomaly alerts (App Governance)",
            "App Governance alerts (external MDA export)",
        ),
    ),
    "57c82df920a313600749": (("✓ Verified", "External export"),),
    "689fab21b71139ce862e": (("✓ Verified", "External export"),),
    "2ac34b45a830158eeada": (("✓ Verified", "External export"),),
    "d64efd20602a04c13ce1": (("✓ Verified", "External export"),),
    "b5fd70bc4d2434978d4c": (
        (
            "You're getting ~95% of the v22 dashboard's value without MDA.",
            "MDE and Entra provide partial coverage without MDA; Cloud Discovery and App Governance remain unavailable.",
        ),
    ),
    "21b668872c9300062234": (
        (
            "What you would unlock by enabling MDA (already in your E5 license, no extra cost): (1) Cloud Discovery — automatic discovery of every AI domain accessed across the tenant from firewall/proxy logs, with risk scoring against the MDA cloud app catalog. (2) App Governance — pre-built ML alerts on OAuth grants to suspicious AI plugins. Until then, the equivalent raw data is captured here from MDE P2 + Entra Audit Logs.",
            "With MDA data exports, you can add Cloud Discovery coverage for AI domains represented in connected traffic sources and native App Governance alerts. Licensing and availability depend on your tenant configuration. Without those exports, MDE and Entra signals remain useful but are not equivalent to MDA coverage.",
        ),
    ),
}
PATCHED_VISUAL_IDS = tuple(
    dict.fromkeys(
        (*STALE_VISUAL_IDS, *REPORT_VISUAL_REPLACEMENTS, COPILOT_SURFACE_VISUAL_ID)
    )
)

CALENDAR_M = [
    "let",
    "    MonthValues = List.Combine({",
    '        Table.Column(AI_Activity, "YearMonth"),',
    '        Table.Column(AI_OAuthConsents, "YearMonth"),',
    '        Table.Column(AI_SSO_SignIns, "YearMonth"),',
    '        Table.Column(AI_FileProximity, "YearMonth"),',
    '        Table.Column(AI_OffHoursGeo, "YearMonth"),',
    '        Table.Column(AI_CopilotUsage, "YearMonth"),',
    '        Table.Column(AI_CopilotSurfaceUsage, "YearMonth"),',
    '        Table.Column(AI_ClientChannel, "YearMonth"),',
    '        Table.Column(AI_AppGovAlerts, "YearMonth"),',
    '        Table.Column(AI_CloudDiscovery, "YearMonth"),',
    '        Table.Column(AI_MDA_Sessions, "YearMonth")',
    "    }),",
    "    MonthDates = List.RemoveNulls(List.Transform(MonthValues, each try Date.StartOfMonth(Date.FromText(Text.From(_) & \"-01\")) otherwise null)),",
    '    Dates = List.Sort(List.Distinct(MonthDates)),',
    '    Tbl = Table.FromList(Dates, Splitter.SplitByNothing(), {"Date"}),',
    '    Typed = Table.TransformColumnTypes(Tbl, {{"Date", type date}}),',
    '    A = Table.AddColumn(Typed, "Year", each Date.Year([Date]), Int64.Type),',
    '    B = Table.AddColumn(A, "Quarter", each "Q" & Text.From(Date.QuarterOfYear([Date])), type text),',
    '    C = Table.AddColumn(B, "QuarterNum", each Date.QuarterOfYear([Date]), Int64.Type),',
    '    D = Table.AddColumn(C, "MonthNumber", each Date.Month([Date]), Int64.Type),',
    '    E = Table.AddColumn(D, "MonthName", each Date.MonthName([Date]), type text),',
    '    F = Table.AddColumn(E, "MonthLabel", each Date.ToText([Date], "MMM yyyy"), type text),',
    '    G = Table.AddColumn(F, "YearMonth", each Date.ToText([Date], "yyyy-MM"), type text),',
    '    H = Table.AddColumn(G, "SortOrder", each Date.Year([Date]) * 100 + Date.Month([Date]), Int64.Type)',
    "in",
    "    H",
]

COPILOT_SURFACE_M = [
    "let",
    '    Source = Csv.Document(File.Contents(AI_Data_Folder_Path & "ai_copilot_surface_usage.csv"), [Delimiter=",", Encoding=65001, QuoteStyle=QuoteStyle.Csv]),',
    "    Headers = Table.PromoteHeaders(Source, [PromoteAllScalars=true]),",
    "    Typed = Table.TransformColumnTypes(Headers, {",
    '        {"UserPrincipalName", type text},',
    '        {"YearMonth", type text},',
    '        {"Surface", type text},',
    '        {"SourceWorkload", type text},',
    '        {"SourceAppHost", type text},',
    '        {"PromptCount", Int64.Type},',
    '        {"ActiveDays", Int64.Type},',
    '        {"LastActivityDate", type text}',
    "    })",
    "in Typed",
]

COPILOT_SURFACE_LINEAGE = {
    "table": "7cfb9cac-1146-50e3-8320-f5aecdfc9c1c",
    "UserPrincipalName": "1d84abb7-5faa-5fbd-b199-6778a18222e2",
    "YearMonth": "a75016f6-d691-5ccb-928a-811ef8c1a4ad",
    "Surface": "75259208-e709-5fd1-8b48-53a7ad4fe937",
    "SourceWorkload": "36480dec-46c0-5bdd-b4b1-94129a15ba8d",
    "SourceAppHost": "b6b05e3a-7927-5feb-a248-352b0a6724bf",
    "PromptCount": "dbfcb043-1d7b-52f0-9b76-ba9e385ecb92",
    "ActiveDays": "7c2c7b11-6a2b-5fdb-8015-08e6736af6f1",
    "LastActivityDate": "bf034414-2977-5426-a9ba-4ab847283fd4",
    "userRelationship": "7448feae-7412-52d2-823d-182f5a136dc7",
    "calendarRelationship": "34183f7d-8b6b-5d58-a385-dbdf949d391c",
    "measure": "f859d21c-fe72-56f0-8095-b9a7aeb00a26",
}

SOLUTIONS_M = [
    "let",
    '    Source = Csv.Document(File.Contents(AI_Data_Folder_Path & "ai_solutions_catalog.csv"), [Delimiter=",", Encoding=65001, QuoteStyle=QuoteStyle.Csv]),',
    "    Headers = Table.PromoteHeaders(Source, [PromoteAllScalars=true]),",
    "    Typed = Table.TransformColumnTypes(Headers, {",
    '        {"AISolution", type text},',
    '        {"Category", type text},',
    '        {"Vendor", type text},',
    '        {"RiskTier", type text},',
    '        {"DefaultDataHandling", type text},',
    '        {"SolutionGroup", type text}',
    "    })",
    "in",
    "    Typed",
]


def dax(value: str) -> str:
    return textwrap.dedent(value).strip()


MEASURE_EXPRESSIONS = {
    "Copilot Surface Prompts": "SUM('AI_CopilotSurfaceUsage'[PromptCount])",
    "AI Users": dax(
        """
        VAR _includeCopilot =
            CONTAINS(
                VALUES('AI_Solutions'[AISolution]),
                'AI_Solutions'[AISolution],
                "Microsoft 365 Copilot"
            )
        VAR _activityUsers =
            SELECTCOLUMNS(
                FILTER(VALUES('AI_Activity'[UPN]), NOT ISBLANK('AI_Activity'[UPN])),
                "UPN", 'AI_Activity'[UPN]
            )
        VAR _copilotUsers =
            SELECTCOLUMNS(
                FILTER(
                    VALUES('AI_CopilotUsage'[UserPrincipalName]),
                    _includeCopilot && NOT ISBLANK('AI_CopilotUsage'[UserPrincipalName])
                ),
                "UPN", 'AI_CopilotUsage'[UserPrincipalName]
            )
        RETURN
            COUNTROWS(DISTINCT(UNION(_activityUsers, _copilotUsers)))
        """
    ),
    "Licensed Copilot Users": dax(
        """
        COUNTROWS(
            FILTER(
                'EntraUsers',
                CONTAINSSTRING(
                    ";" & 'EntraUsers'[assignedLicenses] & ";",
                    ";Microsoft_365_Copilot;"
                )
            )
        )
        """
    ),
    "Copilot License Utilization": dax(
        """
        VAR _licensedUsers = [Licensed Copilot Users]
        VAR _activeLicensedUsers =
            CALCULATE(
                DISTINCTCOUNT('AI_CopilotUsage'[UserPrincipalName]),
                KEEPFILTERS(
                    FILTER(
                        'EntraUsers',
                        CONTAINSSTRING(
                            ";" & 'EntraUsers'[assignedLicenses] & ";",
                            ";Microsoft_365_Copilot;"
                        )
                    )
                )
            )
        RETURN
            MIN(1, DIVIDE(_activeLicensedUsers, _licensedUsers, 0))
        """
    ),
    "Inactive Copilot Licenses": dax(
        """
        VAR _licensedUsers = [Licensed Copilot Users]
        VAR _activeLicensedUsers =
            CALCULATE(
                DISTINCTCOUNT('AI_CopilotUsage'[UserPrincipalName]),
                KEEPFILTERS(
                    FILTER(
                        'EntraUsers',
                        CONTAINSSTRING(
                            ";" & 'EntraUsers'[assignedLicenses] & ";",
                            ";Microsoft_365_Copilot;"
                        )
                    )
                )
            )
        RETURN
            MAX(0, _licensedUsers - _activeLicensedUsers)
        """
    ),
    "Enterprise AI Users": dax(
        """
        VAR _activityUsers =
            SELECTCOLUMNS(
                CALCULATETABLE(
                    VALUES('AI_Activity'[UPN]),
                    KEEPFILTERS('AI_Activity'[AISolution] = "Microsoft 365 Copilot")
                ),
                "UPN", 'AI_Activity'[UPN]
            )
        VAR _includeCopilotUsers =
            NOT ISFILTERED('AI_Solutions'[AISolution])
                || "Microsoft 365 Copilot" IN VALUES('AI_Solutions'[AISolution])
        VAR _copilotUsers =
            SELECTCOLUMNS(
                FILTER(
                    VALUES('AI_CopilotUsage'[UserPrincipalName]),
                    _includeCopilotUsers
                ),
                "UPN", 'AI_CopilotUsage'[UserPrincipalName]
            )
        RETURN
            COUNTROWS(DISTINCT(UNION(_activityUsers, _copilotUsers)))
        """
    ),
    "Unmanaged AI Users": dax(
        """
        CALCULATE(
            DISTINCTCOUNT('AI_Activity'[UPN]),
            KEEPFILTERS('AI_Activity'[RiskTier] = "Unsanctioned")
        )
        """
    ),
    "Non-Microsoft AI Users": dax(
        """
        CALCULATE(
            DISTINCTCOUNT('AI_Activity'[UPN]),
            KEEPFILTERS('AI_Solutions'[Vendor] <> "Microsoft")
        )
        """
    ),
    "Non-Microsoft Activity (est.)": dax(
        """
        CALCULATE(
            [Total Estimated Prompts],
            KEEPFILTERS('AI_Solutions'[Vendor] <> "Microsoft")
        )
        """
    ),
    "Tools per User": dax(
        """
        VAR _users =
            FILTER(
                VALUES('EntraUsers'[userPrincipalName]),
                CALCULATE(DISTINCTCOUNT('AI_Activity'[AISolution])) > 0
            )
        RETURN
            AVERAGEX(
                _users,
                CALCULATE(DISTINCTCOUNT('AI_Activity'[AISolution]))
            )
        """
    ),
    "Power Users (3+ tools)": dax(
        """
        COUNTROWS(
            FILTER(
                VALUES('EntraUsers'[userPrincipalName]),
                CALCULATE(DISTINCTCOUNT('AI_Activity'[AISolution])) >= 3
            )
        )
        """
    ),
    "Critical Risk Users": dax(
        """
        VAR _userRisk =
            ADDCOLUMNS(
                VALUES('EntraUsers'[userPrincipalName]),
                "@Risk", CALCULATE([AI Risk Score])
            )
        RETURN
            COUNTROWS(FILTER(_userRisk, [@Risk] > 100))
        """
    ),
    "High Risk Users": dax(
        """
        VAR _userRisk =
            ADDCOLUMNS(
                VALUES('EntraUsers'[userPrincipalName]),
                "@Risk", CALCULATE([AI Risk Score])
            )
        RETURN
            COUNTROWS(FILTER(_userRisk, [@Risk] > 50 && [@Risk] <= 100))
        """
    ),
    "AI Logins Without CA": dax(
        """
        CALCULATE(
            SUM('AI_SSO_SignIns'[SignInCount]),
            KEEPFILTERS('AI_SSO_SignIns'[HasConditionalAccess] = "FALSE")
        )
        """
    ),
    "AI Users - Prior Month": dax(
        """
        VAR _currentSort = MAX('Calendar'[SortOrder])
        VAR _previousSort =
            IF(MOD(_currentSort, 100) = 1, _currentSort - 89, _currentSort - 1)
        RETURN
            CALCULATE(
                [AI Users],
                REMOVEFILTERS('Calendar'),
                'Calendar'[SortOrder] = _previousSort
            )
        """
    ),
    "AI Users Delta vs Prior Month": dax(
        """
        VAR _currentSort = MAX('Calendar'[SortOrder])
        VAR _currentUsers =
            CALCULATE(
                [AI Users],
                REMOVEFILTERS('Calendar'),
                'Calendar'[SortOrder] = _currentSort
            )
        RETURN
            _currentUsers - [AI Users - Prior Month]
        """
    ),
    "Copilot Adoption - Prior Month": dax(
        """
        VAR _currentSort = MAX('Calendar'[SortOrder])
        VAR _previousSort =
            IF(MOD(_currentSort, 100) = 1, _currentSort - 89, _currentSort - 1)
        RETURN
            CALCULATE(
                [Copilot Adoption %],
                REMOVEFILTERS('Calendar'),
                'Calendar'[SortOrder] = _previousSort
            )
        """
    ),
    "Copilot Adoption Delta vs Prior Month (pp)": dax(
        """
        VAR _currentSort = MAX('Calendar'[SortOrder])
        VAR _currentAdoption =
            CALCULATE(
                [Copilot Adoption %],
                REMOVEFILTERS('Calendar'),
                'Calendar'[SortOrder] = _currentSort
            )
        RETURN
            (_currentAdoption - [Copilot Adoption - Prior Month]) * 100
        """
    ),
    "Avg AI Risk Score per User": dax(
        """
        VAR _userRisk =
            ADDCOLUMNS(
                VALUES('EntraUsers'[userPrincipalName]),
                "@Volume", CALCULATE([AI Activity Volume]),
                "@Risk", CALCULATE([AI Risk Score])
            )
        VAR _activeUsers =
            FILTER(_userRisk, [@Volume] > 0 || [@Risk] > 0)
        RETURN
            COALESCE(AVERAGEX(_activeUsers, [@Risk]), 0)
        """
    ),
    "Licensed AI Users": dax(
        """
        VAR _includeCopilot =
            CONTAINS(
                VALUES('AI_Solutions'[AISolution]),
                'AI_Solutions'[AISolution],
                "Microsoft 365 Copilot"
            )
        VAR _activityUsers =
            SELECTCOLUMNS(
                CALCULATETABLE(
                    VALUES('AI_Activity'[UPN]),
                    KEEPFILTERS('AI_Activity'[RiskTier] = "Sanctioned")
                ),
                "UPN", 'AI_Activity'[UPN]
            )
        VAR _copilotUsers =
            SELECTCOLUMNS(
                FILTER(
                    VALUES('AI_CopilotUsage'[UserPrincipalName]),
                    _includeCopilot && NOT ISBLANK('AI_CopilotUsage'[UserPrincipalName])
                ),
                "UPN", 'AI_CopilotUsage'[UserPrincipalName]
            )
        RETURN
            COUNTROWS(DISTINCT(UNION(_activityUsers, _copilotUsers)))
        """
    ),
    "Shadow AI Users": dax(
        """
        CALCULATE(
            DISTINCTCOUNT('AI_Activity'[UPN]),
            KEEPFILTERS('AI_Activity'[RiskTier] = "Unsanctioned")
        )
        """
    ),
    "MoM Top AI Solution": dax(
        """
        VAR _currentSort = MAX('Calendar'[SortOrder])
        VAR _previousSort =
            IF(MOD(_currentSort, 100) = 1, _currentSort - 89, _currentSort - 1)
        VAR _solutions =
            CALCULATETABLE(
                VALUES('AI_Activity'[AISolution]),
                REMOVEFILTERS('Calendar')
            )
        VAR _growth =
            ADDCOLUMNS(
                _solutions,
                "@CurrentCount",
                    CALCULATE(
                        COUNTROWS('AI_Activity'),
                        REMOVEFILTERS('Calendar'),
                        'Calendar'[SortOrder] = _currentSort
                    ),
                "@PreviousCount",
                    CALCULATE(
                        COUNTROWS('AI_Activity'),
                        REMOVEFILTERS('Calendar'),
                        'Calendar'[SortOrder] = _previousSort
                    )
            )
        VAR _maxGrowth = MAXX(_growth, [@CurrentCount] - [@PreviousCount])
        VAR _topApp =
            MAXX(
                FILTER(_growth, [@CurrentCount] - [@PreviousCount] = _maxGrowth),
                'AI_Activity'[AISolution]
            )
        RETURN
            IF(
                ISBLANK(_topApp),
                "No activity",
                IF(
                    _maxGrowth > 0,
                    _topApp & " (+" & FORMAT(_maxGrowth, "#,0") & ")",
                    _topApp
                )
            )
        """
    ),
    "Lowest Adoption AI": dax(
        """
        VAR _currentSort = MAX('Calendar'[SortOrder])
        VAR _previousSort =
            IF(MOD(_currentSort, 100) = 1, _currentSort - 89, _currentSort - 1)
        VAR _solutions =
            CALCULATETABLE(
                VALUES('AI_Activity'[AISolution]),
                REMOVEFILTERS('Calendar')
            )
        VAR _growth =
            ADDCOLUMNS(
                _solutions,
                "@CurrentCount",
                    CALCULATE(
                        COUNTROWS('AI_Activity'),
                        REMOVEFILTERS('Calendar'),
                        'Calendar'[SortOrder] = _currentSort
                    ),
                "@PreviousCount",
                    CALCULATE(
                        COUNTROWS('AI_Activity'),
                        REMOVEFILTERS('Calendar'),
                        'Calendar'[SortOrder] = _previousSort
                    )
            )
        VAR _minGrowth = MINX(_growth, [@CurrentCount] - [@PreviousCount])
        VAR _bottomApp =
            MAXX(
                FILTER(_growth, [@CurrentCount] - [@PreviousCount] = _minGrowth),
                'AI_Activity'[AISolution]
            )
        RETURN
            COALESCE(_bottomApp, "No activity")
        """
    ),
    "Top Dept Unmanaged": dax(
        """
        VAR _departmentTools =
            ADDCOLUMNS(
                VALUES('EntraUsers'[department]),
                "@ToolCount",
                    CALCULATE(
                        DISTINCTCOUNT('AI_Activity'[AISolution]),
                        KEEPFILTERS('AI_Activity'[RiskTier] = "Unsanctioned")
                    )
            )
        VAR _maxTools = MAXX(_departmentTools, [@ToolCount])
        VAR _topDepartment =
            MAXX(
                FILTER(_departmentTools, [@ToolCount] = _maxTools),
                'EntraUsers'[department]
            )
        RETURN
            IF(_maxTools = 0, "No unmanaged", _topDepartment & " (" & _maxTools & " tools)")
        """
    ),
    "Avg Risk Score": "[Avg AI Risk Score per User]",
    "Funnel Multi-Tool Unmanaged": dax(
        """
        VAR _users =
            ADDCOLUMNS(
                VALUES('EntraUsers'[userPrincipalName]),
                "@UnmanagedTools",
                    CALCULATE(
                        DISTINCTCOUNT('AI_Activity'[AISolution]),
                        KEEPFILTERS('AI_Activity'[RiskTier] = "Unsanctioned")
                    )
            )
        RETURN
            COUNTROWS(FILTER(_users, [@UnmanagedTools] >= 2))
        """
    ),
    "Funnel High-Intensity Unmanaged": dax(
        """
        VAR _users =
            ADDCOLUMNS(
                VALUES('EntraUsers'[userPrincipalName]),
                "@UnmanagedTools",
                    CALCULATE(
                        DISTINCTCOUNT('AI_Activity'[AISolution]),
                        KEEPFILTERS('AI_Activity'[RiskTier] = "Unsanctioned")
                    ),
                "@UnmanagedSessions",
                    CALCULATE(
                        SUM('AI_Activity'[Sessions]),
                        KEEPFILTERS('AI_Activity'[RiskTier] = "Unsanctioned")
                    )
            )
        RETURN
            COUNTROWS(
                FILTER(
                    _users,
                    [@UnmanagedTools] >= 2 && [@UnmanagedSessions] > 50
                )
            )
        """
    ),
    "Tool Sprawl MoM Delta": dax(
        """
        VAR _currentSort = MAX('Calendar'[SortOrder])
        VAR _previousSort =
            IF(MOD(_currentSort, 100) = 1, _currentSort - 89, _currentSort - 1)
        VAR _currentValue =
            CALCULATE(
                [Tool Sprawl Rate],
                REMOVEFILTERS('Calendar'),
                'Calendar'[SortOrder] = _currentSort
            )
        VAR _previousValue =
            CALCULATE(
                [Tool Sprawl Rate],
                REMOVEFILTERS('Calendar'),
                'Calendar'[SortOrder] = _previousSort
            )
        RETURN
            _currentValue - _previousValue
        """
    ),
}

# Model measure names contain typographic characters. Build the keys without
# embedding non-ASCII source text in this script.
MEASURE_EXPRESSIONS["AI Users \u0394 vs Prior Month"] = MEASURE_EXPRESSIONS.pop(
    "AI Users Delta vs Prior Month"
)
MEASURE_EXPRESSIONS["Copilot Adoption \u2014 Prior Month"] = MEASURE_EXPRESSIONS.pop(
    "Copilot Adoption - Prior Month"
)
MEASURE_EXPRESSIONS[
    "Copilot Adoption \u0394 vs Prior Month (pp)"
] = MEASURE_EXPRESSIONS.pop("Copilot Adoption Delta vs Prior Month (pp)")
MEASURE_EXPRESSIONS["AI Users \u2014 Prior Month"] = MEASURE_EXPRESSIONS.pop(
    "AI Users - Prior Month"
)

for count in range(1, 5):
    MEASURE_EXPRESSIONS[f"Users with {count} tool" + ("" if count == 1 else "s")] = dax(
        f"""
        COUNTROWS(
            FILTER(
                VALUES('EntraUsers'[userPrincipalName]),
                CALCULATE(DISTINCTCOUNT('AI_Activity'[AISolution])) = {count}
            )
        )
        """
    )

MEASURE_EXPRESSIONS["Users with 5+ tools"] = dax(
    """
    COUNTROWS(
        FILTER(
            VALUES('EntraUsers'[userPrincipalName]),
            CALCULATE(DISTINCTCOUNT('AI_Activity'[AISolution])) >= 5
        )
    )
    """
)

LICENSE_STATUS_DAX = dax(
    """
    SWITCH(
        'AI_Solutions'[RiskTier],
        "Sanctioned", "Licensed (Org-Provided)",
        "Conditional", "Conditional (Approved with Controls)",
        "Unlicensed (Shadow AI)"
    )
    """
)

GLOSSARY_REPLACEMENTS = (
    (
        "Calculation: DISTINCTCOUNT of UPN across Graph Copilot Usage Report + Defender DeviceNetworkEvents to known AI hosts.",
        "Calculation: distinct UPN union across Purview CopilotInteraction usage and Defender CloudAppEvents AI activity.",
    ),
    (
        'AND user IN Graph AI_CopilotUsage.',
        'AND user IN Purview AI_CopilotUsage.',
    ),
    (
        "Distinct calendar days the user did any AI activity. Calculation: DISTINCTCOUNT of date(Timestamp) across all AI signals.",
        "Per-tool active-day counts from monthly Defender aggregates. Calculation: SUM of AI_Activity[ActiveDays]; the same day can appear under more than one tool.",
    ),
    (
        "Per-user, per-month risk number combining 8 behavioral signals into one comparable value.",
        "Per-user, per-month risk number combining 7 behavioral signals into one comparable value.",
    ),
    (
        " + DeptOutlier(10)",
        "",
    ),
    (
        "Calculation: user IN DeviceNetworkEvents[AIHost] AND user NOT IN AADSignInEventsBeta[ApprovedAIApps]. If you later add the app to Entra SSO, those users automatically reclassify as Corporate-Granted.",
        "Calculation: DISTINCTCOUNT(AI_Activity[UPN]) where RiskTier = Unsanctioned. Reclassify a tool by updating the catalog and exporter taxonomy.",
    ),
    (
        "Calculation: DISTINCTCOUNT(UPN) where AISolution is in the 3rd-party catalog.",
        "Calculation: DISTINCTCOUNT(AI_Activity[UPN]) where the related catalog Vendor is not Microsoft.",
    ),
    (
        "Defender DeviceNetworkEvents\", 404, \"Verified users + Estimated prompts (managed devices) \u00b7 includes SentBytes for upload volume",
        "Defender CloudAppEvents\", 404, \"Verified users, activity sessions, and estimated prompts where Defender for Cloud Apps data is available",
    ),
    (
        "Defender CloudAppEvents (OAuth consent)",
        "Microsoft Graph directory audits (OAuth consent)",
    ),
    (
        "Entra AADSignInEventsBeta",
        "Microsoft Graph sign-ins + Defender EntraIdSignInEvents",
    ),
    (
        "Microsoft Graph \u2014 Copilot Usage Report",
        "Microsoft Purview \u2014 CopilotInteraction audit",
    ),
)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest().upper()


def sanitize_custom_properties(payload: bytes) -> tuple[bytes, int]:
    ET.register_namespace("", CUSTOM_PROPERTIES_NAMESPACE)
    ET.register_namespace("vt", CUSTOM_PROPERTY_TYPES_NAMESPACE)
    root = ET.fromstring(payload)
    property_tag = f"{{{CUSTOM_PROPERTIES_NAMESPACE}}}property"
    removed = 0
    for item in list(root):
        if item.tag != property_tag:
            continue
        if item.attrib.get("name", "").startswith(MSIP_LABEL_PROPERTY_PREFIX):
            root.remove(item)
            removed += 1
    if not removed:
        return payload, 0
    sanitized = ET.tostring(root, encoding="utf-8", xml_declaration=True)
    return sanitized, removed


def validate_public_package_metadata(archive: zipfile.ZipFile) -> None:
    names = archive.namelist()
    if SECURITY_BINDINGS_ENTRY in names:
        raise ValueError("Generated PBIT still contains SecurityBindings.")
    if SECURITY_BINDINGS_OVERRIDE in archive.read(CONTENT_TYPES_ENTRY):
        raise ValueError(
            "Generated PBIT still declares a SecurityBindings content type."
        )
    if CUSTOM_PROPERTIES_ENTRY not in names:
        return
    custom_properties = archive.read(CUSTOM_PROPERTIES_ENTRY)
    for token in FORBIDDEN_PUBLIC_METADATA:
        if token in custom_properties:
            raise ValueError(
                "Generated PBIT contains non-public custom metadata: "
                f"{token.decode('ascii')}"
            )


def get_table(model: dict, name: str) -> dict:
    matches = [table for table in model["model"]["tables"] if table["name"] == name]
    if len(matches) != 1:
        raise ValueError(f"Expected exactly one table named {name!r}; found {len(matches)}.")
    return matches[0]


def update_query_metadata(unapplied: dict, name: str, lines: list[str], referenced: bool) -> None:
    matches = [query for query in unapplied["queries"] if query["name"] == name]
    if len(matches) != 1:
        raise ValueError(f"Expected exactly one unapplied query named {name!r}; found {len(matches)}.")
    query = matches[0]
    query["text"] = lines
    query["lastLoadedAsTableFormulaText"] = json.dumps(
        {
            "IncludesReferencedQueries": referenced,
            "RootFormulaText": "\n".join(lines),
        },
        separators=(",", ":"),
    )


def normalize_file_query_path(expression: list[str] | str) -> list[str] | str:
    lines = expression if isinstance(expression, list) else expression.splitlines()
    matches = sum(line.count(RAW_FILE_PATH_PREFIX) for line in lines)
    if matches == 0:
        return expression
    if matches != 1 or not lines or lines[0].strip() != "let":
        raise ValueError("Unexpected AI_Data_Folder_Path query structure.")

    normalized = [
        lines[0],
        DATA_FOLDER_M,
        *[
            line.replace(RAW_FILE_PATH_PREFIX, NORMALIZED_FILE_PATH_PREFIX)
            for line in lines[1:]
        ],
    ]
    return normalized


def replace_once(text: str, old: str, new: str) -> str:
    count = text.count(old)
    if count != 1:
        raise ValueError(f"Expected one glossary match for {old!r}; found {count}.")
    return text.replace(old, new)


def add_copilot_surface_model(model: dict, unapplied: dict) -> None:
    if any(
        table["name"] == "AI_CopilotSurfaceUsage"
        for table in model["model"]["tables"]
    ):
        raise ValueError("AI_CopilotSurfaceUsage already exists in the source model.")

    source_table = get_table(model, "AI_CopilotUsage")
    source_columns = {
        column["name"]: column for column in source_table["columns"]
    }
    column_specs = (
        (
            "UserPrincipalName",
            "UserPrincipalName",
            True,
            "User identity used to relate Copilot activity to Entra users.",
        ),
        (
            "YearMonth",
            "YearMonth",
            True,
            "Calendar month in yyyy-MM format.",
        ),
        (
            "Surface",
            "UserPrincipalName",
            False,
            "Friendly Copilot surface derived from Purview AppHost or Workload.",
        ),
        (
            "SourceWorkload",
            "UserPrincipalName",
            False,
            "Original Purview Workload value retained for traceability.",
        ),
        (
            "SourceAppHost",
            "UserPrincipalName",
            False,
            "Original Purview AppHost value retained for traceability.",
        ),
        (
            "PromptCount",
            "TotalPrompts",
            True,
            "Prompt count for the user, month, surface, workload, and app host.",
        ),
        (
            "ActiveDays",
            "ActiveDays",
            True,
            "Distinct activity dates within the surface row.",
        ),
        (
            "LastActivityDate",
            "LastActivityDate",
            False,
            "Most recent activity date within the surface row.",
        ),
    )
    columns = []
    for name, template_name, hidden, description in column_specs:
        column = copy.deepcopy(source_columns[template_name])
        column["name"] = name
        column["sourceColumn"] = name
        column["lineageTag"] = COPILOT_SURFACE_LINEAGE[name]
        column["description"] = description
        if hidden:
            column["isHidden"] = True
        else:
            column.pop("isHidden", None)
        columns.append(column)

    surface_table = copy.deepcopy(source_table)
    surface_table["name"] = "AI_CopilotSurfaceUsage"
    surface_table["lineageTag"] = COPILOT_SURFACE_LINEAGE["table"]
    surface_table["description"] = (
        "Normalized Copilot usage at user, month, surface, source workload, "
        "and source app-host grain."
    )
    surface_table["columns"] = columns
    partition = surface_table["partitions"][0]
    partition["name"] = "AI_CopilotSurfaceUsage-partition"
    partition["source"]["expression"] = COPILOT_SURFACE_M

    source_index = model["model"]["tables"].index(source_table)
    model["model"]["tables"].insert(source_index + 1, surface_table)

    source_query = next(
        query for query in unapplied["queries"] if query["name"] == "AI_CopilotUsage"
    )
    surface_query = copy.deepcopy(source_query)
    surface_query["name"] = "AI_CopilotSurfaceUsage"
    surface_query["lineageTag"] = COPILOT_SURFACE_LINEAGE["table"]
    query_index = unapplied["queries"].index(source_query)
    unapplied["queries"].insert(query_index + 1, surface_query)
    update_query_metadata(
        unapplied,
        "AI_CopilotSurfaceUsage",
        COPILOT_SURFACE_M,
        referenced=False,
    )

    source_relationships = [
        relationship
        for relationship in model["model"]["relationships"]
        if relationship.get("fromTable") == "AI_CopilotUsage"
    ]
    if len(source_relationships) != 2:
        raise ValueError(
            "Expected AI_CopilotUsage relationships to EntraUsers and Calendar."
        )
    for relationship in source_relationships:
        surface_relationship = copy.deepcopy(relationship)
        surface_relationship["fromTable"] = "AI_CopilotSurfaceUsage"
        if relationship.get("toTable") == "EntraUsers":
            surface_relationship["name"] = COPILOT_SURFACE_LINEAGE[
                "userRelationship"
            ]
        elif relationship.get("toTable") == "Calendar":
            surface_relationship["name"] = COPILOT_SURFACE_LINEAGE[
                "calendarRelationship"
            ]
        else:
            raise ValueError("Unexpected AI_CopilotUsage relationship target.")
        model["model"]["relationships"].append(surface_relationship)

    measures_table = get_table(model, "AI Measures")
    if any(
        measure["name"] == "Copilot Surface Prompts"
        for measure in measures_table["measures"]
    ):
        raise ValueError("Copilot Surface Prompts already exists in the source model.")
    source_measure = next(
        measure
        for measure in measures_table["measures"]
        if measure["name"] == "Copilot Prompts"
    )
    surface_measure = copy.deepcopy(source_measure)
    surface_measure["name"] = "Copilot Surface Prompts"
    surface_measure["expression"] = MEASURE_EXPRESSIONS[
        "Copilot Surface Prompts"
    ]
    surface_measure["lineageTag"] = COPILOT_SURFACE_LINEAGE["measure"]
    surface_measure["description"] = (
        "Total prompts from the normalized all-surface Purview export."
    )
    surface_measure["displayFolder"] = "Copilot"
    measures_table["measures"].append(surface_measure)


def transform_model(model: dict, unapplied: dict) -> None:
    add_copilot_surface_model(model, unapplied)

    calendar = get_table(model, "Calendar")
    removed_columns = {
        "Day",
        "DayOfWeek",
        "DayOfWeekNum",
        "WeekStart",
        "WeekNumber",
    }
    calendar["columns"] = [
        column for column in calendar["columns"] if column["name"] not in removed_columns
    ]
    year_month = next(column for column in calendar["columns"] if column["name"] == "YearMonth")
    year_month["isKey"] = True
    calendar["partitions"][0]["source"]["expression"] = CALENDAR_M
    calendar.pop("dataCategory", None)
    for column in calendar["columns"]:
        if column["name"] == "Date":
            column.pop("dataCategory", None)
    for hierarchy in calendar.get("hierarchies", []):
        hierarchy["levels"] = [
            level for level in hierarchy["levels"] if level["column"] not in removed_columns
        ]
    calendar["annotations"] = [
        annotation
        for annotation in calendar.get("annotations", [])
        if annotation["name"] != "PBI_TemplateDateTable"
    ]

    solutions = get_table(model, "AI_Solutions")
    solutions["partitions"][0]["source"]["expression"] = SOLUTIONS_M
    license_status = next(
        column for column in solutions["columns"] if column["name"] == "LicenseStatus"
    )
    license_status["expression"] = LICENSE_STATUS_DAX

    normalized_file_queries: dict[str, list[str]] = {}
    for table in model["model"]["tables"]:
        for partition in table.get("partitions", []):
            source = partition.get("source", {})
            expression = source.get("expression")
            if expression is None:
                continue
            normalized = normalize_file_query_path(expression)
            if normalized == expression:
                continue
            if table["name"] in normalized_file_queries or not isinstance(normalized, list):
                raise ValueError(
                    f"Unexpected file-query partitions for table {table['name']!r}."
                )
            source["expression"] = normalized
            normalized_file_queries[table["name"]] = normalized

    if len(normalized_file_queries) != FILE_QUERY_COUNT:
        raise ValueError(
            f"Expected {FILE_QUERY_COUNT} folder-based queries; "
            f"found {len(normalized_file_queries)}."
        )
    for name, lines in normalized_file_queries.items():
        update_query_metadata(unapplied, name, lines, referenced=False)

    calendar_relationships = [
        relationship
        for relationship in model["model"]["relationships"]
        if relationship.get("toTable") == "Calendar"
        and relationship.get("toColumn") == "YearMonth"
    ]
    if len(calendar_relationships) != 11:
        raise ValueError(
            f"Expected 11 fact-to-Calendar relationships; found {len(calendar_relationships)}."
        )
    for relationship in calendar_relationships:
        relationship["fromCardinality"] = "many"
        relationship["toCardinality"] = "one"
        relationship["crossFilteringBehavior"] = "oneDirection"
        relationship.pop("securityFilteringBehavior", None)

    measures_table = get_table(model, "AI Measures")
    measures = {measure["name"]: measure for measure in measures_table["measures"]}
    missing_measures = sorted(set(MEASURE_EXPRESSIONS) - set(measures))
    if missing_measures:
        raise ValueError(f"Missing measures required for patching: {missing_measures}")
    for name, expression in MEASURE_EXPRESSIONS.items():
        measures[name]["expression"] = expression

    glossary = get_table(model, "Glossary")
    glossary_expression = glossary["partitions"][0]["source"]["expression"]
    if isinstance(glossary_expression, list):
        glossary_expression = "\n".join(glossary_expression)
    for old, new in GLOSSARY_REPLACEMENTS:
        glossary_expression = replace_once(glossary_expression, old, new)
    glossary["partitions"][0]["source"]["expression"] = glossary_expression

    for annotation in model["model"].get("annotations", []):
        if annotation["name"] == "__PBI_TimeIntelligenceEnabled":
            annotation["value"] = "0"
        elif annotation["name"] == "PBI_QueryOrder":
            query_order = json.loads(annotation["value"])
            query_order.remove("Calendar")
            if "AI_CopilotSurfaceUsage" not in query_order:
                copilot_index = query_order.index("AI_CopilotUsage")
                query_order.insert(copilot_index + 1, "AI_CopilotSurfaceUsage")
            parameter = query_order.pop(query_order.index("AI_Data_Folder_Path"))
            query_order.extend(["Calendar", parameter])
            annotation["value"] = json.dumps(query_order, separators=(",", ":"))
    update_query_metadata(unapplied, "Calendar", CALENDAR_M, referenced=True)


def remove_stale_selectors(visual: dict, visual_id: str) -> int:
    data_points = visual.get("visual", {}).get("objects", {}).get("dataPoint", [])
    if not isinstance(data_points, list):
        raise ValueError(f"Visual {visual_id} does not contain a dataPoint list.")
    retained = []
    removed = 0
    for data_point in data_points:
        serialized = json.dumps(data_point, ensure_ascii=False, separators=(",", ":"))
        if any(token in serialized for token in STALE_SELECTOR_TOKENS):
            removed += 1
        else:
            retained.append(data_point)
    if removed != 2:
        raise ValueError(f"Expected to remove 2 stale selectors from {visual_id}; removed {removed}.")
    visual["visual"]["objects"]["dataPoint"] = retained
    return removed


def replace_report_text(visual: dict, visual_id: str) -> None:
    replacements = REPORT_VISUAL_REPLACEMENTS[visual_id]
    counts = [0] * len(replacements)

    def visit(value):
        if isinstance(value, dict):
            for key, child in value.items():
                value[key] = visit(child)
        elif isinstance(value, list):
            for index, child in enumerate(value):
                value[index] = visit(child)
        elif isinstance(value, str):
            for index, (old, new) in enumerate(replacements):
                if value == old:
                    value = new
                    counts[index] += 1
        return value

    visit(visual)
    invalid = [
        old
        for count, (old, _) in zip(counts, replacements)
        if count != 1
    ]
    if invalid:
        raise ValueError(
            f"Expected one match for each report-text replacement in {visual_id}; "
            f"invalid matches: {invalid}"
        )


def update_copilot_surface_visual(visual: dict, visual_id: str) -> None:
    if visual_id != COPILOT_SURFACE_VISUAL_ID:
        raise ValueError(f"Unexpected Copilot surface visual id: {visual_id}")

    visual_root = visual.get("visual")
    if not isinstance(visual_root, dict) or visual_root.get("visualType") != "columnChart":
        raise ValueError("Copilot surface visual is not the expected column chart.")

    surface_field = {
        "Column": {
            "Expression": {
                "SourceRef": {"Entity": "AI_CopilotSurfaceUsage"}
            },
            "Property": "Surface",
        }
    }
    prompt_measure = {
        "Measure": {
            "Expression": {"SourceRef": {"Entity": "AI Measures"}},
            "Property": "Copilot Surface Prompts",
        }
    }
    visual_root["query"]["queryState"] = {
        "Category": {
            "projections": [
                {
                    "field": surface_field,
                    "queryRef": "AI_CopilotSurfaceUsage.Surface",
                    "nativeQueryRef": "Surface",
                }
            ]
        },
        "Y": {
            "projections": [
                {
                    "field": prompt_measure,
                    "queryRef": "AI Measures.Copilot Surface Prompts",
                    "nativeQueryRef": "Copilot Surface Prompts",
                }
            ]
        },
    }
    visual_root["query"]["sortDefinition"] = {
        "sort": [{"field": prompt_measure, "direction": "Descending"}],
        "isDefaultSort": False,
    }
    legend = visual_root.get("objects", {}).get("legend", [])
    if legend:
        legend[0].setdefault("properties", {})["show"] = {
            "expr": {"Literal": {"Value": "false"}}
        }


def add_missing_native_query_refs(visual: dict) -> int:
    query_state = (
        visual.get("visual", {})
        .get("query", {})
        .get("queryState", {})
    )
    if not isinstance(query_state, dict):
        return 0

    added = 0
    for role in query_state.values():
        if not isinstance(role, dict):
            continue
        for projection in role.get("projections", []):
            if not isinstance(projection, dict) or "nativeQueryRef" in projection:
                continue
            field = projection.get("field", {})
            native_ref = None
            for field_kind in ("Column", "Measure"):
                field_definition = field.get(field_kind)
                if isinstance(field_definition, dict):
                    native_ref = field_definition.get("Property")
                    if native_ref:
                        break
            if native_ref:
                projection["nativeQueryRef"] = native_ref
                added += 1
    return added


def encode_model(model: dict) -> bytes:
    text = json.dumps(model, ensure_ascii=False, indent=2)
    return text.replace("\n", "\r\n").encode("utf-16-le")


def validate_transformed_payloads(
    model: dict,
    unapplied: dict,
    visuals: dict[str, dict],
) -> None:
    calendar = get_table(model, "Calendar")
    calendar_columns = {column["name"] for column in calendar["columns"]}
    if calendar_columns != {
        "Date",
        "Year",
        "Quarter",
        "QuarterNum",
        "MonthNumber",
        "MonthName",
        "MonthLabel",
        "YearMonth",
        "SortOrder",
    }:
        raise ValueError(f"Unexpected Calendar columns: {sorted(calendar_columns)}")
    calendar_m = calendar["partitions"][0]["source"]["expression"]
    if "DateTime.LocalNow" in "\n".join(calendar_m):
        raise ValueError("Calendar still depends on the refresh date.")

    for relationship in model["model"]["relationships"]:
        if relationship.get("toTable") == "Calendar":
            if relationship.get("fromCardinality") != "many":
                raise ValueError("Calendar relationship has an invalid from-cardinality.")
            if relationship.get("toCardinality") != "one":
                raise ValueError("Calendar relationship has an invalid to-cardinality.")

    serialized_model = json.dumps(model, ensure_ascii=False)
    forbidden = (
        "AADSignInEventsBeta",
        '"HasConditionalAccess] = \\"No\\""',
        '"Unmanaged AI","Developer AI"',
        "DateTime.LocalNow",
    )
    for token in forbidden:
        if token in serialized_model:
            raise ValueError(f"Obsolete model token remains: {token}")

    calendar_query = next(
        query for query in unapplied["queries"] if query["name"] == "Calendar"
    )
    if calendar_query["text"] != CALENDAR_M:
        raise ValueError("UnappliedChanges Calendar query is not synchronized.")

    surface_table = get_table(model, "AI_CopilotSurfaceUsage")
    surface_columns = {column["name"] for column in surface_table["columns"]}
    expected_surface_columns = {
        "UserPrincipalName",
        "YearMonth",
        "Surface",
        "SourceWorkload",
        "SourceAppHost",
        "PromptCount",
        "ActiveDays",
        "LastActivityDate",
    }
    if surface_columns != expected_surface_columns:
        raise ValueError(
            f"Unexpected Copilot surface columns: {sorted(surface_columns)}"
        )
    surface_relationship_targets = {
        relationship.get("toTable")
        for relationship in model["model"]["relationships"]
        if relationship.get("fromTable") == "AI_CopilotSurfaceUsage"
    }
    if surface_relationship_targets != {"Calendar", "EntraUsers"}:
        raise ValueError(
            "AI_CopilotSurfaceUsage is not related to Calendar and EntraUsers."
        )
    measures = {
        measure["name"]: measure
        for measure in get_table(model, "AI Measures")["measures"]
    }
    if measures["Copilot Surface Prompts"]["expression"] != (
        "SUM('AI_CopilotSurfaceUsage'[PromptCount])"
    ):
        raise ValueError("Copilot Surface Prompts has an unexpected expression.")

    normalized_file_queries = {}
    for table in model["model"]["tables"]:
        for partition in table.get("partitions", []):
            expression = partition.get("source", {}).get("expression")
            if not isinstance(expression, list):
                continue
            text = "\n".join(expression)
            if RAW_FILE_PATH_PREFIX in text:
                raise ValueError(
                    f"Table {table['name']!r} still requires a trailing folder separator."
                )
            if NORMALIZED_FILE_PATH_PREFIX in text:
                if expression.count(DATA_FOLDER_M) != 1:
                    raise ValueError(
                        f"Table {table['name']!r} has invalid folder normalization."
                    )
                normalized_file_queries[table["name"]] = expression

    if len(normalized_file_queries) != FILE_QUERY_COUNT:
        raise ValueError(
            f"Expected {FILE_QUERY_COUNT} normalized file queries; "
            f"found {len(normalized_file_queries)}."
        )
    unapplied_queries = {query["name"]: query for query in unapplied["queries"]}
    for name, expression in normalized_file_queries.items():
        if unapplied_queries[name]["text"] != expression:
            raise ValueError(
                f"UnappliedChanges query {name!r} is not synchronized."
            )

    for visual_id, visual in visuals.items():
        serialized = json.dumps(visual, ensure_ascii=False)
        stale = [token for token in STALE_SELECTOR_TOKENS if token in serialized]
        if stale:
            raise ValueError(f"Visual {visual_id} still contains stale selectors: {stale}")
        for old, _ in REPORT_VISUAL_REPLACEMENTS.get(visual_id, ()):
            if old in serialized:
                raise ValueError(
                    f"Visual {visual_id} still contains obsolete report text: {old}"
                )
        if visual_id == COPILOT_SURFACE_VISUAL_ID:
            query_state = visual["visual"]["query"]["queryState"]
            if set(query_state) != {"Category", "Y"}:
                raise ValueError("Copilot surface visual has unexpected query roles.")
            if "AI_CopilotSurfaceUsage.Surface" not in serialized:
                raise ValueError("Copilot surface visual is not bound to Surface.")
            if "AI Measures.Copilot Surface Prompts" not in serialized:
                raise ValueError(
                    "Copilot surface visual is not bound to the surface measure."
                )
            for legacy_measure in (
                "Teams Prompts",
                "Word Prompts",
                "Excel Prompts",
                "Outlook Prompts",
                "PowerPoint Prompts",
                "Chat Prompts",
            ):
                if legacy_measure in serialized:
                    raise ValueError(
                        f"Copilot surface visual still references {legacy_measure}."
                    )


def build_pbit(source: Path, output: Path) -> dict[str, str | int]:
    source = source.resolve()
    output = output.resolve()
    if not source.is_file():
        raise FileNotFoundError(f"Source PBIT not found: {source}")
    if source == output:
        raise ValueError("Output path must differ from the source PBIT.")
    output.parent.mkdir(parents=True, exist_ok=True)

    replacements: dict[str, bytes] = {}
    with zipfile.ZipFile(source, "r") as archive:
        names = archive.namelist()
        for required in (
            MODEL_ENTRY,
            UNAPPLIED_ENTRY,
            CONTENT_TYPES_ENTRY,
        ):
            if names.count(required) != 1:
                raise ValueError(f"Expected one {required!r} package entry.")
        if names.count(SECURITY_BINDINGS_ENTRY) > 1:
            raise ValueError("Expected at most one SecurityBindings package entry.")
        if names.count(CUSTOM_PROPERTIES_ENTRY) > 1:
            raise ValueError("Expected at most one custom-properties package entry.")
        has_security_bindings = SECURITY_BINDINGS_ENTRY in names
        output_names = [name for name in names if name != SECURITY_BINDINGS_ENTRY]

        content_types = archive.read(CONTENT_TYPES_ENTRY)
        security_override_count = content_types.count(SECURITY_BINDINGS_OVERRIDE)
        if has_security_bindings:
            if security_override_count != 1:
                raise ValueError("Expected one SecurityBindings content-type override.")
            replacements[CONTENT_TYPES_ENTRY] = content_types.replace(
                SECURITY_BINDINGS_OVERRIDE,
                b"",
                1,
            )
        elif security_override_count:
            raise ValueError(
                "Found a SecurityBindings content-type override without its entry."
            )

        if CUSTOM_PROPERTIES_ENTRY in names:
            custom_properties = archive.read(CUSTOM_PROPERTIES_ENTRY)
            sanitized_properties, removed_properties = sanitize_custom_properties(
                custom_properties
            )
            if removed_properties:
                replacements[CUSTOM_PROPERTIES_ENTRY] = sanitized_properties

        model = json.loads(archive.read(MODEL_ENTRY).decode("utf-16-le"))
        unapplied = json.loads(archive.read(UNAPPLIED_ENTRY).decode("utf-16-le"))
        transform_model(model, unapplied)

        visual_entries = [
            name
            for name in names
            if "/visuals/" in name and name.endswith("/visual.json")
        ]
        visual_payloads: dict[str, dict] = {}
        patched_visual_counts = {visual_id: 0 for visual_id in PATCHED_VISUAL_IDS}
        for visual_entry in visual_entries:
            visual_id = visual_entry.rsplit("/", 2)[1]
            visual = json.loads(archive.read(visual_entry).decode("utf-8"))
            changed = False
            if visual_id in STALE_VISUAL_IDS:
                remove_stale_selectors(visual, visual_id)
                changed = True
            if visual_id in REPORT_VISUAL_REPLACEMENTS:
                replace_report_text(visual, visual_id)
                changed = True
            if visual_id == COPILOT_SURFACE_VISUAL_ID:
                update_copilot_surface_visual(visual, visual_id)
                changed = True
            if add_missing_native_query_refs(visual):
                changed = True
            if visual_id in patched_visual_counts:
                patched_visual_counts[visual_id] += 1
                visual_payloads[visual_id] = visual
            if changed:
                replacements[visual_entry] = json.dumps(
                    visual, ensure_ascii=False, separators=(",", ":")
                ).encode("utf-8")

        invalid_patched_visuals = {
            visual_id: count
            for visual_id, count in patched_visual_counts.items()
            if count != 1
        }
        if invalid_patched_visuals:
            details = ", ".join(
                f"{visual_id}={count}"
                for visual_id, count in sorted(invalid_patched_visuals.items())
            )
            raise ValueError(
                "Expected one entry for every patched visual; found " + details
            )

        validate_transformed_payloads(model, unapplied, visual_payloads)
        replacements[MODEL_ENTRY] = encode_model(model)
        replacements[UNAPPLIED_ENTRY] = json.dumps(
            unapplied, ensure_ascii=False, separators=(",", ":")
        ).encode("utf-16-le")

        source_entries = archive.infolist()
        source_comment = archive.comment
        fd, temporary_name = tempfile.mkstemp(
            prefix=output.stem + ".",
            suffix=".tmp",
            dir=output.parent,
        )
        os.close(fd)
        temporary_path = Path(temporary_name)
        try:
            with zipfile.ZipFile(
                temporary_path,
                "w",
                allowZip64=True,
                strict_timestamps=False,
            ) as destination:
                destination.comment = source_comment
                for source_info in source_entries:
                    if source_info.filename == SECURITY_BINDINGS_ENTRY:
                        continue
                    payload = replacements.get(
                        source_info.filename,
                        archive.read(source_info.filename),
                    )
                    destination.writestr(copy.copy(source_info), payload)
            os.replace(temporary_path, output)
        finally:
            if temporary_path.exists():
                temporary_path.unlink()

    with zipfile.ZipFile(output, "r") as generated:
        if generated.namelist() != output_names:
            raise ValueError(
                "Generated package entry ordering differs from the source minus "
                "SecurityBindings."
            )
        if generated.testzip() is not None:
            raise ValueError("Generated PBIT contains a corrupt ZIP entry.")
        validate_public_package_metadata(generated)
        output_model = json.loads(generated.read(MODEL_ENTRY).decode("utf-16-le"))
        output_unapplied = json.loads(generated.read(UNAPPLIED_ENTRY).decode("utf-16-le"))
        output_visuals = {}
        for visual_id in PATCHED_VISUAL_IDS:
            name = next(
                entry
                for entry in names
                if entry.endswith(f"/visuals/{visual_id}/visual.json")
            )
            output_visuals[visual_id] = json.loads(generated.read(name).decode("utf-8"))
        validate_transformed_payloads(
            output_model,
            output_unapplied,
            output_visuals,
        )

    return {
        "source": str(source),
        "source_sha256": sha256(source),
        "output": str(output),
        "output_sha256": sha256(output),
        "entries": len(output_names),
        "patched_entries": len(replacements),
        "removed_entries": int(has_security_bindings),
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Build a deterministic, validated V26 Power BI template."
    )
    parser.add_argument(
        "--source",
        type=Path,
        default=DEFAULT_SOURCE,
        help=f"Source PBIT (default: {DEFAULT_SOURCE.name})",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=DEFAULT_OUTPUT,
        help=f"Output PBIT (default: {DEFAULT_OUTPUT.name})",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    result = build_pbit(args.source, args.output)
    print("Validated PBIT generated.")
    print(f"  Source : {result['source']}")
    print(f"  SHA-256: {result['source_sha256']}")
    print(f"  Output : {result['output']}")
    print(f"  SHA-256: {result['output_sha256']}")
    print(
        f"  Entries: {result['entries']} "
        f"({result['patched_entries']} patched, "
        f"{result['removed_entries']} removed)"
    )


if __name__ == "__main__":
    main()
