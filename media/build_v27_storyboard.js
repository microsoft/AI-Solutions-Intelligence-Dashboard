const pptxgen = require("pptxgenjs");
const path = require("path");

const deck = new pptxgen();
deck.layout = "LAYOUT_WIDE";
deck.author = "Microsoft Scout";
deck.company = "Microsoft";
deck.subject = "AI Solutions Intelligence Dashboard V27 interpretation storyboard";
deck.title = "AI Solutions Intelligence Dashboard V27 In Testing - Interpretation Storyboard";
deck.lang = "en-US";
deck.theme = {
  headFontFace: "Aptos Display",
  bodyFontFace: "Aptos",
  lang: "en-US",
};
deck.defineSlideMaster({
  title: "CONTENT",
  background: { color: "FFFFFF" },
  objects: [
    {
      rect: {
        x: 0,
        y: 0,
        w: 13.333,
        h: 0.18,
        fill: { color: "4B2D83" },
        line: { color: "4B2D83" },
      },
    },
  ],
  slideNumber: {
    x: 12.58,
    y: 7.19,
    w: 0.35,
    h: 0.16,
    fontFace: "Aptos",
    fontSize: 7,
    color: "726A7C",
    align: "right",
    margin: 0,
  },
});

const repoRoot = path.resolve(__dirname, "..");
const output = path.join(
  repoRoot,
  "AI-Solutions-Intelligence-Dashboard V27 In Testing - Interpretation Storyboard.pptx",
);
const images = path.join(repoRoot, "images", "v27-report-pages");

const C = {
  purple: "4B2D83",
  purpleDark: "2B174D",
  violet: "7551A8",
  magenta: "E63B93",
  teal: "00A9A5",
  green: "67A83D",
  blue: "0078D4",
  amber: "F2B134",
  ink: "202033",
  muted: "625B6A",
  line: "D8CEE8",
  pale: "F7F5FA",
  palePurple: "F0EBF7",
  paleTeal: "EAF8F7",
  white: "FFFFFF",
  black: "000000",
};

const pageImages = [
  "01-executive-summary.png",
  "02-copilot-deep-dive.png",
  "03-behavioral-risk.png",
  "04-shadow-ai.png",
  "05-dept-intensity.png",
  "06-department-breakdown.png",
  "07-shadow-ai-catalog.png",
  "08-benchmarks-targets.png",
  "09-glossary-data-dictionary.png",
  "10-tier-comparison.png",
].map((name) => path.join(images, name));

function addFooter(slide, label = "V27 In Testing | Fabricated sample data") {
  slide.addText("github.com/microsoft/AI-Solutions-Intelligence-Dashboard", {
    x: 0.42,
    y: 7.18,
    w: 5.7,
    h: 0.16,
    fontFace: "Aptos",
    fontSize: 6.8,
    color: C.muted,
    margin: 0,
  });
  slide.addText(label, {
    x: 7.35,
    y: 7.18,
    w: 5.0,
    h: 0.16,
    fontFace: "Aptos",
    fontSize: 6.8,
    color: C.muted,
    align: "right",
    margin: 0,
  });
}

function addSectionTitle(slide, title, subtitle) {
  slide.addText(title, {
    x: 0.48,
    y: 0.32,
    w: 8.7,
    h: 0.42,
    fontFace: "Aptos Display",
    fontSize: 24,
    bold: true,
    color: C.purpleDark,
    margin: 0,
  });
  if (subtitle) {
    slide.addText(subtitle, {
      x: 9.2,
      y: 0.42,
      w: 3.62,
      h: 0.22,
      fontFace: "Aptos",
      fontSize: 8,
      color: C.muted,
      align: "right",
      margin: 0,
    });
  }
  slide.addShape(deck.ShapeType.line, {
    x: 0.48,
    y: 0.79,
    w: 12.36,
    h: 0,
    line: { color: C.line, width: 1 },
  });
}

function addPill(slide, text, x, y, w, fill, color = C.white) {
  slide.addShape(deck.ShapeType.roundRect, {
    x,
    y,
    w,
    h: 0.32,
    rectRadius: 0.08,
    fill: { color: fill },
    line: { color: fill },
  });
  slide.addText(text, {
    x: x + 0.06,
    y: y + 0.075,
    w: w - 0.12,
    h: 0.12,
    fontFace: "Aptos",
    fontSize: 8,
    bold: true,
    color,
    align: "center",
    margin: 0,
  });
}

function addNumber(slide, number, x, y, color = C.green) {
  slide.addShape(deck.ShapeType.ellipse, {
    x,
    y,
    w: 0.32,
    h: 0.32,
    fill: { color },
    line: { color },
  });
  slide.addText(String(number), {
    x,
    y: y + 0.035,
    w: 0.32,
    h: 0.13,
    fontFace: "Aptos",
    fontSize: 8,
    bold: true,
    color: C.white,
    align: "center",
    margin: 0,
  });
}

function addCallout(slide, callout, x, y, w, h) {
  slide.addShape(deck.ShapeType.roundRect, {
    x,
    y,
    w,
    h,
    rectRadius: 0.08,
    fill: { color: C.white },
    line: { color: C.line, width: 1.2 },
  });
  addNumber(slide, callout.number, x + 0.13, y + 0.13, callout.color || C.green);
  slide.addText(callout.question, {
    x: x + 0.55,
    y: y + 0.12,
    w: w - 0.7,
    h: 0.31,
    fontFace: "Aptos",
    fontSize: 10.5,
    bold: true,
    color: C.ink,
    margin: 0,
    fit: "shrink",
  });
  slide.addText("INTERPRETATION", {
    x: x + 0.15,
    y: y + 0.51,
    w: 1.02,
    h: 0.13,
    fontFace: "Aptos",
    fontSize: 6.5,
    bold: true,
    color: C.purple,
    margin: 0,
  });
  slide.addText(callout.interpretation, {
    x: x + 1.18,
    y: y + 0.48,
    w: w - 1.34,
    h: h >= 2 ? 0.58 : 0.43,
    fontFace: "Aptos",
    fontSize: 8.2,
    color: C.ink,
    margin: 0,
    breakLine: false,
    fit: "shrink",
    valign: "top",
  });
  slide.addText(callout.actionLabel || "ACTION", {
    x: x + 0.15,
    y: y + (h >= 2 ? 1.28 : 1.08),
    w: 1.02,
    h: 0.13,
    fontFace: "Aptos",
    fontSize: 6.5,
    bold: true,
    color: C.teal,
    margin: 0,
  });
  slide.addText(callout.action, {
    x: x + 1.18,
    y: y + (h >= 2 ? 1.24 : 1.04),
    w: w - 1.34,
    h: h >= 2 ? 0.65 : 0.42,
    fontFace: "Aptos",
    fontSize: 8.2,
    color: C.ink,
    margin: 0,
    fit: "shrink",
    valign: "top",
  });
}

