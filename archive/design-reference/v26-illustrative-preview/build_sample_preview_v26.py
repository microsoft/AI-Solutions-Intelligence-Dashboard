#!/usr/bin/env python3
"""Build the animated dashboard preview from synthetic sample data only."""

from __future__ import annotations

import csv
import re
from collections import Counter
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parent
SAMPLE_DIR = ROOT / "sample_data_v26"
OUTPUT_PATH = ROOT / "images" / "report-preview.gif"

EXPECTED_FILES = {
    "EntraUsers.csv",
    "ai_activity_sessions.csv",
    "ai_appgov_alerts.csv",
    "ai_client_channel.csv",
    "ai_cloud_discovery.csv",
    "ai_copilot_surface_usage.csv",
    "ai_copilot_usage_graph.csv",
    "ai_file_proximity.csv",
    "ai_mda_sessions.csv",
    "ai_oauth_consents.csv",
    "ai_offhours_geo.csv",
    "ai_solutions_catalog.csv",
    "ai_sso_signins.csv",
}
ALLOWED_USER_DOMAINS = {"contoso.com"}
EMAIL_PATTERN = re.compile(
    r"[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@(?:[A-Za-z0-9-]+\.)+[A-Za-z]{2,}"
)

WIDTH = 1280
HEIGHT = 720
SIDEBAR_WIDTH = 220
CONTENT_LEFT = 248
CONTENT_RIGHT = 1252
CONTENT_WIDTH = CONTENT_RIGHT - CONTENT_LEFT

COLORS = {
    "purple": "#4B2D83",
    "purple_dark": "#32205F",
    "blue": "#003087",
    "violet": "#8A2BE2",
    "green": "#2EA44F",
    "teal": "#167A7A",
    "orange": "#D67213",
    "red": "#B02A2A",
    "yellow": "#F2B134",
    "ink": "#1B1F27",
    "muted": "#5A6472",
    "line": "#E3E6EC",
    "bg": "#F6F7FB",
    "white": "#FFFFFF",
    "lavender": "#EEE9F8",
    "pale_blue": "#E8EFFB",
    "pale_green": "#E8F6EC",
    "pale_orange": "#FCEFE1",
    "pale_red": "#F9E6E6",
}

PAGE_NAMES = [
    "Executive Summary",
    "Copilot Deep Dive",
    "Behavioral Risk",
    "Shadow AI",
    "Dept Intensity",
    "Department Breakdown",
    "Shadow AI Catalog",
    "Benchmarks & Targets",
    "Glossary",
    "Tier Comparison",
]


def load_font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
    windows_fonts = Path("C:/Windows/Fonts")
    candidates = [
        windows_fonts / ("seguisb.ttf" if bold else "segoeui.ttf"),
        Path("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf")
        if bold
        else Path("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"),
    ]
    for candidate in candidates:
        if candidate.exists():
            return ImageFont.truetype(str(candidate), size)
    return ImageFont.load_default()


FONT_11 = load_font(11)
FONT_12 = load_font(12)
FONT_13 = load_font(13)
FONT_13_BOLD = load_font(13, bold=True)
FONT_14 = load_font(14)
FONT_14_BOLD = load_font(14, bold=True)
FONT_16 = load_font(16)
FONT_16_BOLD = load_font(16, bold=True)
FONT_18_BOLD = load_font(18, bold=True)
FONT_20_BOLD = load_font(20, bold=True)
FONT_26_BOLD = load_font(26, bold=True)
FONT_30_BOLD = load_font(30, bold=True)


def read_rows(file_name: str) -> list[dict[str, str]]:
    with (SAMPLE_DIR / file_name).open(
        encoding="utf-8-sig", newline=""
    ) as handle:
        return list(csv.DictReader(handle))


def validate_sample_source() -> None:
    actual_files = {path.name for path in SAMPLE_DIR.glob("*.csv")}
    if actual_files != EXPECTED_FILES:
        missing = sorted(EXPECTED_FILES - actual_files)
        extra = sorted(actual_files - EXPECTED_FILES)
        raise ValueError(
            f"Sample input contract failed. Missing={missing}; extra={extra}"
        )

    detected_domains: set[str] = set()
    for file_name in sorted(EXPECTED_FILES):
        with (SAMPLE_DIR / file_name).open(
            encoding="utf-8-sig", newline=""
        ) as handle:
            for row in csv.reader(handle):
                for value in row:
                    for address in EMAIL_PATTERN.findall(value):
                        detected_domains.add(address.rsplit("@", 1)[1].lower())

    if detected_domains != ALLOWED_USER_DOMAINS:
        raise ValueError(
            "Preview generation stopped: unexpected email domains "
            f"{sorted(detected_domains)}"
        )


