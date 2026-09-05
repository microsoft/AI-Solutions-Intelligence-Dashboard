<#
.SYNOPSIS
    Builds the V27 In Testing narrated walkthrough from actual report captures.

.DESCRIPTION
    Uses the local Windows speech synthesizer and FFmpeg. The narration matches
    AI-Solutions-Dashboard-V27-In-Testing-Walkthrough-transcript.md.
#>
[CmdletBinding()]
param(
    [string]$Voice = 'Microsoft David Desktop',
    [ValidateRange(-10, 10)]
    [int]$Rate = 2
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent $PSScriptRoot
$images = Join-Path $repo 'images\v27-report-pages'
$output = Join-Path $PSScriptRoot 'AI-Solutions-Dashboard-V27-In-Testing-Walkthrough.mp4'
$temp = Join-Path $PSScriptRoot '.walkthrough-build'

$ffmpeg = (Get-Command ffmpeg -ErrorAction Stop).Source
$ffprobe = (Get-Command ffprobe -ErrorAction Stop).Source

$segments = @(
    @{
        Image = '01-executive-summary.png'
        Text = 'Welcome to the AI Solutions Intelligence Dashboard, version 27 In Testing. This walkthrough uses fabricated sample data and actual Power BI captures. Start on the Executive Summary to review adoption, tool mix, and monthly direction. Always check the active filters and reporting period. The dashboard combines available source signals; it does not guarantee complete tenant coverage, and its sample values are not recommendations or operational findings.'
    },
    @{
        Image = '02-copilot-deep-dive.png'
        Text = 'The Copilot Deep Dive summarizes Copilot interaction audit events by surface, month, user, and department. Licensed users and active users answer different questions. Prompt counts are directional metrics derived from Purview audit records. Microsoft notes that audit-log-derived active-user and prompt metrics can differ from the official Microsoft 365 Copilot usage report and Viva Insights Copilot Dashboard. Use this page to find enablement patterns, then confirm them with official product reports where available.'
    },
    @{
        Image = '03-behavioral-risk.png'
        Text = 'Behavioral Risk combines configured signals into investigation priorities. The AI Risk Score is a heuristic composite, not a probability or severity rating. Sensitive proximity events are selected file create, modify, rename, or copy events observed shortly after an AI-domain network connection. That timing does not prove upload, disclosure, or causation. Geo anomalies can also reflect travel, V P Ns, proxies, or network routing. Validate the original Entra, Defender, device, and consent records before taking action.'
    },
    @{
        Image = '04-shadow-ai.png'
        Text = 'The Shadow AI page summarizes observed third-party activity and the classifications in the local AI solutions catalog. A tool appears as shadow AI because of that catalog classification, not because the report independently proves a policy violation. Session bins and estimated prompts approximate activity; they are not vendor prompt logs or content inspection. Use the page to identify popular tools for review with security, privacy, legal, procurement, and business owners.'
    },
    @{
        Image = '05-dept-intensity.png'
        Text = 'The department intensity view compares breadth and depth of adoption. Weekly active days are on the horizontal axis and are capped at seven. Weekly actions are on the vertical axis, and bubble size represents user count. A small, high-intensity bubble can be a specialist group, while a larger moderate bubble can indicate broad adoption. Select a department, then continue to Department Breakdown for context.'
    },
    @{
        Image = '06-department-breakdown.png'
        Text = 'Department Breakdown separates activity volume, user reach, tool diversity, and monthly solution mix. High volume can come from only a few users, so compare bars with user counts and averages. Greatest growth is a period-over-period result in the current filter context, not a forecast. Confirm department mappings in the Entra users file, then use business-owner interviews before setting training, license, or governance actions.'
    },
    @{
        Image = '07-shadow-ai-catalog.png'
        Text = 'This optional page adds Defender for Cloud Apps exports. Alert severity should remain the originating source severity. Upload megabytes is network traffic volume attributed by Cloud Discovery; it does not identify transferred content and is not proof of data exfiltration. Missing visuals can reflect licensing, regional availability, an unconfigured connector, retention, or a header-only placeholder. Open the source alert or Cloud Discovery record before escalation.'
    },
    @{
        Image = '08-benchmarks-targets.png'
        Text = 'Benchmarks and Targets compares observed metrics with local what-if assumptions. These targets are not Microsoft benchmarks. Gap cards are arithmetic differences, so interpret whether higher or lower is desirable for each measure. Logins without Conditional Access means the Entra record reports Conditional Access as not applied. It does not prove that M F A, device, network, or location protections were absent. Month-over-month cards compare available report periods; check period completeness before quoting the change.'
    },
    @{
        Image = '09-glossary-data-dictionary.png'
        Text = 'Use the glossary before sharing any metric. Verified means calculated from a named source event or dimension; it does not establish intent or causality. Exact plus estimated combines source values with modeled activity. Approximate and behavioral signals require corroboration. Include the confidence label, reporting period, and filters whenever a value is exported or discussed outside the report.'
    },
    @{
        Image = '10-tier-comparison.png'
        Text = 'Finish with Data Coverage by License and Source. This matrix is a planning aid, not a licensing entitlement statement. Product ownership alone does not guarantee data. Onboarding, connectors, permissions, retention, and regional availability also matter. Entra sign-in hunting requires Entra I D P 2. Cloud app events require Defender for Cloud Apps and its Microsoft 365 activities connector. Version 27 is experimental and In Testing. Protect customer exports, corroborate every risk signal, and read the interpretation guide before operational use.'
    }
)

if (Test-Path $temp) {
    Remove-Item $temp -Recurse -Force
}
New-Item -ItemType Directory -Path $temp | Out-Null

Add-Type -AssemblyName System.Speech
$synth = [System.Speech.Synthesis.SpeechSynthesizer]::new()
try {
    $availableVoices = @($synth.GetInstalledVoices() | ForEach-Object { $_.VoiceInfo.Name })
    if ($Voice -in $availableVoices) {
        $synth.SelectVoice($Voice)
    }
    $synth.Rate = $Rate
    $synth.Volume = 100
    $selectedVoice = $synth.Voice.Name

    $clipFiles = [System.Collections.Generic.List[string]]::new()
    for ($i = 0; $i -lt $segments.Count; $i++) {
        $number = $i + 1
        $wav = Join-Path $temp ('narration-{0:D2}.wav' -f $number)
        $clip = Join-Path $temp ('segment-{0:D2}.mp4' -f $number)
        $image = Join-Path $images $segments[$i].Image

        if (-not (Test-Path $image)) {
            throw "Missing walkthrough image: $image"
        }

        $synth.SetOutputToWaveFile($wav)
        $synth.Speak([string]$segments[$i].Text)
        $synth.SetOutputToNull()

        & $ffmpeg -hide_banner -loglevel error -y `
            -loop 1 -framerate 30 -i $image -i $wav `
            -vf 'scale=1280:720:force_original_aspect_ratio=decrease,pad=1280:720:(ow-iw)/2:(oh-ih)/2:color=0xF4F5F9,format=yuv420p' `
            -af 'apad=pad_dur=0.5' `
            -c:v libx264 -preset medium -crf 20 -tune stillimage `
            -c:a aac -b:a 128k -shortest $clip
        if ($LASTEXITCODE -ne 0) {
            throw "FFmpeg failed while building segment $number."
        }
        $clipFiles.Add($clip)
    }
}
finally {
    $synth.Dispose()
}

$concat = Join-Path $temp 'concat.txt'
$concatLines = $clipFiles | ForEach-Object {
    "file '$([System.IO.Path]::GetFileName($_))'"
}
[System.IO.File]::WriteAllLines($concat, $concatLines)

Push-Location $temp
try {
    & $ffmpeg -hide_banner -loglevel error -y `
        -f concat -safe 0 -i 'concat.txt' -c copy `
        -metadata title='AI Solutions Dashboard V27 In Testing Walkthrough' `
        -metadata comment='Actual Power BI captures with fabricated sample data.' `
        $output
    if ($LASTEXITCODE -ne 0) {
        throw 'FFmpeg failed while concatenating walkthrough segments.'
    }
}
finally {
    Pop-Location
}

$duration = & $ffprobe -v error -show_entries format=duration `
    -of default=noprint_wrappers=1:nokey=1 $output
$file = Get-Item $output
Remove-Item $temp -Recurse -Force

[PSCustomObject]@{
    Output = $file.FullName
    Bytes = $file.Length
    DurationSeconds = [Math]::Round([double]$duration, 1)
    Voice = $selectedVoice
    Rate = $Rate
}