function addImageFrame(slide, imagePath, x, y, w, h) {
  const sourceAspect = 2150 / 1178;
  const targetAspect = w / h;
  const imageW = targetAspect > sourceAspect ? h * sourceAspect : w;
  const imageH = targetAspect > sourceAspect ? h : w / sourceAspect;
  const imageX = x + (w - imageW) / 2;
  const imageY = y + (h - imageH) / 2;

  slide.addShape(deck.ShapeType.roundRect, {
    x: imageX - 0.05,
    y: imageY - 0.05,
    w: imageW + 0.1,
    h: imageH + 0.1,
    rectRadius: 0.04,
    fill: { color: C.palePurple },
    line: { color: C.violet, width: 1.1 },
  });
  slide.addImage({ path: imagePath, x: imageX, y: imageY, w: imageW, h: imageH });
  slide.addText("Actual V27 Power BI capture - fabricated sample data", {
    x: imageX,
    y: imageY + imageH + 0.07,
    w: imageW,
    h: 0.13,
    fontFace: "Aptos",
    fontSize: 6.2,
    italic: true,
    color: C.muted,
    align: "right",
    margin: 0,
  });
}

function addDetailSlide(page) {
  const slide = deck.addSlide("CONTENT");
  addSectionTitle(slide, page.title, page.subtitle);
  addCallout(slide, page.callouts[0], 0.48, 1.02, 5.98, 1.62);
  addCallout(slide, page.callouts[1], 0.48, 2.82, 5.98, 1.62);
  addImageFrame(slide, page.image, 6.76, 1.0, 5.96, 3.35);
  addCallout(slide, page.callouts[2], 0.48, 4.72, 5.98, 2.18);
  addCallout(slide, page.callouts[3], 6.76, 4.72, 5.96, 2.18);
  addFooter(slide);
}

function addInfoCard(slide, options) {
  const { x, y, w, h, number, title, body, accent = C.purple, fill = C.pale } = options;
  slide.addShape(deck.ShapeType.roundRect, {
    x,
    y,
    w,
    h,
    rectRadius: 0.08,
    fill: { color: fill },
    line: { color: "E2DDE8", width: 0.8 },
  });
  if (number !== undefined) {
    addNumber(slide, number, x + 0.18, y + 0.18, accent);
  }
  slide.addText(title, {
    x: x + (number !== undefined ? 0.62 : 0.2),
    y: y + 0.16,
    w: w - (number !== undefined ? 0.8 : 0.4),
    h: 0.3,
    fontFace: "Aptos",
    fontSize: 12,
    bold: true,
    color: C.ink,
    margin: 0,
    fit: "shrink",
  });
  slide.addText(body, {
    x: x + 0.2,
    y: y + 0.58,
    w: w - 0.4,
    h: h - 0.76,
    fontFace: "Aptos",
    fontSize: 9.5,
    color: C.muted,
    margin: 0,
    fit: "shrink",
    valign: "top",
  });
}

function addTermCard(slide, x, y, w, term, definition, accent) {
  slide.addShape(deck.ShapeType.roundRect, {
    x,
    y,
    w,
    h: 1.42,
    rectRadius: 0.07,
    fill: { color: C.white },
    line: { color: C.line, width: 0.9 },
  });
  slide.addShape(deck.ShapeType.rect, {
    x,
    y,
    w: 0.1,
    h: 1.42,
    fill: { color: accent },
    line: { color: accent },
  });
  slide.addText(term, {
    x: x + 0.25,
    y: y + 0.18,
    w: w - 0.45,
    h: 0.26,
    fontFace: "Aptos",
    fontSize: 11,
    bold: true,
    color: C.purpleDark,
    margin: 0,
  });
  slide.addText(definition, {
    x: x + 0.25,
    y: y + 0.52,
    w: w - 0.45,
    h: 0.7,
    fontFace: "Aptos",
    fontSize: 8.6,
    color: C.muted,
    margin: 0,
    fit: "shrink",
  });
}