def build_metrics() -> dict[str, object]:
    entra = read_rows("EntraUsers.csv")
    activity = read_rows("ai_activity_sessions.csv")
    copilot = read_rows("ai_copilot_usage_graph.csv")
    surfaces = read_rows("ai_copilot_surface_usage.csv")
    oauth = read_rows("ai_oauth_consents.csv")
    proximity = read_rows("ai_file_proximity.csv")
    offhours = read_rows("ai_offhours_geo.csv")
    signins = read_rows("ai_sso_signins.csv")
    cloud = read_rows("ai_cloud_discovery.csv")
    mda = read_rows("ai_mda_sessions.csv")
    alerts = read_rows("ai_appgov_alerts.csv")

    department_by_upn = {
        row["userPrincipalName"]: row["department"] for row in entra
    }
    ai_users = {row["UPN"] for row in activity} | {
        row["UserPrincipalName"] for row in copilot
    }
    copilot_users = {row["UserPrincipalName"] for row in copilot}
    licensed_users = {
        row["userPrincipalName"]
        for row in entra
        if "Copilot" in row["assignedLicenses"]
    }
    unmanaged_users = {
        row["UPN"] for row in activity if row["RiskTier"] == "Unsanctioned"
    }

    by_tool: Counter[str] = Counter()
    by_surface: Counter[str] = Counter()
    by_department: Counter[str] = Counter()
    by_tier: Counter[str] = Counter()
    by_domain: Counter[str] = Counter()
    heat: Counter[tuple[str, str]] = Counter()

    for row in activity:
        sessions = int(row["Sessions"])
        department = department_by_upn[row["UPN"]]
        by_tool[row["AISolution"]] += sessions
        by_department[department] += sessions
        by_tier[row["RiskTier"]] += sessions
        heat[(department, row["AISolution"])] += sessions

    for row in surfaces:
        by_surface[row["Surface"]] += int(row["PromptCount"])
    for row in cloud:
        by_domain[row["AIDomain"]] += int(row["TransactionCount"])

    total_offhours = sum(int(row["OffHoursSessions"]) for row in offhours)
    total_signin_sessions = sum(int(row["TotalSessions"]) for row in offhours)

    return {
        "total_users": len(entra),
        "ai_users": len(ai_users),
        "adoption": 100 * len(ai_users) / len(entra),
        "copilot_users": len(copilot_users),
        "licensed_users": len(licensed_users),
        "license_utilization": (
            100 * len(copilot_users & licensed_users) / len(licensed_users)
        ),
        "unmanaged_users": len(unmanaged_users),
        "unmanaged_share": 100 * len(unmanaged_users) / len(ai_users),
        "total_sessions": sum(by_tool.values()),
        "total_prompts": sum(by_surface.values()),
        "file_proximity": len(proximity),
        "sensitive_proximity": sum(
            row["NameMatchesSensitivePattern"] == "1"
            or row["FolderMatchesSensitive"] == "1"
            for row in proximity
        ),
        "oauth_risk_points": sum(
            int(row["ConsentCount"]) * int(row["PermissionWeight"])
            for row in oauth
        ),
        "offhours_pct": 100 * total_offhours / total_signin_sessions,
        "geo_anomalies": sum(
            int(row["AnomalousCountryCount"]) for row in offhours
        ),
        "logins_without_ca": sum(
            int(row["SignInCount"])
            for row in signins
            if row["HasConditionalAccess"] == "FALSE"
        ),
        "cloud_domains": len({row["AIDomain"] for row in cloud}),
        "unsanctioned_domains": len(
            {
                row["AIDomain"]
                for row in cloud
                if row["SanctionStatus"] == "Unsanctioned"
            }
        ),
        "mda_events": sum(int(row["EventCount"]) for row in mda),
        "appgov_alerts": len(alerts),
        "by_tool": by_tool,
        "by_surface": by_surface,
        "by_department": by_department,
        "by_tier": by_tier,
        "by_domain": by_domain,
        "heat": heat,
    }


def short_number(value: float) -> str:
    if abs(value) >= 1_000_000:
        return f"{value / 1_000_000:.1f}M"
    if abs(value) >= 1_000:
        return f"{value / 1_000:.1f}K"
    return f"{value:,.0f}"


def rounded_card(
    draw: ImageDraw.ImageDraw,
    box: tuple[int, int, int, int],
    fill: str = COLORS["white"],
    outline: str = COLORS["line"],
) -> None:
    x1, y1, x2, y2 = box
    draw.rounded_rectangle(
        (x1 + 3, y1 + 5, x2 + 3, y2 + 5),
        radius=12,
        fill="#DADDE5",
    )
    draw.rounded_rectangle(
        box, radius=12, fill=fill, outline=outline, width=1
    )


def draw_wrapped(
    draw: ImageDraw.ImageDraw,
    text: str,
    box: tuple[int, int, int, int],
    font: ImageFont.FreeTypeFont,
    fill: str,
    spacing: int = 5,
) -> None:
    x1, y1, x2, _ = box
    words = text.split()
    lines: list[str] = []
    current = ""
    for word in words:
        candidate = word if not current else f"{current} {word}"
        if draw.textbbox((0, 0), candidate, font=font)[2] <= x2 - x1:
            current = candidate
        else:
            if current:
                lines.append(current)
            current = word
    if current:
        lines.append(current)
    draw.multiline_text(
        (x1, y1), "\n".join(lines), font=font, fill=fill, spacing=spacing
    )


