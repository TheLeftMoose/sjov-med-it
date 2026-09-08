[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Model,

    [ValidateSet("none", "minimal", "low", "medium", "high", "xhigh", "max")]
    [string]$ReasoningEffort = "medium",

    [ValidateRange(1, 99)]
    [int]$RunNumber = 1,

    [string]$Researcher = "Unknown",

    [switch]$Force
)

$ErrorActionPreference = "Stop"

function ConvertTo-Slug {
    param([Parameter(Mandatory = $true)][string]$Value)

    $slug = $Value.ToLowerInvariant() -replace "[^a-z0-9]+", "-"
    return $slug.Trim("-")
}

$experimentDirectory = Split-Path -Parent $PSScriptRoot
$taskPath = Join-Path $experimentDirectory "task.md"
$resultsDirectory = Join-Path $experimentDirectory "results"
$sessionId = [guid]::NewGuid().ToString()
$runId = "copilot-cli--$(ConvertTo-Slug $Model)--run-$($RunNumber.ToString("D2"))"
$resultPath = Join-Path $resultsDirectory "$runId.md"
$workDirectory = Join-Path $experimentDirectory ".benchmark-work\$sessionId"

if ((Test-Path $resultPath) -and -not $Force) {
    throw "Result already exists: $resultPath. Use -Force to overwrite it."
}

if (-not (Get-Command copilot -ErrorAction SilentlyContinue)) {
    throw "GitHub Copilot CLI was not found on PATH."
}

$task = Get-Content -Raw $taskPath
$promptSection = [regex]::Match(
    $task,
    "(?s)## Prompts\s*(.*?)\s*## Expected reasoning"
)

if (-not $promptSection.Success) {
    throw "Could not find the prompt section in $taskPath."
}

$turnMatches = [regex]::Matches(
    $promptSection.Groups[1].Value,
    "(?ms)^### Turn (?<turn>\d+)\s*\r?\n(?<prompt>.*?)(?=^### Turn |\z)"
)

if ($turnMatches.Count -ne 7) {
    throw "Expected 7 prompts in $taskPath, found $($turnMatches.Count)."
}

$prompts = foreach ($match in $turnMatches) {
    $lines = $match.Groups["prompt"].Value.Trim() -split "\r?\n"
    $prompt = ($lines | ForEach-Object { $_ -replace "^\s*>\s?", "" }) -join "`n"

    [pscustomobject]@{
        Turn = [int]$match.Groups["turn"].Value
        Text = $prompt.Trim()
    }
}

$prompts = $prompts | Sort-Object Turn
$copilotVersion = (& copilot --version | Select-Object -First 1).Trim()
$responses = [System.Collections.Generic.List[object]]::new()

New-Item -ItemType Directory -Force -Path $workDirectory | Out-Null

try {
    foreach ($prompt in $prompts) {
        Write-Host "Running turn $($prompt.Turn) of $($prompts.Count)..."

        $arguments = @(
            "-C", $workDirectory
            "--prompt", $prompt.Text
            "--session-id", $sessionId
            "--model", $Model
            "--reasoning-effort", $ReasoningEffort
            "--no-custom-instructions"
            "--disable-builtin-mcps"
            "--disallow-temp-dir"
            "--available-tools="
            "--allow-all-tools"
            "--silent"
            "--no-color"
            "--no-remote-export"
            "--stream", "off"
        )

        $response = (& copilot @arguments 2>&1) -join [Environment]::NewLine

        if ($LASTEXITCODE -ne 0) {
            throw "Copilot CLI failed on turn $($prompt.Turn):`n$response"
        }

        $responses.Add([pscustomobject]@{
            Turn = $prompt.Turn
            Text = $response.Trim()
        })
    }

    $date = Get-Date -Format "yyyy-MM-dd"
    $document = [System.Collections.Generic.List[string]]::new()
    $document.Add("# Benchmark run")
    $document.Add("")
    $document.Add("## Metadata")
    $document.Add("")
    $document.Add("| Field | Value |")
    $document.Add("| --- | --- |")
    $document.Add("| Run ID | $runId |")
    $document.Add("| Date | $date |")
    $document.Add("| Researcher | $Researcher |")
    $document.Add("| Harness | GitHub Copilot CLI |")
    $document.Add("| Harness version | $copilotVersion |")
    $document.Add("| Harness mode | Non-interactive prompt with resumed session |")
    $document.Add("| Model provider | GitHub Copilot |")
    $document.Add("| Model | $Model |")
    $document.Add("| Model version | Unknown |")
    $document.Add("| Temperature | Unknown |")
    $document.Add("| Reasoning mode | $ReasoningEffort |")
    $document.Add("| System/custom instructions | Repository instructions disabled |")
    $document.Add("| Tools enabled | None |")
    $document.Add("| Skills or subagents enabled | None |")
    $document.Add("| Repository context provided | None |")
    $document.Add("| Internet access | None exposed to the model |")
    $document.Add("| Run number | $RunNumber |")
    $document.Add("| Copilot session ID | $sessionId |")
    $document.Add("")
    $document.Add("## Harness notes")
    $document.Add("")
    $document.Add("Prompts were submitted by `scripts/run-copilot-cli.ps1`. Custom")
    $document.Add("instructions, tools, built-in MCP servers, and remote export were disabled.")
    $document.Add("")
    $document.Add("## Run notes")
    $document.Add("")
    $document.Add("None.")

    foreach ($response in $responses) {
        $document.Add("")
        $document.Add("## Turn $($response.Turn) response")
        $document.Add("")
        $document.Add($response.Text)
    }

    New-Item -ItemType Directory -Force -Path $resultsDirectory | Out-Null
    Set-Content -Path $resultPath -Value $document -Encoding utf8
    Write-Host "Created result: $resultPath"
}
finally {
    if (Test-Path $workDirectory) {
        Remove-Item -Recurse -Force $workDirectory
    }
}