// Slide 1 - cover
{
  const slide = deck.addSlide();
  slide.background = { color: C.pale };
  slide.addShape(deck.ShapeType.rect, {
    x: 0,
    y: 0,
    w: 6.45,
    h: 7.5,
    fill: { color: C.purpleDark },
    line: { color: C.purpleDark },
  });
  slide.addShape(deck.ShapeType.arc, {
    x: 9.2,
    y: -0.7,
    w: 4.8,
    h: 4.8,
    adjustPoint: 0.35,
    rotate: 25,
    fill: { color: C.magenta, transparency: 34 },
    line: { color: C.magenta, transparency: 100 },
  });
  slide.addShape(deck.ShapeType.arc, {
    x: 10.6,
    y: 6.1,
    w: 4.2,
    h: 4.2,
    rotate: 215,
    fill: { color: C.teal, transparency: 24 },
    line: { color: C.teal, transparency: 100 },
  });
  addPill(slide, "V27 IN TESTING", 0.72, 0.66, 1.62, C.amber, C.purpleDark);
  slide.addText("AI Solutions\nIntelligence Dashboard", {
    x: 0.72,
    y: 1.36,
    w: 5.1,
    h: 1.55,
    fontFace: "Aptos Display",
    fontSize: 30,
    bold: true,
    color: C.white,
    margin: 0,
    breakLine: false,
  });
  slide.addText("Interpretation Storyboard", {
    x: 0.72,
    y: 3.1,
    w: 4.9,
    h: 0.55,
    fontFace: "Aptos Display",
    fontSize: 22,
    bold: true,
    color: "D9C9F3",
    margin: 0,
  });
  slide.addText(
    "A page-by-page guide to the questions each visual answers, what the signals may mean, and what to verify before acting.",
    {
      x: 0.72,
      y: 3.86,
      w: 4.9,
      h: 0.85,
      fontFace: "Aptos",
      fontSize: 13,
      color: C.white,
      margin: 0,
      fit: "shrink",
    },
  );
  slide.addText("Get the template and documentation at", {
    x: 0.72,
    y: 5.37,
    w: 3.9,
    h: 0.22,
    fontFace: "Aptos",
    fontSize: 9,
    color: "C9BED8",
    margin: 0,
  });
  slide.addText("github.com/microsoft/AI-Solutions-Intelligence-Dashboard", {
    x: 0.72,
    y: 5.68,
    w: 4.95,
    h: 0.28,
    fontFace: "Aptos",
    fontSize: 10,
    bold: true,
    color: C.white,
    margin: 0,
  });
  addImageFrame(slide, pageImages[0], 6.9, 1.45, 5.75, 3.23);
  slide.addText(
    "All figures shown use deterministic fabricated sample data. This experimental template is an analysis aid, not a sole source of truth for licensing, security, privacy, legal, compliance, personnel, or procurement decisions.",
    {
      x: 6.95,
      y: 5.34,
      w: 5.65,
      h: 0.9,
      fontFace: "Aptos",
      fontSize: 8.8,
      color: C.ink,
      margin: 0,
      fit: "shrink",
    },
  );
  slide.addText("Last updated September 5, 2026", {
    x: 6.95,
    y: 6.5,
    w: 5.65,
    h: 0.2,
    fontFace: "Aptos",
    fontSize: 7.5,
    color: C.muted,
    align: "right",
    margin: 0,
  });
}

// Slide 2 - key questions
{
  const slide = deck.addSlide("CONTENT");
  addSectionTitle(slide, "The four questions that matter", "Start here before opening a detail page");
  addInfoCard(slide, {
    x: 0.62,
    y: 1.12,
    w: 5.9,
    h: 2.38,
    number: 1,
    title: "ADOPTION - Who is using AI, and how broadly?",
    body: "Use active users, workforce adoption, department reach, and weekly activity together. Volume without population context can overstate broad adoption.",
    accent: C.purple,
    fill: C.palePurple,
  });
  addInfoCard(slide, {
    x: 6.8,
    y: 1.12,
    w: 5.9,
    h: 2.38,
    number: 2,
    title: "COPILOT VALUE - Which surfaces are gaining traction?",
    body: "Compare licensed users with observed activity by surface and department. Audit-derived prompt metrics are directional and can differ from official usage reports.",
    accent: C.blue,
    fill: "EEF5FC",
  });
  addInfoCard(slide, {
    x: 0.62,
    y: 3.8,
    w: 5.9,
    h: 2.38,
    number: 3,
    title: "GOVERNANCE - Which signals warrant review?",
    body: "Use shadow-tool classifications, consent risk, geo patterns, and file proximity to prioritize investigation. None of these signals proves misuse or data disclosure.",
    accent: C.magenta,
    fill: "FCEEF6",
  });
  addInfoCard(slide, {
    x: 6.8,
    y: 3.8,
    w: 5.9,
    h: 2.38,
    number: 4,
    title: "COVERAGE - What can the available sources support?",
    body: "Confirm licenses, onboarding, connectors, permissions, retention, and reporting period before interpreting blanks or comparing values across pages.",
    accent: C.teal,
    fill: C.paleTeal,
  });
  slide.addText(
    "Read adoption and governance indicators frequently; revisit locally defined targets and source coverage on a scheduled review cadence.",
    {
      x: 0.72,
      y: 6.51,
      w: 11.9,
      h: 0.28,
      fontFace: "Aptos",
      fontSize: 10,
      italic: true,
      color: C.muted,
      align: "center",
      margin: 0,
    },
  );
  addFooter(slide);
}

// Slide 3 - introduction
{
  const slide = deck.addSlide("CONTENT");
  addSectionTitle(slide, "Introduction", "What this storyboard is designed to do");
  slide.addShape(deck.ShapeType.roundRect, {
    x: 0.58,
    y: 1.08,
    w: 6.0,
    h: 5.62,
    rectRadius: 0.09,
    fill: { color: C.pale },
    line: { color: "E4DEE9", width: 0.8 },
  });
  slide.addText(
    "This guide walks through the AI Solutions Intelligence Dashboard page by page. Every dashboard page is paired with four business questions, a careful interpretation, and a concrete next action.",
    {
      x: 0.88,
      y: 1.42,
      w: 5.4,
      h: 1.0,
      fontFace: "Aptos",
      fontSize: 14,
      color: C.ink,
      margin: 0,
      fit: "shrink",
    },
  );
  slide.addText("Detailed page interpretation", {
    x: 0.88,
    y: 2.74,
    w: 5.2,
    h: 0.3,
    fontFace: "Aptos Display",
    fontSize: 16,
    bold: true,
    color: C.purple,
    margin: 0,
  });
  slide.addText(
    "Follow callouts 1 through 4 to read each page in a consistent order. Begin with the question, use the interpretation to understand the limits of the metric, then complete the action before making a decision.",
    {
      x: 0.88,
      y: 3.17,
      w: 5.35,
      h: 1.02,
      fontFace: "Aptos",
      fontSize: 11,
      color: C.muted,
      margin: 0,
      fit: "shrink",
    },
  );
  slide.addText("Before quoting any value", {
    x: 0.88,
    y: 4.53,
    w: 5.2,
    h: 0.3,
    fontFace: "Aptos Display",
    fontSize: 16,
    bold: true,
    color: C.teal,
    margin: 0,
  });
  slide.addText(
    "Check the active filters, reporting period, source coverage, confidence label, and denominator. Protect exports because they can contain user identifiers and other sensitive operational data.",
    {
      x: 0.88,
      y: 4.95,
      w: 5.35,
      h: 1.08,
      fontFace: "Aptos",
      fontSize: 11,
      color: C.muted,
      margin: 0,
      fit: "shrink",
    },
  );
  addImageFrame(slide, pageImages[8], 7.0, 1.17, 5.42, 3.05);
  addImageFrame(slide, pageImages[9], 7.62, 4.51, 4.18, 2.35);
  addFooter(slide);
}