def base_frame(
    page_index: int, title: str, subtitle: str
) -> tuple[Image.Image, ImageDraw.ImageDraw]:
    image = Image.new("RGB", (WIDTH, HEIGHT), COLORS["bg"])
    draw = ImageDraw.Draw(image)

    for y in range(HEIGHT):
        ratio = y / HEIGHT
        start = (75, 45, 131)
        end = (0, 48, 135)
        color = tuple(
            int(start[channel] * (1 - ratio) + end[channel] * ratio)
            for channel in range(3)
        )
        draw.line((0, y, SIDEBAR_WIDTH, y), fill=color)

    draw.ellipse((24, 24, 58, 58), fill=COLORS["violet"])
    draw.text((34, 29), "AI", font=FONT_13_BOLD, fill=COLORS["white"])
    draw.text(
        (70, 23), "AI SOLUTIONS", font=FONT_14_BOLD, fill=COLORS["white"]
    )
    draw.text(
        (70, 42), "INTELLIGENCE", font=FONT_12, fill="#DED8EC"
    )

    nav_y = 95
    for index, name in enumerate(PAGE_NAMES):
        y1 = nav_y + index * 52
        if index == page_index:
            draw.rounded_rectangle(
                (14, y1 - 8, 206, y1 + 29),
                radius=8,
                fill="#FFFFFF",
            )
            draw.ellipse(
                (27, y1 + 3, 35, y1 + 11), fill=COLORS["violet"]
            )
            color = COLORS["purple"]
            font = FONT_13_BOLD
        else:
            draw.ellipse((27, y1 + 3, 35, y1 + 11), fill="#998DB8")
            color = "#E4DEEE"
            font = FONT_13
        draw.text((44, y1), name, font=font, fill=color)

    draw.text(
        (CONTENT_LEFT, 22), title, font=FONT_30_BOLD, fill=COLORS["ink"]
    )
    draw.text(
        (CONTENT_LEFT, 66), subtitle, font=FONT_14, fill=COLORS["muted"]
    )
    badge = (1040, 22, 1252, 58)
    draw.rounded_rectangle(
        badge,
        radius=18,
        fill=COLORS["pale_green"],
        outline="#A8DDB6",
    )
    draw.ellipse((1055, 34, 1067, 46), fill=COLORS["green"])
    draw.text(
        (1077, 31),
        "SAMPLE DATA ONLY",
        font=FONT_13_BOLD,
        fill="#1F6B2E",
    )

    draw.line(
        (CONTENT_LEFT, 680, CONTENT_RIGHT, 680),
        fill=COLORS["line"],
        width=1,
    )
    draw.text(
        (CONTENT_LEFT, 691),
        "Synthetic Contoso dataset | Seed 20260504 | No tenant or employee data",
        font=FONT_11,
        fill=COLORS["muted"],
    )
    page_text = f"Page {page_index + 1} of {len(PAGE_NAMES)}"
    page_width = draw.textbbox((0, 0), page_text, font=FONT_11)[2]
    draw.text(
        (CONTENT_RIGHT - page_width, 691),
        page_text,
        font=FONT_11,
        fill=COLORS["muted"],
    )
    return image, draw


def draw_kpis(
    draw: ImageDraw.ImageDraw,
    items: list[tuple[str, str, str]],
    top: int = 112,
) -> None:
    gap = 14
    card_width = (CONTENT_WIDTH - gap * 3) // 4
    for index, (label, value, accent) in enumerate(items):
        x1 = CONTENT_LEFT + index * (card_width + gap)
        x2 = x1 + card_width
        rounded_card(draw, (x1, top, x2, top + 98))
        draw.rounded_rectangle(
            (x1, top, x1 + 7, top + 98),
            radius=4,
            fill=accent,
        )
        draw.text(
            (x1 + 20, top + 15),
            label.upper(),
            font=FONT_11,
            fill=COLORS["muted"],
        )
        draw.text(
            (x1 + 20, top + 43),
            value,
            font=FONT_26_BOLD,
            fill=COLORS["ink"],
        )