// Slide 4 - evidence model
{
  const slide = deck.addSlide("CONTENT");
  addSectionTitle(slide, "Why an observed signal is not proof - and why that matters", "Different evidence requires different action");
  const steps = [
    {
      n: 1,
      title: "OBSERVE",
      body: "The report receives events, dimensions, and locally maintained catalog classifications from configured sources.",
      color: C.blue,
    },
    {
      n: 2,
      title: "INTERPRET",
      body: "Measures summarize, estimate, or combine those records. Some are exact; others are approximations or behavioral signals.",
      color: C.purple,
    },
    {
      n: 3,
      title: "VERIFY",
      body: "Source records, identity and device context, retention, connectors, and business purpose must be corroborated.",
      color: C.teal,
    },
    {
      n: 4,
      title: "ACT",
      body: "Use organizational incident, privacy, acceptable-use, licensing, procurement, and legal processes.",
      color: C.magenta,
    },
  ];
  steps.forEach((step, i) => {
    const x = 0.58 + i * 3.16;
    slide.addShape(deck.ShapeType.roundRect, {
      x,
      y: 1.28,
      w: 2.78,
      h: 3.5,
      rectRadius: 0.08,
      fill: { color: i % 2 === 0 ? C.pale : C.palePurple },
      line: { color: C.line, width: 1 },
    });
    addNumber(slide, step.n, x + 1.21, 1.62, step.color);
    slide.addText(step.title, {
      x: x + 0.3,
      y: 2.15,
      w: 2.18,
      h: 0.34,
      fontFace: "Aptos Display",
      fontSize: 17,
      bold: true,
      color: step.color,
      align: "center",
      margin: 0,
    });
    slide.addText(step.body, {
      x: x + 0.3,
      y: 2.75,
      w: 2.18,
      h: 1.38,
      fontFace: "Aptos",
      fontSize: 10,
      color: C.ink,
      align: "center",
      margin: 0,
      fit: "shrink",
      valign: "mid",
    });
    if (i < steps.length - 1) {
      slide.addShape(deck.ShapeType.chevron, {
        x: x + 2.81,
        y: 2.73,
        w: 0.31,
        h: 0.52,
        fill: { color: C.line },
        line: { color: C.line },
      });
    }
  });
  slide.addShape(deck.ShapeType.roundRect, {
    x: 0.72,
    y: 5.25,
    w: 11.9,
    h: 1.12,
    rectRadius: 0.06,
    fill: { color: "FFF4E5" },
    line: { color: "F4C57A", width: 1 },
  });
  slide.addText(
    "Examples: file proximity is timing correlation, not proof of upload; AI Upload MB is network volume, not content evidence; a high OAuth permission weight does not prove malicious intent; a catalog label does not independently establish a policy violation.",
    {
      x: 1.0,
      y: 5.57,
      w: 11.35,
      h: 0.5,
      fontFace: "Aptos",
      fontSize: 11,
      color: C.ink,
      margin: 0,
      align: "center",
      fit: "shrink",
    },
  );
  addFooter(slide);
}

// Slide 5 - reading order
{
  const slide = deck.addSlide("CONTENT");
  addSectionTitle(slide, "How to read this report", "Build the narrative from coverage to action");
  const readingOrder = [
    ["Tier Comparison", "Confirm which source systems and capabilities can populate."],
    ["Executive Summary", "Orient on adoption, tool mix, and monthly direction."],
    ["Copilot Deep Dive", "Understand Microsoft 365 Copilot surfaces and reach."],
    ["Department Views", "Separate broad adoption from concentrated intensity."],
    ["Shadow AI", "Review observed third-party tools and local classifications."],
    ["Behavioral Risk", "Prioritize cross-signal patterns for corroboration."],
    ["MDA Detail", "Add optional App Governance and Cloud Discovery evidence."],
    ["Benchmarks & Targets", "Compare observations with locally owned assumptions."],
    ["Glossary", "Confirm definition and confidence before sharing a metric."],
  ];
  readingOrder.forEach((item, i) => {
    const col = i < 5 ? 0 : 1;
    const row = col === 0 ? i : i - 5;
    const x = col === 0 ? 0.62 : 6.85;
    const y = 1.08 + row * 1.08;
    slide.addShape(deck.ShapeType.roundRect, {
      x,
      y,
      w: 5.86,
      h: 0.86,
      rectRadius: 0.06,
      fill: { color: i % 2 === 0 ? C.pale : C.white },
      line: { color: C.line, width: 0.8 },
    });
    addNumber(slide, i + 1, x + 0.18, y + 0.26, i >= 7 ? C.teal : C.purple);
    slide.addText(item[0], {
      x: x + 0.67,
      y: y + 0.14,
      w: 1.72,
      h: 0.23,
      fontFace: "Aptos",
      fontSize: 10.5,
      bold: true,
      color: C.ink,
      margin: 0,
      fit: "shrink",
    });
    slide.addText(item[1], {
      x: x + 2.35,
      y: y + 0.13,
      w: 3.23,
      h: 0.5,
      fontFace: "Aptos",
      fontSize: 8.5,
      color: C.muted,
      margin: 0,
      fit: "shrink",
      valign: "mid",
    });
  });
  slide.addText(
    "At every review ask: Is the trend sustained? Is activity broad or concentrated? Which source limitation could change the interpretation? What evidence is required before action?",
    {
      x: 6.98,
      y: 5.77,
      w: 5.45,
      h: 0.83,
      fontFace: "Aptos",
      fontSize: 10.5,
      bold: true,
      color: C.purpleDark,
      margin: 0,
      fit: "shrink",
      valign: "mid",
    },
  );
  addFooter(slide);
}

// Slide 6 - FAQ
{
  const slide = deck.addSlide("CONTENT");
  addSectionTitle(slide, "Frequently asked questions", "The answers to align on before a dashboard review");
  const faqs = [
    ["What is this dashboard?", "A Power BI template that combines source-dependent indicators for adoption, third-party AI activity, consent risk, off-hours and geo patterns, and optional MDA data."],
    ["Where does the data come from?", "From the 13-file CSV contract populated by Graph, Purview, Defender XDR, local catalog data, and optional Defender for Cloud Apps exports."],
    ["Why do my numbers look different?", "The slides use fabricated demo data. Tenant values depend on source coverage, filter context, reporting period, retention, identity mapping, and catalog choices."],
    ["How often should I review it?", "Review adoption and risk indicators on an agreed operating cadence. Review targets, ownership, and coverage whenever source or policy assumptions change."],
    ["What should I do when a signal looks concerning?", "Validate the original source record and business context. Follow established security, privacy, compliance, procurement, and personnel processes."],
  ];
  faqs.forEach((faq, i) => {
    const y = 1.03 + i * 1.13;
    slide.addShape(deck.ShapeType.roundRect, {
      x: 0.68,
      y,
      w: 11.98,
      h: 0.91,
      rectRadius: 0.06,
      fill: { color: i % 2 === 0 ? C.pale : C.white },
      line: { color: "E5E0EA", width: 0.7 },
    });
    slide.addShape(deck.ShapeType.ellipse, {
      x: 0.92,
      y: y + 0.25,
      w: 0.38,
      h: 0.38,
      fill: { color: i === 4 ? C.magenta : C.purple },
      line: { color: i === 4 ? C.magenta : C.purple },
    });
    slide.addText("Q", {
      x: 0.92,
      y: y + 0.295,
      w: 0.38,
      h: 0.14,
      fontFace: "Aptos",
      fontSize: 8.5,
      bold: true,
      color: C.white,
      align: "center",
      margin: 0,
    });
    slide.addText(faq[0], {
      x: 1.52,
      y: y + 0.16,
      w: 3.32,
      h: 0.26,
      fontFace: "Aptos",
      fontSize: 11,
      bold: true,
      color: C.purpleDark,
      margin: 0,
    });
    slide.addText(faq[1], {
      x: 4.72,
      y: y + 0.13,
      w: 7.55,
      h: 0.54,
      fontFace: "Aptos",
      fontSize: 8.9,
      color: C.ink,
      margin: 0,
      fit: "shrink",
      valign: "mid",
    });
  });
  addFooter(slide);
}

// Slides 7-8 - glossary
{
  const slide = deck.addSlide("CONTENT");
  addSectionTitle(slide, "Glossary", "Definitions to use when presenting the report");
  const terms = [
    ["AI Users", "Distinct users observed in any configured AI activity source. Limited by available telemetry and identity resolution."],
    ["Workforce Adoption %", "Observed AI users divided by the report workforce denominator. Denominator quality depends on EntraUsers.csv."],
    ["Copilot Adoption %", "Licensed users with observed Copilot activity divided by licensed users. Audit-derived and directional."],
    ["Active Days", "Distinct dates with observed activity. Source timestamp and timezone definitions can change the result."],
    ["Weekly Actions per User", "Observed actions normalized by active users and weeks. An average can hide concentration."],
    ["Non-Microsoft Activity", "Modeled activity for configured third-party AI tools. It is not an actual prompt count."],
  ];
  terms.forEach((term, i) => {
    const x = i % 2 === 0 ? 0.65 : 6.86;
    const y = 1.07 + Math.floor(i / 2) * 1.72;
    addTermCard(slide, x, y, 5.82, term[0], term[1], i % 2 === 0 ? C.purple : C.teal);
  });
  addFooter(slide);
}

{
  const slide = deck.addSlide("CONTENT");
  addSectionTitle(slide, "Glossary - continued", "Risk, coverage, and planning terms");
  const terms = [
    ["AI Risk Score", "A composite of configured behavioral signals. It is a triage score, not probability, proof, or severity."],
    ["Sensitive Proximity Event", "A selected file event shortly after an AI-domain connection. Correlation only; not proof of upload."],
    ["Geo Anomaly Event", "A country pattern meeting the model rule. VPN, travel, proxies, and routing can create false positives."],
    ["AI Upload MB", "Cloud Discovery network volume attributed to a domain. It does not identify content or prove exfiltration."],
    ["Gap vs Target", "Actual minus a locally configured target. The target is an organizational choice, not a Microsoft benchmark."],
    ["Confidence Label", "Verified, exact plus estimated, approximate, or behavioral signal. Use it to calibrate how strongly to state a finding."],
  ];
  terms.forEach((term, i) => {
    const x = i % 2 === 0 ? 0.65 : 6.86;
    const y = 1.07 + Math.floor(i / 2) * 1.72;
    addTermCard(slide, x, y, 5.82, term[0], term[1], i % 2 === 0 ? C.magenta : C.blue);
  });
  addFooter(slide);
}

// Slide 9 - responsible targets
{
  const slide = deck.addSlide("CONTENT");
  addSectionTitle(slide, "How to use targets responsibly", "Targets are local planning assumptions, not Microsoft benchmarks");
  const headers = ["Signal", "Review question", "Required caution"];
  const rows = [
    ["Adoption", "Is observed reach moving toward the locally owned goal?", "Confirm denominator and source coverage."],
    ["License utilization", "Are licensed users active in the selected period?", "No observed activity is not proof of never-used."],
    ["Unmanaged AI share", "Is locally classified shadow activity changing?", "Classification comes from the local catalog."],
    ["Logins without CA", "Which successful sign-ins did not report CA success?", "Other protections may still have applied."],
  ];
  const xs = [0.64, 2.42, 5.58];
  const ws = [1.78, 3.16, 3.22];
  headers.forEach((header, i) => {
    slide.addShape(deck.ShapeType.rect, {
      x: xs[i],
      y: 1.15,
      w: ws[i],
      h: 0.5,
      fill: { color: C.purple },
      line: { color: C.white, width: 0.4 },
    });
    slide.addText(header, {
      x: xs[i] + 0.12,
      y: 1.29,
      w: ws[i] - 0.24,
      h: 0.16,
      fontFace: "Aptos",
      fontSize: 8.5,
      bold: true,
      color: C.white,
      margin: 0,
    });
  });
  rows.forEach((row, r) => {
    row.forEach((cell, i) => {
      slide.addShape(deck.ShapeType.rect, {
        x: xs[i],
        y: 1.65 + r * 1.0,
        w: ws[i],
        h: 1.0,
        fill: { color: r % 2 === 0 ? C.pale : C.white },
        line: { color: C.line, width: 0.5 },
      });
      slide.addText(cell, {
        x: xs[i] + 0.12,
        y: 1.82 + r * 1.0,
        w: ws[i] - 0.24,
        h: 0.56,
        fontFace: "Aptos",
        fontSize: i === 0 ? 8.8 : 8.2,
        bold: i === 0,
        color: C.ink,
        margin: 0,
        fit: "shrink",
        valign: "mid",
      });
    });
  });
  addImageFrame(slide, pageImages[7], 9.18, 1.15, 3.52, 1.98);
  addInfoCard(slide, {
    x: 9.18,
    y: 3.56,
    w: 3.52,
    h: 2.12,
    title: "Target governance",
    body: "Document the owner, rationale, review cadence, data period, and action threshold for every target. Keep the definition stable when comparing periods.",
    accent: C.teal,
    fill: C.paleTeal,
  });
  slide.addText(
    "A positive arithmetic gap is not automatically good or bad. Interpret whether higher or lower is desirable for that metric.",
    {
      x: 0.72,
      y: 6.15,
      w: 11.8,
      h: 0.42,
      fontFace: "Aptos",
      fontSize: 10.5,
      bold: true,
      color: C.purpleDark,
      align: "center",
      margin: 0,
    },
  );
  addFooter(slide);
}