def draw_bar_chart(
    draw: ImageDraw.ImageDraw,
    box: tuple[int, int, int, int],
    title: str,
    data: list[tuple[str, int]],
    colors: list[str] | None = None,
    label_width: int = 155,
) -> None:
    rounded_card(draw, box)
    x1, y1, x2, y2 = box
    draw.text(
        (x1 + 20, y1 + 16), title, font=FONT_18_BOLD, fill=COLORS["ink"]
    )
    if not data:
        return
    max_value = max(value for _, value in data) or 1
    row_height = max(36, (y2 - y1 - 72) // len(data))
    chart_left = x1 + 20 + label_width
    chart_right = x2 - 72
    for index, (label, value) in enumerate(data):
        y = y1 + 58 + index * row_height
        draw.text(
            (x1 + 20, y + 3),
            label[:22],
            font=FONT_13,
            fill=COLORS["ink"],
        )
        draw.rounded_rectangle(
            (chart_left, y, chart_right, y + 22),
            radius=6,
            fill="#ECEEF3",
        )
        bar_right = chart_left + int(
            (chart_right - chart_left) * value / max_value
        )
        bar_color = colors[index % len(colors)] if colors else COLORS["violet"]
        draw.rounded_rectangle(
            (chart_left, y, max(chart_left + 7, bar_right), y + 22),
            radius=6,
            fill=bar_color,
        )
        value_text = short_number(value)
        draw.text(
            (chart_right + 10, y + 2),
            value_text,
            font=FONT_12,
            fill=COLORS["muted"],
        )


def draw_tier_mix(
    draw: ImageDraw.ImageDraw,
    box: tuple[int, int, int, int],
    data: Counter[str],
) -> None:
    rounded_card(draw, box)
    x1, y1, x2, _ = box
    draw.text(
        (x1 + 20, y1 + 16),
        "Sessions by governance tier",
        font=FONT_18_BOLD,
        fill=COLORS["ink"],
    )
    total = sum(data.values()) or 1
    palette = {
        "Sanctioned": COLORS["green"],
        "Conditional": COLORS["orange"],
        "Unsanctioned": COLORS["red"],
    }
    start_angle = -90
    for label in ("Sanctioned", "Conditional", "Unsanctioned"):
        value = data[label]
        sweep = 360 * value / total
        draw.pieslice(
            (x1 + 35, y1 + 70, x1 + 235, y1 + 270),
            start=start_angle,
            end=start_angle + sweep,
            fill=palette[label],
        )
        start_angle += sweep
    draw.ellipse(
        (x1 + 91, y1 + 126, x1 + 179, y1 + 214),
        fill=COLORS["white"],
    )
    draw.text(
        (x1 + 106, y1 + 151),
        short_number(total),
        font=FONT_18_BOLD,
        fill=COLORS["ink"],
    )
    draw.text(
        (x1 + 105, y1 + 174),
        "sessions",
        font=FONT_11,
        fill=COLORS["muted"],
    )
    legend_y = y1 + 86
    for label in ("Sanctioned", "Conditional", "Unsanctioned"):
        value = data[label]
        draw.rounded_rectangle(
            (x1 + 270, legend_y, x1 + 284, legend_y + 14),
            radius=3,
            fill=palette[label],
        )
        draw.text(
            (x1 + 295, legend_y - 2),
            label,
            font=FONT_13_BOLD,
            fill=COLORS["ink"],
        )
        draw.text(
            (x1 + 295, legend_y + 18),
            f"{short_number(value)} ({100 * value / total:.1f}%)",
            font=FONT_12,
            fill=COLORS["muted"],
        )
        legend_y += 66


def slide_executive(metrics: dict[str, object]) -> Image.Image:
    image, draw = base_frame(
        0,
        "Executive Summary",
        "Adoption, license utilization, and governance posture at a glance",
    )
    draw_kpis(
        draw,
        [
            ("AI users", str(metrics["ai_users"]), COLORS["violet"]),
            ("Workforce adoption", f"{metrics['adoption']:.0f}%", COLORS["blue"]),
            (
                "License utilization",
                f"{metrics['license_utilization']:.0f}%",
                COLORS["green"],
            ),
            (
                "Unmanaged AI users",
                str(metrics["unmanaged_users"]),
                COLORS["red"],
            ),
        ],
    )
    by_tool = metrics["by_tool"]
    assert isinstance(by_tool, Counter)
    draw_bar_chart(
        draw,
        (CONTENT_LEFT, 232, 820, 654),
        "Top AI solutions by sessions",
        by_tool.most_common(6),
        [
            COLORS["blue"],
            COLORS["violet"],
            COLORS["purple"],
            COLORS["teal"],
            COLORS["orange"],
            COLORS["red"],
        ],
    )
    by_tier = metrics["by_tier"]
    assert isinstance(by_tier, Counter)
    draw_tier_mix(draw, (840, 232, CONTENT_RIGHT, 654), by_tier)
    return image


def slide_copilot(metrics: dict[str, object]) -> Image.Image:
    image, draw = base_frame(
        1,
        "Copilot Deep Dive",
        "Prompt activity across Microsoft 365 Copilot surfaces",
    )
    by_surface = metrics["by_surface"]
    assert isinstance(by_surface, Counter)
    draw_kpis(
        draw,
        [
            ("Copilot users", str(metrics["copilot_users"]), COLORS["blue"]),
            (
                "Surface prompts",
                short_number(float(metrics["total_prompts"])),
                COLORS["violet"],
            ),
            ("Observed surfaces", str(len(by_surface)), COLORS["teal"]),
            (
                "License utilization",
                f"{metrics['license_utilization']:.0f}%",
                COLORS["green"],
            ),
        ],
    )
    draw_bar_chart(
        draw,
        (CONTENT_LEFT, 232, CONTENT_RIGHT, 654),
        "Prompt volume by surface",
        by_surface.most_common(10),
        [
            COLORS["blue"],
            COLORS["violet"],
            COLORS["purple"],
            COLORS["teal"],
            COLORS["orange"],
        ],
        label_width=125,
    )
    return image


def slide_risk(metrics: dict[str, object]) -> Image.Image:
    image, draw = base_frame(
        2,
        "Behavioral Risk",
        "Prioritization signals for investigation, not proof of data leakage",
    )
    draw_kpis(
        draw,
        [
            (
                "File proximity events",
                str(metrics["file_proximity"]),
                COLORS["violet"],
            ),
            (
                "Sensitive signals",
                str(metrics["sensitive_proximity"]),
                COLORS["red"],
            ),
            (
                "Off-hours share",
                f"{metrics['offhours_pct']:.1f}%",
                COLORS["orange"],
            ),
            (
                "Geo anomalies",
                str(metrics["geo_anomalies"]),
                COLORS["blue"],
            ),
        ],
    )
    draw_bar_chart(
        draw,
        (CONTENT_LEFT, 232, 800, 654),
        "Synthetic risk signal counts",
        [
            ("Logins without CA", int(metrics["logins_without_ca"])),
            ("OAuth risk points", int(metrics["oauth_risk_points"])),
            ("File proximity events", int(metrics["file_proximity"])),
            ("Sensitive proximity", int(metrics["sensitive_proximity"])),
            ("Geo anomaly events", int(metrics["geo_anomalies"])),
        ],
        [
            COLORS["red"],
            COLORS["orange"],
            COLORS["violet"],
            COLORS["purple"],
            COLORS["blue"],
        ],
        label_width=145,
    )
    rounded_card(draw, (820, 232, CONTENT_RIGHT, 654), COLORS["pale_orange"])
    draw.text(
        (845, 256),
        "Interpret carefully",
        font=FONT_20_BOLD,
        fill=COLORS["orange"],
    )
    notes = [
        "File proximity means a file event occurred within five minutes of an AI event.",
        "It does not prove that content was uploaded or disclosed.",
        "Off-hours and geo signals need user, travel, and business context.",
        "Use the risk score to prioritize review, then validate with source evidence.",
    ]
    y = 306
    for note in notes:
        draw.ellipse((845, y + 5, 855, y + 15), fill=COLORS["orange"])
        draw_wrapped(
            draw,
            note,
            (870, y, 1225, y + 70),
            FONT_14,
            COLORS["ink"],
        )
        y += 78
    return image


def slide_shadow(metrics: dict[str, object]) -> Image.Image:
    image, draw = base_frame(
        3,
        "Shadow AI",
        "Unsanctioned tool activity and unmanaged user exposure",
    )
    by_tool = metrics["by_tool"]
    by_tier = metrics["by_tier"]
    assert isinstance(by_tool, Counter)
    assert isinstance(by_tier, Counter)
    sanctioned = {"Microsoft 365 Copilot", "GitHub Copilot"}
    conditional = {"ChatGPT"}
    unmanaged_tools = [
        (label, value)
        for label, value in by_tool.most_common()
        if label not in sanctioned | conditional
    ]
    draw_kpis(
        draw,
        [
            (
                "Unmanaged users",
                str(metrics["unmanaged_users"]),
                COLORS["red"],
            ),
            (
                "Share of AI users",
                f"{metrics['unmanaged_share']:.1f}%",
                COLORS["orange"],
            ),
            (
                "Unsanctioned sessions",
                short_number(by_tier["Unsanctioned"]),
                COLORS["violet"],
            ),
            ("Observed tools", str(len(by_tool)), COLORS["blue"]),
        ],
    )
    draw_bar_chart(
        draw,
        (CONTENT_LEFT, 232, 840, 654),
        "Top unsanctioned tools by sessions",
        unmanaged_tools[:6],
        [
            COLORS["red"],
            COLORS["orange"],
            COLORS["violet"],
            COLORS["purple"],
            COLORS["teal"],
            COLORS["blue"],
        ],
    )
    rounded_card(draw, (860, 232, CONTENT_RIGHT, 654), COLORS["pale_red"])
    draw.text(
        (885, 256),
        "Governance workflow",
        font=FONT_20_BOLD,
        fill=COLORS["red"],
    )
    steps = [
        ("1", "Validate", "Confirm the activity and business purpose."),
        ("2", "Classify", "Review the tool, account type, and data handling."),
        ("3", "Respond", "Sanction, restrict, educate, or investigate."),
    ]
    y = 310
    for number, heading, body in steps:
        draw.ellipse((885, y, 925, y + 40), fill=COLORS["red"])
        draw.text(
            (899, y + 8),
            number,
            font=FONT_16_BOLD,
            fill=COLORS["white"],
        )
        draw.text(
            (945, y - 2),
            heading,
            font=FONT_16_BOLD,
            fill=COLORS["ink"],
        )
        draw_wrapped(
            draw,
            body,
            (945, y + 25, 1225, y + 80),
            FONT_13,
            COLORS["muted"],
        )
        y += 102
    return image


def slide_heatmap(metrics: dict[str, object]) -> Image.Image:
    image, draw = base_frame(
        4,
        "Department Intensity by Solution",
        "Where synthetic AI activity concentrates across departments and tools",
    )
    rounded_card(draw, (CONTENT_LEFT, 112, CONTENT_RIGHT, 654))
    draw.text(
        (CONTENT_LEFT + 20, 130),
        "Session intensity heatmap",
        font=FONT_18_BOLD,
        fill=COLORS["ink"],
    )
    draw.text(
        (CONTENT_LEFT + 20, 155),
        "Darker cells represent higher session volume",
        font=FONT_12,
        fill=COLORS["muted"],
    )

    departments = [
        "Engineering",
        "Finance",
        "HR",
        "IT",
        "Legal",
        "Marketing",
        "Operations",
        "Sales",
    ]
    solutions = [
        ("M365", "Microsoft 365 Copilot"),
        ("GitHub", "GitHub Copilot"),
        ("Gemini", "Gemini"),
        ("Claude", "Claude"),
        ("ChatGPT", "ChatGPT"),
        ("DeepSeek", "DeepSeek"),
        ("Midjourney", "Midjourney"),
        ("Perplexity", "Perplexity"),
    ]
    heat = metrics["heat"]
    assert isinstance(heat, Counter)
    max_value = max(heat.values()) or 1
    grid_left = CONTENT_LEFT + 130
    grid_top = 210
    cell_width = 103
    cell_height = 48
    for col, (short, _) in enumerate(solutions):
        label_width = draw.textbbox((0, 0), short, font=FONT_12)[2]
        draw.text(
            (
                grid_left + col * cell_width + (cell_width - label_width) // 2,
                grid_top - 27,
            ),
            short,
            font=FONT_12,
            fill=COLORS["muted"],
        )
    for row_index, department in enumerate(departments):
        y = grid_top + row_index * cell_height
        draw.text(
            (CONTENT_LEFT + 20, y + 13),
            department,
            font=FONT_13,
            fill=COLORS["ink"],
        )
        for col, (_, solution) in enumerate(solutions):
            value = heat[(department, solution)]
            intensity = value / max_value
            light = (238, 233, 248)
            dark = (75, 45, 131)
            color = tuple(
                int(light[channel] * (1 - intensity) + dark[channel] * intensity)
                for channel in range(3)
            )
            x = grid_left + col * cell_width
            draw.rounded_rectangle(
                (x + 3, y + 3, x + cell_width - 3, y + cell_height - 3),
                radius=6,
                fill=color,
            )
            if value:
                value_text = short_number(value)
                text_width = draw.textbbox(
                    (0, 0), value_text, font=FONT_12
                )[2]
                draw.text(
                    (
                        x + (cell_width - text_width) // 2,
                        y + 15,
                    ),
                    value_text,
                    font=FONT_12,
                    fill=COLORS["white"]
                    if intensity > 0.42
                    else COLORS["purple_dark"],
                )
    return image


def slide_departments(metrics: dict[str, object]) -> Image.Image:
    image, draw = base_frame(
        5,
        "Department Breakdown",
        "Compare adoption volume and investigate differences in usage patterns",
    )
    by_department = metrics["by_department"]
    assert isinstance(by_department, Counter)
    department_count = len(by_department)
    average_sessions = int(metrics["total_sessions"]) / department_count
    draw_kpis(
        draw,
        [
            ("Departments", str(department_count), COLORS["blue"]),
            (
                "Total sessions",
                short_number(float(metrics["total_sessions"])),
                COLORS["violet"],
            ),
            (
                "Average per dept",
                short_number(average_sessions),
                COLORS["teal"],
            ),
            (
                "Active AI users",
                str(metrics["ai_users"]),
                COLORS["green"],
            ),
        ],
    )
    draw_bar_chart(
        draw,
        (CONTENT_LEFT, 232, 870, 654),
        "Sessions by department",
        by_department.most_common(),
        [
            COLORS["purple"],
            COLORS["violet"],
            COLORS["blue"],
            COLORS["teal"],
        ],
        label_width=110,
    )
    rounded_card(draw, (890, 232, CONTENT_RIGHT, 654))
    draw.text(
        (915, 256),
        "How to use this page",
        font=FONT_20_BOLD,
        fill=COLORS["purple"],
    )
    draw_wrapped(
        draw,
        "Use department differences to find enablement opportunities, "
        "unexpected tool concentrations, and teams that need governance support.",
        (915, 305, 1225, 430),
        FONT_16,
        COLORS["ink"],
        spacing=8,
    )
    draw.rounded_rectangle(
        (915, 465, 1225, 590),
        radius=10,
        fill=COLORS["lavender"],
    )
    draw.text(
        (935, 487),
        "Sample insight",
        font=FONT_14_BOLD,
        fill=COLORS["purple"],
    )
    draw_wrapped(
        draw,
        "HR and Legal are intentionally overrepresented so the preview "
        "demonstrates visible contrast. This is not a real benchmark.",
        (935, 520, 1205, 585),
        FONT_13,
        COLORS["muted"],
    )
    return image


def slide_catalog(metrics: dict[str, object]) -> Image.Image:
    image, draw = base_frame(
        6,
        "Shadow AI Catalog (MDA)",
        "Cloud Discovery domains, traffic indicators, and sanction status",
    )
    draw_kpis(
        draw,
        [
            ("Observed domains", str(metrics["cloud_domains"]), COLORS["blue"]),
            (
                "Unsanctioned domains",
                str(metrics["unsanctioned_domains"]),
                COLORS["red"],
            ),
            (
                "MDA policy events",
                short_number(float(metrics["mda_events"])),
                COLORS["violet"],
            ),
            (
                "AppGov alerts",
                str(metrics["appgov_alerts"]),
                COLORS["orange"],
            ),
        ],
    )
    by_domain = metrics["by_domain"]
    assert isinstance(by_domain, Counter)
    draw_bar_chart(
        draw,
        (CONTENT_LEFT, 232, 860, 654),
        "Cloud Discovery transactions by domain",
        by_domain.most_common(),
        [
            COLORS["red"],
            COLORS["orange"],
            COLORS["violet"],
            COLORS["purple"],
            COLORS["blue"],
        ],
        label_width=150,
    )
    rounded_card(draw, (880, 232, CONTENT_RIGHT, 654), COLORS["pale_blue"])
    draw.text(
        (905, 256),
        "MDA coverage",
        font=FONT_20_BOLD,
        fill=COLORS["blue"],
    )
    draw_wrapped(
        draw,
        "This page uses synthetic Defender for Cloud Apps records. "
        "In a tenant without MDA, the report displays an availability callout "
        "instead of these visuals.",
        (905, 305, 1220, 430),
        FONT_14,
        COLORS["ink"],
        spacing=8,
    )
    draw.text(
        (905, 480),
        "Typical next steps",
        font=FONT_14_BOLD,
        fill=COLORS["blue"],
    )
    draw.text(
        (905, 515),
        "Review risk score\nConfirm sanction status\nInspect traffic volume\nAssign an owner",
        font=FONT_14,
        fill=COLORS["muted"],
        spacing=12,
    )
    return image


def draw_benchmark_row(
    draw: ImageDraw.ImageDraw,
    y: int,
    label: str,
    actual: float,
    target: float,
    lower_is_better: bool = False,
) -> None:
    x1 = CONTENT_LEFT + 30
    x2 = CONTENT_RIGHT - 30
    draw.text((x1, y), label, font=FONT_16_BOLD, fill=COLORS["ink"])
    actual_text = f"{actual:.1f}%"
    text_width = draw.textbbox((0, 0), actual_text, font=FONT_16_BOLD)[2]
    draw.text(
        (x2 - text_width, y),
        actual_text,
        font=FONT_16_BOLD,
        fill=COLORS["ink"],
    )
    bar_top = y + 34
    bar_left = x1
    bar_right = x2
    draw.rounded_rectangle(
        (bar_left, bar_top, bar_right, bar_top + 24),
        radius=8,
        fill="#E8EAF0",
    )
    actual_right = bar_left + int((bar_right - bar_left) * min(actual, 100) / 100)
    meets = actual <= target if lower_is_better else actual >= target
    actual_color = COLORS["green"] if meets else COLORS["orange"]
    draw.rounded_rectangle(
        (bar_left, bar_top, max(bar_left + 8, actual_right), bar_top + 24),
        radius=8,
        fill=actual_color,
    )
    target_x = bar_left + int((bar_right - bar_left) * min(target, 100) / 100)
    draw.line(
        (target_x, bar_top - 7, target_x, bar_top + 31),
        fill=COLORS["purple_dark"],
        width=3,
    )
    status = "ON TARGET" if meets else "REVIEW"
    status_color = COLORS["green"] if meets else COLORS["orange"]
    draw.text(
        (x1, y + 66),
        f"Illustrative target: {target:.0f}%",
        font=FONT_12,
        fill=COLORS["muted"],
    )
    status_width = draw.textbbox((0, 0), status, font=FONT_12)[2]
    draw.text(
        (x2 - status_width, y + 66),
        status,
        font=FONT_12,
        fill=status_color,
    )


def slide_benchmarks(metrics: dict[str, object]) -> Image.Image:
    image, draw = base_frame(
        7,
        "Benchmarks & Targets",
        "Illustrative what-if targets applied to the synthetic dataset",
    )
    rounded_card(draw, (CONTENT_LEFT, 112, CONTENT_RIGHT, 654))
    draw.text(
        (CONTENT_LEFT + 30, 132),
        "Sample scorecard",
        font=FONT_20_BOLD,
        fill=COLORS["ink"],
    )
    draw.text(
        (CONTENT_LEFT + 30, 160),
        "Targets are examples only and should be configured for your organization.",
        font=FONT_13,
        fill=COLORS["muted"],
    )
    draw_benchmark_row(
        draw, 205, "Workforce AI adoption", float(metrics["adoption"]), 80
    )
    draw_benchmark_row(
        draw,
        310,
        "Copilot license utilization",
        float(metrics["license_utilization"]),
        85,
    )
    draw_benchmark_row(
        draw,
        415,
        "Users on unmanaged AI",
        float(metrics["unmanaged_share"]),
        25,
        lower_is_better=True,
    )
    draw_benchmark_row(
        draw,
        520,
        "Off-hours activity share",
        float(metrics["offhours_pct"]),
        20,
        lower_is_better=True,
    )
    return image


def slide_glossary(metrics: dict[str, object]) -> Image.Image:
    del metrics
    image, draw = base_frame(
        8,
        "Glossary & Data Dictionary",
        "Plain-language definitions for adoption, activity, and risk signals",
    )
    cards = [
        (
            "Workforce adoption",
            "Unique users with observed AI activity divided by total Entra users.",
            COLORS["pale_blue"],
            COLORS["blue"],
        ),
        (
            "Unmanaged AI",
            "Activity mapped to solutions classified as unsanctioned in the catalog.",
            COLORS["pale_red"],
            COLORS["red"],
        ),
        (
            "File proximity",
            "A file event occurring within five minutes of an AI event; correlation only.",
            COLORS["lavender"],
            COLORS["purple"],
        ),
        (
            "AI risk score",
            "A weighted prioritization signal combining available behavioral indicators.",
            COLORS["pale_orange"],
            COLORS["orange"],
        ),
    ]
    positions = [
        (CONTENT_LEFT, 125, 740, 365),
        (760, 125, CONTENT_RIGHT, 365),
        (CONTENT_LEFT, 385, 740, 625),
        (760, 385, CONTENT_RIGHT, 625),
    ]
    for (title, body, fill, accent), box in zip(cards, positions):
        rounded_card(draw, box, fill=fill)
        x1, y1, x2, _ = box
        draw.ellipse((x1 + 25, y1 + 28, x1 + 57, y1 + 60), fill=accent)
        draw.text(
            (x1 + 75, y1 + 25),
            title,
            font=FONT_20_BOLD,
            fill=COLORS["ink"],
        )
        draw_wrapped(
            draw,
            body,
            (x1 + 25, y1 + 90, x2 - 25, y1 + 190),
            FONT_16,
            COLORS["muted"],
            spacing=8,
        )
        draw.text(
            (x1 + 25, y1 + 200),
            "Use as context, then validate against source evidence.",
            font=FONT_12,
            fill=accent,
        )
    return image


def slide_tiers(metrics: dict[str, object]) -> Image.Image:
    del metrics
    image, draw = base_frame(
        9,
        "Tier Comparison",
        "The same template expands as more data sources become available",
    )
    rounded_card(draw, (CONTENT_LEFT, 112, CONTENT_RIGHT, 654))
    x1 = CONTENT_LEFT + 20
    x2 = CONTENT_RIGHT - 20
    table_top = 145
    columns = [x1, 610, 825, 1035, x2]
    headers = ["Report page", "E3 + Copilot", "E5 / MDE P2", "MDA"]
    for col in range(4):
        draw.rectangle(
            (
                columns[col],
                table_top,
                columns[col + 1],
                table_top + 44,
            ),
            fill=COLORS["purple"],
        )
        header_width = draw.textbbox(
            (0, 0), headers[col], font=FONT_13_BOLD
        )[2]
        draw.text(
            (
                columns[col]
                + (columns[col + 1] - columns[col] - header_width) // 2,
                table_top + 13,
            ),
            headers[col],
            font=FONT_13_BOLD,
            fill=COLORS["white"],
        )

    rows = [
        ("Executive Summary", "CORE", "ENRICHED", "ENRICHED"),
        ("Copilot Deep Dive", "CORE", "CORE", "CORE"),
        ("Behavioral Risk", "BASIC", "CORE", "ENRICHED"),
        ("Shadow AI", "-", "CORE", "ENRICHED"),
        ("Dept Intensity", "CORE", "CORE", "CORE"),
        ("Department Breakdown", "CORE", "CORE", "CORE"),
        ("Shadow AI Catalog", "-", "-", "CORE"),
        ("Benchmarks & Targets", "CORE", "CORE", "CORE"),
        ("Glossary", "CORE", "CORE", "CORE"),
        ("Tier Comparison", "CORE", "CORE", "CORE"),
    ]
    state_colors = {
        "CORE": (COLORS["pale_green"], COLORS["green"]),
        "ENRICHED": (COLORS["pale_blue"], COLORS["blue"]),
        "BASIC": (COLORS["pale_orange"], COLORS["orange"]),
        "-": ("#F0F1F4", COLORS["muted"]),
    }
    row_height = 42
    for row_index, row in enumerate(rows):
        y = table_top + 44 + row_index * row_height
        fill = COLORS["white"] if row_index % 2 == 0 else "#F8F9FC"
        draw.rectangle((x1, y, x2, y + row_height), fill=fill)
        draw.text(
            (columns[0] + 16, y + 12),
            row[0],
            font=FONT_13,
            fill=COLORS["ink"],
        )
        for col in range(1, 4):
            state = row[col]
            state_fill, state_text = state_colors[state]
            pill_width = 92
            center = (columns[col] + columns[col + 1]) // 2
            draw.rounded_rectangle(
                (
                    center - pill_width // 2,
                    y + 8,
                    center + pill_width // 2,
                    y + 33,
                ),
                radius=12,
                fill=state_fill,
            )
            text_width = draw.textbbox(
                (0, 0), state, font=FONT_11
            )[2]
            draw.text(
                (center - text_width // 2, y + 13),
                state,
                font=FONT_11,
                fill=state_text,
            )
        draw.line((x1, y + row_height, x2, y + row_height), fill=COLORS["line"])
    return image


def build_frames(metrics: dict[str, object]) -> list[Image.Image]:
    builders = [
        slide_executive,
        slide_copilot,
        slide_risk,
        slide_shadow,
        slide_heatmap,
        slide_departments,
        slide_catalog,
        slide_benchmarks,
        slide_glossary,
        slide_tiers,
    ]
    return [builder(metrics) for builder in builders]


def save_gif(frames: list[Image.Image]) -> None:
    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    adaptive_palette = getattr(Image, "Palette", Image).ADAPTIVE
    converted = [
        frame.convert("P", palette=adaptive_palette, colors=128)
        for frame in frames
    ]
    converted[0].save(
        OUTPUT_PATH,
        save_all=True,
        append_images=converted[1:],
        duration=2600,
        loop=0,
        optimize=True,
        disposal=2,
    )


def main() -> None:
    validate_sample_source()
    metrics = build_metrics()
    frames = build_frames(metrics)
    save_gif(frames)
    print(f"Created {OUTPUT_PATH}")
    print(f"Frames: {len(frames)}")
    print("Privacy guard: PASS (sample_data_v26 only; contoso.com user domain)")


if __name__ == "__main__":
    main()