// Slide 10 - first 30 days
{
  const slide = deck.addSlide("CONTENT");
  addSectionTitle(slide, "Your first 30 days with this report", "A practical sequence before operational use");
  const weeks = [
    ["WEEK 1", "Confirm the data", "Load the 13 CSVs. Check filters, reporting period, source freshness, row counts, identity mappings, and Tier Comparison. Do not present findings yet."],
    ["WEEK 2", "Align definitions", "Review the glossary and confidence labels. Confirm catalog classifications, workforce denominator, target owners, and locally accepted terms."],
    ["WEEK 3", "Corroborate signals", "Select representative adoption and risk patterns. Trace them back to source records and document false-positive or coverage scenarios."],
    ["WEEK 4", "Run the review", "Open with the Executive Summary, state coverage and limitations, then move to the relevant detail pages and agreed next actions."],
  ];
  weeks.forEach((week, i) => {
    const x = 0.58 + i * 3.17;
    const accent = [C.purple, C.blue, C.teal, C.magenta][i];
    slide.addShape(deck.ShapeType.roundRect, {
      x,
      y: 1.28,
      w: 2.82,
      h: 4.85,
      rectRadius: 0.08,
      fill: { color: i % 2 === 0 ? C.pale : C.white },
      line: { color: C.line, width: 1 },
    });
    slide.addShape(deck.ShapeType.rect, {
      x,
      y: 1.28,
      w: 2.82,
      h: 0.12,
      fill: { color: accent },
      line: { color: accent },
    });
    slide.addText(week[0], {
      x: x + 0.24,
      y: 1.78,
      w: 2.34,
      h: 0.24,
      fontFace: "Aptos",
      fontSize: 9,
      bold: true,
      color: accent,
      align: "center",
      margin: 0,
    });
    slide.addText(week[1], {
      x: x + 0.24,
      y: 2.27,
      w: 2.34,
      h: 0.72,
      fontFace: "Aptos Display",
      fontSize: 19,
      bold: true,
      color: C.purpleDark,
      align: "center",
      margin: 0,
      fit: "shrink",
      valign: "mid",
    });
    slide.addText(week[2], {
      x: x + 0.3,
      y: 3.25,
      w: 2.22,
      h: 2.2,
      fontFace: "Aptos",
      fontSize: 10,
      color: C.ink,
      align: "center",
      margin: 0,
      fit: "shrink",
      valign: "mid",
    });
  });
  addFooter(slide);
}

// Slide 11 - divider
{
  const slide = deck.addSlide();
  slide.background = { color: C.purpleDark };
  slide.addShape(deck.ShapeType.arc, {
    x: -1.3,
    y: -1.9,
    w: 7.0,
    h: 7.0,
    rotate: 15,
    fill: { color: C.magenta, transparency: 35 },
    line: { color: C.magenta, transparency: 100 },
  });
  slide.addShape(deck.ShapeType.arc, {
    x: 8.6,
    y: 2.8,
    w: 6.0,
    h: 6.0,
    rotate: 200,
    fill: { color: C.teal, transparency: 25 },
    line: { color: C.teal, transparency: 100 },
  });
  slide.addText("Detailed page interpretation", {
    x: 1.0,
    y: 2.62,
    w: 11.3,
    h: 0.72,
    fontFace: "Aptos Display",
    fontSize: 34,
    bold: true,
    color: C.white,
    align: "center",
    margin: 0,
  });
  slide.addText("Ten dashboard pages | four questions each | one evidence-aware reading path", {
    x: 1.0,
    y: 3.58,
    w: 11.3,
    h: 0.3,
    fontFace: "Aptos",
    fontSize: 14,
    color: "D9C9F3",
    align: "center",
    margin: 0,
  });
  slide.addShape(deck.ShapeType.roundRect, {
    x: 5.73,
    y: 4.45,
    w: 1.87,
    h: 0.48,
    rectRadius: 0.08,
    fill: { color: C.white, transparency: 8 },
    line: { color: C.white, transparency: 45 },
  });
  slide.addText("START WITH 1", {
    x: 5.83,
    y: 4.62,
    w: 1.67,
    h: 0.14,
    fontFace: "Aptos",
    fontSize: 8.5,
    bold: true,
    color: C.purpleDark,
    align: "center",
    margin: 0,
  });
}

const detailPages = [
  {
    title: "Executive Summary",
    subtitle: "Portfolio-level adoption, tool mix, and monthly direction",
    image: pageImages[0],
    callouts: [
      {
        number: 1,
        question: "Is observed AI adoption broad or concentrated?",
        interpretation: "AI Users and workforce adoption show reach within the configured sources and current filters. They are not a complete inventory of every AI interaction.",
        action: "Confirm the workforce denominator, active month, and source coverage before quoting the adoption rate.",
      },
      {
        number: 2,
        question: "Which solution groups are driving activity?",
        interpretation: "The service breakdown separates Copilot, licensed third-party, and shadow classifications using the local catalog and observed activity.",
        action: "Validate catalog classifications and compare user counts with volume before drawing a governance conclusion.",
      },
      {
        number: 3,
        question: "Is the direction sustained across periods?",
        interpretation: "Monthly trends show available report periods. Non-Microsoft prompt figures are modeled from activity/session signals rather than vendor logs.",
        action: "Use several complete periods and check filters; do not infer a trend from one partial month.",
      },
      {
        number: 4,
        question: "Where should the review go next?",
        interpretation: "This page orients the conversation but does not explain surface adoption, department concentration, or individual risk signals.",
        action: "Continue to Copilot Deep Dive, Shadow AI, and Department Breakdown for the relevant evidence.",
      },
    ],
  },
  {
    title: "Copilot Deep Dive",
    subtitle: "Audit-event-derived activity by surface, user, month, and department",
    image: pageImages[1],
    callouts: [
      {
        number: 1,
        question: "Are licensed and active users telling the same story?",
        interpretation: "Licensed Users is an entitlement dimension. Active Users requires observed activity in the selected context; the two values answer different questions.",
        action: "Review the reporting period and official Microsoft 365 Copilot usage report before a license action.",
      },
      {
        number: 2,
        question: "Which Copilot surfaces are gaining traction?",
        interpretation: "Prompt counts come from Purview CopilotInteraction audit records and retain the reported surface. They are directional analysis metrics.",
        action: "Compare surface mix over time and use the pattern to target workload-specific enablement.",
      },
      {
        number: 3,
        question: "Is activity broad or driven by a small group?",
        interpretation: "Prompts per user and department bars can look strong when a small population is highly active. Averages can hide concentration.",
        action: "Read active-user counts with prompt volume and inspect department reach before scaling conclusions.",
      },
      {
        number: 4,
        question: "What can this page support operationally?",
        interpretation: "It can surface enablement and adoption patterns, but audit-derived metrics can differ from official product usage reports.",
        action: "Use official usage reporting as the product benchmark and this page for cross-source context.",
      },
    ],
  },
  {
    title: "Behavioral Risk and File Activity",
    subtitle: "Cross-signal triage for investigation priority",
    image: pageImages[2],
    callouts: [
      {
        number: 1,
        question: "What does the AI Risk Score actually mean?",
        interpretation: "The score is a composite heuristic built from configured signals. It is not a probability, severity rating, or determination of misconduct.",
        action: "Read each heatmap column independently, then inspect the contributing events and source quality.",
      },
      {
        number: 2,
        question: "Do sensitive proximity events prove an upload?",
        interpretation: "They are selected file events observed shortly after an AI-domain connection. Temporal proximity does not establish transfer, disclosure, or causation.",
        action: "Validate the original file, device, network, and destination evidence before escalation.",
      },
      {
        number: 3,
        question: "How should geo anomalies be interpreted?",
        interpretation: "Country patterns can reflect travel, VPNs, proxies, mobile carriers, or shared infrastructure as well as activity that warrants review.",
        action: "Confirm identity, sign-in, device, and network context; document likely false-positive conditions.",
      },
      {
        number: 4,
        question: "What is the defensible investigation path?",
        interpretation: "Risk, consent, file, and geo signals prioritize attention but remain incomplete without the underlying source records and business purpose.",
        action: "Follow established incident, privacy, acceptable-use, legal, and personnel processes.",
      },
    ],
  },
  {
    title: "Shadow AI and Third-Party Tools",
    subtitle: "Observed activity and local sanction classification",
    image: pageImages[3],
    callouts: [
      {
        number: 1,
        question: "Why is a tool labeled shadow AI?",
        interpretation: "The label comes from the corresponding row in ai_solutions_catalog.csv. The report does not independently prove that the tool violates policy.",
        action: "Have security, legal, privacy, procurement, and business owners confirm classifications.",
      },
      {
        number: 2,
        question: "Are session bins and estimated prompts exact?",
        interpretation: "They approximate activity from configured telemetry. They are not content inspection and are not equivalent to vendor prompt logs.",
        action: "Use them for directional comparison, not precise productivity or data-loss claims.",
      },
      {
        number: 3,
        question: "Where is unmanaged activity concentrated?",
        interpretation: "The eight starter-solution colors support cross-page tracing; custom catalog additions use the default palette unless explicitly formatted.",
        action: "Compare values within a column, then check users, departments, and periods before choosing an intervention.",
      },
      {
        number: 4,
        question: "What response is proportionate?",
        interpretation: "Popular tools may need sanctioning review, procurement, user guidance, a supported alternative, or technical control evaluation.",
        action: "Validate domains and purpose first, then use the organization's governance process.",
      },
    ],
  },
  {
    title: "AI Solutions Intensity by Department",
    subtitle: "Two views of adoption breadth, intensity, and governance",
    image: pageImages[4],
    callouts: [
      {
        number: 1,
        question: "Which view should I use?",
        interpretation: "Dept Intensity compares weekly active days with weekly actions. Adoption vs Governance compares weekly actions per user with the managed-session share.",
        action: "Confirm the orange selected view, then use Open filters. Selections remain applied when the panel closes or the view changes.",
      },
      {
        number: 2,
        question: "What does bubble size add?",
        interpretation: "Bubble size changes by view: Dept Intensity uses AI Users; Adoption vs Governance uses Sensitive Proximity Events.",
        action: "Treat risk-event size as a triage signal, not severity or proof, and corroborate the source events.",
      },
      {
        number: 3,
        question: "Which pattern is an enablement opportunity?",
        interpretation: "In Dept Intensity, a large moderate-intensity bubble can indicate broad adoption; a small high-intensity bubble may be a specialist team.",
        action: "Validate department population and tool mix, then select the department for detail.",
      },
      {
        number: 4,
        question: "What should follow the visual comparison?",
        interpretation: "The scatter plot identifies contrast but does not explain which tools or users create it.",
        action: "Open Department Breakdown and confirm actions, users, solutions, and local business context.",
      },
    ],
  },
  {
    title: "Department Breakdown",
    subtitle: "Per-department activity, tool diversity, and top services",
    image: pageImages[5],
    callouts: [
      {
        number: 1,
        question: "Is high activity broad or concentrated?",
        interpretation: "A high action count can come from only a few users. User reach and volume must be read together.",
        action: "Compare action volume, active users, and weekly actions per user before ranking departments.",
      },
      {
        number: 2,
        question: "Does greatest growth predict future adoption?",
        interpretation: "Greatest Growth is a period-over-period result in the current filter context. It is not a forecast.",
        action: "Check period completeness and repeat the comparison over several stable windows.",
      },
      {
        number: 3,
        question: "Where might tool sprawl be increasing?",
        interpretation: "The eight starter-solution colors support cross-page tracing; purple table fills show relative values independently within each metric column.",
        action: "Validate classifications, department mappings, and the users behind each value before comparing departments.",
      },
      {
        number: 4,
        question: "How should a department action be chosen?",
        interpretation: "The page can support enablement or governance hypotheses but cannot supply the department's business purpose.",
        action: "Review the pattern with business owners before training, licensing, blocking, or procurement action.",
      },
    ],
  },
  {
    title: "Shadow AI and App Governance Data",
    subtitle: "Optional Defender for Cloud Apps evidence",
    image: pageImages[6],
    callouts: [
      {
        number: 1,
        question: "What source coverage does this page require?",
        interpretation: "App Governance alerts and Cloud Discovery traffic require supported Defender for Cloud Apps data, connectors, permissions, and retention.",
        action: "Confirm Tier Comparison and connector scope before interpreting an empty visual.",
      },
      {
        number: 2,
        question: "How should alert severity be handled?",
        interpretation: "Severity and descriptions should remain those supplied by the originating alert. The report does not create a new severity determination.",
        action: "Open the source alert and follow the source-system investigation workflow.",
      },
      {
        number: 3,
        question: "Does AI Upload MB prove exfiltration?",
        interpretation: "It is network traffic volume attributed by Cloud Discovery. It does not identify transferred content or establish data loss.",
        action: "Investigate the underlying session, user, device, destination, and content evidence.",
      },
      {
        number: 4,
        question: "Why might this page be blank?",
        interpretation: "Missing data can reflect licensing, region, unconfigured connectors, retention, export scope, or header-only placeholder files.",
        action: "Resolve source availability before concluding that no relevant activity or alerts exist.",
      },
    ],
  },
  {
    title: "Benchmarks and Targets",
    subtitle: "Observed metrics against locally selected what-if assumptions",
    image: pageImages[7],
    callouts: [
      {
        number: 1,
        question: "Are these Microsoft benchmarks?",
        interpretation: "No. The target controls are user-entered planning assumptions chosen by the organization.",
        action: "Document each target's owner, rationale, review cadence, and action threshold.",
      },
      {
        number: 2,
        question: "Is a positive gap always favorable?",
        interpretation: "Gap cards are arithmetic differences in percentage points or counts. Desired direction depends on the metric.",
        action: "State whether higher or lower is desirable before presenting the gap.",
      },
      {
        number: 3,
        question: "What does logins without CA mean?",
        interpretation: "It counts successful AI sign-ins whose Entra record does not report Conditional Access as successfully applied. Other protections may still exist.",
        action: "Inspect the source sign-in and relevant controls before asserting an access-control failure.",
      },
      {
        number: 4,
        question: "Can month-over-month cards be quoted immediately?",
        interpretation: "They compare the current report period with the prior period available to the measure. A partial month can distort the change.",
        action: "Check filter context and period completeness, then use the same definition each review.",
      },
    ],
  },
  {
    title: "Glossary and Data Dictionary",
    subtitle: "Definitions, source descriptions, and confidence labels",
    image: pageImages[8],
    callouts: [
      {
        number: 1,
        question: "What does Verified mean?",
        interpretation: "Verified means calculated from a named source event or dimension. It does not establish intent, causality, or complete tenant coverage.",
        action: "Pair the metric with its source, reporting period, and relevant limitations.",
      },
      {
        number: 2,
        question: "How should estimated metrics be stated?",
        interpretation: "Exact plus estimated mixes source values with modeled activity. Status colors reinforce the visible labels; they do not replace them.",
        action: "Use the confidence label in screenshots, exports, and executive narration.",
      },
      {
        number: 3,
        question: "Why review source-table definitions?",
        interpretation: "They describe the report input and calculation path, not guaranteed source availability or completeness in a tenant.",
        action: "Trace unexpected values back to the CSV, collector, and originating system.",
      },
      {
        number: 4,
        question: "When should this page be opened?",
        interpretation: "Use it whenever a metric will be repeated outside the report or compared across audiences.",
        action: "Confirm definition, confidence, period, filters, and denominator before sharing.",
      },
    ],
  },
  {
    title: "Data Coverage by License and Source",
    subtitle: "Planning aid for available signals and known limitations",
    image: pageImages[9],
    callouts: [
      {
        number: 1,
        question: "Is this matrix a licensing entitlement statement?",
        interpretation: "No. It is a planning aid that maps report capabilities to common product and source combinations.",
        action: "Verify current Microsoft licensing documentation and tenant configuration.",
      },
      {
        number: 2,
        question: "Why can an owned product still produce no data?",
        interpretation: "Onboarding, connector selection, permissions, region, policy configuration, export scope, and retention all affect coverage.",
        action: "Validate each dependency before interpreting an empty page as no activity.",
      },
      {
        number: 3,
        question: "What does the sign-in hunting signal require?",
        interpretation: "EntraIdSignInEvents requires Microsoft Entra ID P2 and appropriate Defender XDR advanced hunting access.",
        action: "Confirm role, license, and table availability in the target tenant.",
      },
      {
        number: 4,
        question: "What does CloudAppEvents require?",
        interpretation: "CloudAppEvents requires Defender for Cloud Apps data and its Microsoft 365 activities connector; MDE Plan 2 alone does not supply the table.",
        action: "Resolve missing source coverage before drawing conclusions from MDA-dependent visuals.",
      },
    ],
  },
];

detailPages.forEach(addDetailSlide);

(async () => {
  await deck.writeFile({ fileName: output });
  console.log(output);
})().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
