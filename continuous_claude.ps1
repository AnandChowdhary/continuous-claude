#!/usr/bin/env pwsh

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$script:Version = "v0.24.6"
$script:ClaudeFlags = @("--dangerously-skip-permissions", "--output-format", "stream-json", "--verbose")
$script:CodexFlags = @("--json", "--dangerously-bypass-approvals-and-sandbox", "--skip-git-repo-check")

$script:NotesFile = "SHARED_TASK_NOTES.md"
$script:AgentProvider = if ($env:CONTINUOUS_CLAUDE_PROVIDER) { $env:CONTINUOUS_CLAUDE_PROVIDER } else { "claude" }
$script:ReviewProvider = ""
$script:CodexInputCostPerMillion = if ($env:CODEX_INPUT_COST_PER_MILLION) { $env:CODEX_INPUT_COST_PER_MILLION } else { "" }
$script:CodexOutputCostPerMillion = if ($env:CODEX_OUTPUT_COST_PER_MILLION) { $env:CODEX_OUTPUT_COST_PER_MILLION } else { "" }
$script:CodexCachedInputCostPerMillion = if ($env:CODEX_CACHED_INPUT_COST_PER_MILLION) { $env:CODEX_CACHED_INPUT_COST_PER_MILLION } else { "" }

$script:Prompt = ""
$script:MaxRuns = ""
$script:MaxCost = ""
$script:MaxDuration = ""
$script:EnableCommits = $true
$script:DisableBranches = $false
$script:GitBranchPrefix = "continuous-claude/"
$script:MergeStrategy = "squash"
$script:GitHubOwner = ""
$script:GitHubRepo = ""
$script:DryRun = $false
$script:CompletionSignal = "CONTINUOUS_CLAUDE_PROJECT_COMPLETE"
$script:CompletionThreshold = 3
$script:ReviewPrompt = ""
$script:DisableUpdates = $false
$script:ExtraAgentFlags = [System.Collections.Generic.List[string]]::new()

$script:PromptCommitMessage = "Please review all uncommitted changes in the git repository (both modified and new files). Write a commit message with: (1) a short one-line summary, (2) two newlines, (3) then a detailed explanation. Do not include any footers or metadata like 'Generated with Claude Code' or 'Co-Authored-By'. Feel free to look at the last few commits to get a sense of the commit message style for consistency. First run 'git add .' to stage all changes including new untracked files, then commit using 'git commit -m `"your message`"' (don't push, just commit, no need to ask for confirmation)."

$script:PromptWorkflowContext = @"
## CONTINUOUS WORKFLOW CONTEXT

This is part of a continuous development loop where work happens incrementally across multiple iterations. You might run once, then a human developer might make changes, then you run again, and so on. This could happen daily or on any schedule.

**Important**: You don't need to complete the entire goal in one iteration. Just make meaningful progress on one thing, then leave clear notes for the next iteration (human or AI). Think of it as a relay race where you're passing the baton.

**Do NOT commit or push changes** - The automation will handle committing and pushing your changes after you finish. Just focus on making the code changes.

**Project Completion Signal**: If you determine that not just your current task but the ENTIRE project goal is fully complete (nothing more to be done on the overall goal), only include the exact phrase "COMPLETION_SIGNAL_PLACEHOLDER" in your response. Only use this when absolutely certain that the whole project is finished, not just your individual task. We will stop working on this project when multiple developers independently determine that the project is complete.

## PRIMARY GOAL
"@

$script:PromptNotesGuidelines = @"

This file helps coordinate work across iterations (both human and AI developers). It should:

- Contain relevant context and instructions for the next iteration
- Stay concise and actionable (like a notes file, not a detailed report)
- Help the next developer understand what to do next

The file should NOT include:
- Lists of completed work or full reports
- Information that can be discovered by running tests/coverage
- Unnecessary details
"@

$script:PromptReviewerContext = @"
## CODE REVIEW CONTEXT

You are performing a review pass on changes just made by another developer. This is NOT a new feature implementation - you are reviewing and validating existing changes using the instructions given below by the user. Feel free to use git commands to see what changes were made if it's helpful to you.

**Do NOT commit or push changes** - The automation will handle committing and pushing your changes after you finish. Just focus on validating and fixing any issues.
"@

$script:PromptDefaultReviewer = "Review the currently changed files on this branch before I ship. Look at the diff and read everything that changed. Run the test suite, typecheck, lint, formatter, etc., whatever is available, and fix anything that fails. Invoke the /simplify skill on the changed files to dedupe, extract clean abstractions where patterns repeat, and tighten naming, but don't over-abstract. Then start the dev server if any, and drive the app with real tooling, like a browser test similar to the agent-browser CLI or whatever else is relevant to this project. Screenshot surfaces you touched, click through the golden path and edge cases, and watch the dev server logs and browser console for warnings or errors where relevant. Report back with what changed, what you simplified, test results, and a screenshot-backed walkthrough, and flag anything you couldn't verify. No need to commit or push."

function Write-Err {
    param([string]$Message)
    [Console]::Error.WriteLine($Message)
}

function Show-Version {
    Write-Output "continuous-claude PowerShell version $script:Version"
}

function Show-Help {
    @"
Continuous Claude PowerShell - native Windows runner

USAGE:
    ./continuous_claude.ps1 -p "prompt" (-m max-runs | --max-cost max-cost | --max-duration duration) [options]

REQUIRED OPTIONS:
    -p, --prompt <text>             The prompt/goal for the selected agent to work on
    -m, --max-runs <number>         Maximum successful iterations (use 0 for unlimited with --max-cost or --max-duration)
    --max-cost <dollars>            Maximum estimated cost in USD
    --max-duration <duration>       Maximum duration to run, e.g. 2h, 30m, 1h30m

OPTIONAL FLAGS:
    -h, --help                      Show this help message
    -v, --version                   Show version information
    --provider <provider>           AI coding agent provider: claude or codex (default: claude)
    --review-provider <provider>    Provider for reviewer pass: claude or codex (defaults to --provider)
    --owner <owner>                 GitHub repository owner (auto-detected from git remote if not provided)
    --repo <repo>                   GitHub repository name (auto-detected from git remote if not provided)
    --disable-commits               Disable automatic commits and PR creation
    --disable-branches              Commit on current branch without creating branches or PRs
    --disable-updates               Accepted for parity with the Bash runner
    --git-branch-prefix <prefix>    Branch prefix for iterations (default: continuous-claude/)
    --merge-strategy <strategy>     PR merge strategy: squash, merge, or rebase (default: squash)
    --notes-file <file>             Shared notes file for iteration context (default: SHARED_TASK_NOTES.md)
    --knowledge-file <file>         Bash-runner only; durable project knowledge file
    --dry-run                       Simulate execution without making changes
    --completion-signal <phrase>    Phrase agents output when project is complete
    --completion-threshold <num>    Consecutive signals required to stop early (default: 3)
    --stall-threshold <number>      Bash-runner only; pause after repeated failures and write diagnostics
    --max-calls-per-hour <number>   Bash-runner only; throttle provider calls to this hourly ceiling
    --error-threshold <number>      Bash-runner only; consecutive non-rate-limit errors before exiting
    -r, --review-prompt [text]      Run a reviewer pass after each iteration; uses a default prompt when text is omitted
    --codex-input-cost-per-million <dollars>
                                    Input token rate for Codex --max-cost estimates
    --codex-output-cost-per-million <dollars>
                                    Output token rate for Codex --max-cost estimates
    --codex-cached-input-cost-per-million <dollars>
                                    Cached input token rate for Codex estimates (defaults to input rate)
    --                              Stop parsing continuous-claude options; forward the rest to the provider CLI

EXAMPLES:
    ./continuous_claude.ps1 -p "Fix lint errors" -m 3
    ./continuous_claude.ps1 --provider codex -p "Add tests" -m 3
    ./continuous_claude.ps1 --provider claude --review-provider codex -p "Add tests" -m 3 -r
    ./continuous_claude.ps1 -p "Review my branch" -m 1 -r --disable-commits
"@
}

function Add-ExtraAgentFlag {
    param([string]$Flag)
    [void]$script:ExtraAgentFlags.Add($Flag)
}

function Need-Value {
    param(
        [string[]]$Items,
        [int]$Index,
        [string]$Flag
    )

    if ($Index + 1 -ge $Items.Count) {
        throw "Missing value for $Flag"
    }
    return $Items[$Index + 1]
}

function Exit-UnsupportedFlag {
    param([string]$Flag)
    Write-Err "Error: $Flag is not supported by the native PowerShell runner yet. Use the Bash runner for this workflow."
    exit 1
}

function Parse-Arguments {
    param([string[]]$Items)

    $i = 0
    while ($i -lt $Items.Count) {
        $arg = $Items[$i]
        switch -Regex ($arg) {
            "^--$" {
                $i++
                while ($i -lt $Items.Count) {
                    Add-ExtraAgentFlag $Items[$i]
                    $i++
                }
                break
            }
            "^(-h|--help)$" {
                Show-Help
                exit 0
            }
            "^(-v|--version)$" {
                Show-Version
                exit 0
            }
            "^(-p|--prompt)$" {
                $script:Prompt = Need-Value $Items $i $arg
                $i += 2
                continue
            }
            "^(-m|--max-runs)$" {
                $script:MaxRuns = Need-Value $Items $i $arg
                $i += 2
                continue
            }
            "^--provider$" {
                $script:AgentProvider = Need-Value $Items $i $arg
                $i += 2
                continue
            }
            "^--review-provider$" {
                $script:ReviewProvider = Need-Value $Items $i $arg
                $i += 2
                continue
            }
            "^--max-cost$" {
                $script:MaxCost = Need-Value $Items $i $arg
                $i += 2
                continue
            }
            "^--max-duration$" {
                $script:MaxDuration = Need-Value $Items $i $arg
                $i += 2
                continue
            }
            "^--codex-input-cost-per-million$" {
                $script:CodexInputCostPerMillion = Need-Value $Items $i $arg
                $i += 2
                continue
            }
            "^--codex-output-cost-per-million$" {
                $script:CodexOutputCostPerMillion = Need-Value $Items $i $arg
                $i += 2
                continue
            }
            "^--codex-cached-input-cost-per-million$" {
                $script:CodexCachedInputCostPerMillion = Need-Value $Items $i $arg
                $i += 2
                continue
            }
            "^--owner$" {
                $script:GitHubOwner = Need-Value $Items $i $arg
                $i += 2
                continue
            }
            "^--repo$" {
                $script:GitHubRepo = Need-Value $Items $i $arg
                $i += 2
                continue
            }
            "^--git-branch-prefix$" {
                $script:GitBranchPrefix = Need-Value $Items $i $arg
                $i += 2
                continue
            }
            "^--merge-strategy$" {
                $script:MergeStrategy = Need-Value $Items $i $arg
                $i += 2
                continue
            }
            "^--notes-file$" {
                $script:NotesFile = Need-Value $Items $i $arg
                $i += 2
                continue
            }
            "^--knowledge-file$" {
                Exit-UnsupportedFlag $arg
            }
            "^--disable-commits$" {
                $script:EnableCommits = $false
                $i++
                continue
            }
            "^--disable-branches$" {
                $script:DisableBranches = $true
                $i++
                continue
            }
            "^--disable-updates$" {
                $script:DisableUpdates = $true
                $i++
                continue
            }
            "^--auto-update$" {
                Exit-UnsupportedFlag $arg
            }
            "^--worktree$" {
                Exit-UnsupportedFlag $arg
            }
            "^--worktree-base-dir$" {
                Exit-UnsupportedFlag $arg
            }
            "^--cleanup-worktree$" {
                Exit-UnsupportedFlag $arg
            }
            "^--list-worktrees$" {
                Exit-UnsupportedFlag $arg
            }
            "^--dry-run$" {
                $script:DryRun = $true
                $i++
                continue
            }
            "^--completion-signal$" {
                $script:CompletionSignal = Need-Value $Items $i $arg
                $i += 2
                continue
            }
            "^--completion-threshold$" {
                $script:CompletionThreshold = [int](Need-Value $Items $i $arg)
                $i += 2
                continue
            }
            "^--stall-threshold$" {
                Exit-UnsupportedFlag $arg
            }
            "^--max-calls-per-hour$" {
                Exit-UnsupportedFlag $arg
            }
            "^--error-threshold$" {
                Exit-UnsupportedFlag $arg
            }
            "^--review-prompt=.*$" {
                $script:ReviewPrompt = $arg.Substring("--review-prompt=".Length)
                if ([string]::IsNullOrEmpty($script:ReviewPrompt)) {
                    $script:ReviewPrompt = $script:PromptDefaultReviewer
                }
                $i++
                continue
            }
            "^(-r|--review-prompt)$" {
                if ($i + 1 -lt $Items.Count -and -not [string]::IsNullOrEmpty($Items[$i + 1]) -and -not $Items[$i + 1].StartsWith("-")) {
                    $script:ReviewPrompt = $Items[$i + 1]
                    $i += 2
                } else {
                    $script:ReviewPrompt = $script:PromptDefaultReviewer
                    $i++
                }
                continue
            }
            "^--disable-ci-retry$" {
                Exit-UnsupportedFlag $arg
            }
            "^--ci-retry-max$" {
                Exit-UnsupportedFlag $arg
            }
            "^--disable-comment-review$" {
                Exit-UnsupportedFlag $arg
            }
            "^--comment-review-max$" {
                Exit-UnsupportedFlag $arg
            }
            default {
                Add-ExtraAgentFlag $arg
                $i++
                continue
            }
        }
    }
}

function Is-PositiveNumber {
    param([string]$Value)
    $parsed = 0.0
    return [double]::TryParse($Value, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$parsed) -and $parsed -gt 0
}

function Is-NonNegativeNumber {
    param([string]$Value)
    $parsed = 0.0
    return [double]::TryParse($Value, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$parsed) -and $parsed -ge 0
}

function Parse-Duration {
    param([string]$Value)

    $normalized = ($Value -replace "\s", "").ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($normalized)) {
        throw "Invalid duration"
    }

    $total = 0
    $matches = [regex]::Matches($normalized, "(\d+)([hms])")
    $rebuilt = ""
    foreach ($match in $matches) {
        $amount = [int]$match.Groups[1].Value
        $unit = $match.Groups[2].Value
        $rebuilt += $match.Value
        switch ($unit) {
            "h" { $total += $amount * 3600 }
            "m" { $total += $amount * 60 }
            "s" { $total += $amount }
        }
    }

    if ($rebuilt -ne $normalized -or $total -le 0) {
        throw "Invalid duration"
    }

    return $total
}

function Format-Duration {
    param([int]$Seconds)
    $parts = [System.Collections.Generic.List[string]]::new()
    $hours = [Math]::Floor($Seconds / 3600)
    $minutes = [Math]::Floor(($Seconds % 3600) / 60)
    $remainingSeconds = $Seconds % 60
    if ($hours -gt 0) { [void]$parts.Add("${hours}h") }
    if ($minutes -gt 0) { [void]$parts.Add("${minutes}m") }
    if ($remainingSeconds -gt 0 -or $parts.Count -eq 0) { [void]$parts.Add("${remainingSeconds}s") }
    return ($parts -join " ")
}

function Invoke-ExternalCommand {
    param(
        [string]$FilePath,
        [string[]]$Arguments
    )

    $psi = [Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $FilePath
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    foreach ($argument in $Arguments) {
        [void]$psi.ArgumentList.Add($argument)
    }

    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $psi
    [void]$process.Start()
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()

    return [pscustomobject]@{
        ExitCode = $process.ExitCode
        StdOut = $stdout
        StdErr = $stderr
    }
}

function Invoke-Git {
    param([string[]]$Arguments)
    return Invoke-ExternalCommand "git" $Arguments
}

function Invoke-Gh {
    param([string[]]$Arguments)
    return Invoke-ExternalCommand "gh" $Arguments
}

function Require-Command {
    param(
        [string]$Name,
        [string]$InstallUrl
    )

    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        Write-Err "Error: $Name is not installed: $InstallUrl"
        exit 1
    }
}

function Get-AgentCommand {
    param([string]$Provider = $script:AgentProvider)

    switch ($Provider) {
        "claude" { return "claude" }
        "codex" { return "codex" }
        default { return $Provider }
    }
}

function Get-AgentDisplayName {
    param([string]$Provider = $script:AgentProvider)

    switch ($Provider) {
        "claude" { return "Claude Code" }
        "codex" { return "Codex CLI" }
        default { return $Provider }
    }
}

function Get-AgentInstallUrl {
    param([string]$Provider = $script:AgentProvider)

    switch ($Provider) {
        "claude" { return "https://github.com/anthropics/claude-code" }
        "codex" { return "https://help.openai.com/en/articles/11096431" }
        default { return "provider-specific install instructions" }
    }
}

function Detect-GitHubRepo {
    $remote = Invoke-Git @("remote", "get-url", "origin")
    if ($remote.ExitCode -ne 0) {
        return $null
    }

    $url = $remote.StdOut.Trim()
    if ($url -match "github\.com[:/]([^/]+)/([^/]+?)(\.git)?$") {
        return [pscustomobject]@{ Owner = $matches[1]; Repo = $matches[2] }
    }
    return $null
}

function Validate-Arguments {
    if ($script:AgentProvider -notin @("claude", "codex")) {
        Write-Err "Error: --provider must be one of: claude, codex"
        exit 1
    }

    if (-not [string]::IsNullOrWhiteSpace($script:ReviewProvider) -and $script:ReviewProvider -notin @("claude", "codex")) {
        Write-Err "Error: --review-provider must be one of: claude, codex"
        exit 1
    }

    if ([string]::IsNullOrWhiteSpace($script:Prompt)) {
        Write-Err "Error: Prompt is required. Use -p to provide a prompt."
        exit 1
    }

    if ([string]::IsNullOrWhiteSpace($script:MaxRuns) -and [string]::IsNullOrWhiteSpace($script:MaxCost) -and [string]::IsNullOrWhiteSpace($script:MaxDuration)) {
        Write-Err "Error: Either --max-runs, --max-cost, or --max-duration is required."
        exit 1
    }

    if ($script:DryRun -and [string]::IsNullOrWhiteSpace($script:MaxRuns) -and -not [string]::IsNullOrWhiteSpace($script:MaxCost) -and [string]::IsNullOrWhiteSpace($script:MaxDuration)) {
        $script:MaxRuns = "1"
    }

    if (-not [string]::IsNullOrWhiteSpace($script:MaxRuns) -and $script:MaxRuns -notmatch "^\d+$") {
        Write-Err "Error: --max-runs must be a non-negative integer"
        exit 1
    }

    if (-not [string]::IsNullOrWhiteSpace($script:MaxCost) -and -not (Is-PositiveNumber $script:MaxCost)) {
        Write-Err "Error: --max-cost must be a positive number"
        exit 1
    }

    if (-not [string]::IsNullOrWhiteSpace($script:CodexInputCostPerMillion) -and -not (Is-PositiveNumber $script:CodexInputCostPerMillion)) {
        Write-Err "Error: --codex-input-cost-per-million must be a positive number"
        exit 1
    }

    if (-not [string]::IsNullOrWhiteSpace($script:CodexOutputCostPerMillion) -and -not (Is-PositiveNumber $script:CodexOutputCostPerMillion)) {
        Write-Err "Error: --codex-output-cost-per-million must be a positive number"
        exit 1
    }

    if (-not [string]::IsNullOrWhiteSpace($script:CodexCachedInputCostPerMillion) -and -not (Is-NonNegativeNumber $script:CodexCachedInputCostPerMillion)) {
        Write-Err "Error: --codex-cached-input-cost-per-million must be a non-negative number"
        exit 1
    }

    if (($script:AgentProvider -eq "codex" -or (-not [string]::IsNullOrWhiteSpace($script:ReviewPrompt) -and $script:ReviewProvider -eq "codex")) -and -not [string]::IsNullOrWhiteSpace($script:MaxCost)) {
        if ([string]::IsNullOrWhiteSpace($script:CodexInputCostPerMillion) -or [string]::IsNullOrWhiteSpace($script:CodexOutputCostPerMillion)) {
            Write-Err "Error: Codex CLI does not report USD cost. Use --codex-input-cost-per-million and --codex-output-cost-per-million with --max-cost."
            exit 1
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($script:MaxDuration)) {
        try {
            $script:MaxDuration = [string](Parse-Duration $script:MaxDuration)
        } catch {
            Write-Err "Error: --max-duration must be a valid duration, e.g. 2h, 30m, 1h30m, 90s"
            exit 1
        }
    }

    if ($script:MergeStrategy -notin @("squash", "merge", "rebase")) {
        Write-Err "Error: --merge-strategy must be one of: squash, merge, rebase"
        exit 1
    }

    if ($script:CompletionThreshold -lt 1) {
        Write-Err "Error: --completion-threshold must be a positive integer"
        exit 1
    }

    if ($script:EnableCommits) {
        if ([string]::IsNullOrWhiteSpace($script:GitHubOwner) -or [string]::IsNullOrWhiteSpace($script:GitHubRepo)) {
            $detected = Detect-GitHubRepo
            if ($null -ne $detected) {
                if ([string]::IsNullOrWhiteSpace($script:GitHubOwner)) { $script:GitHubOwner = $detected.Owner }
                if ([string]::IsNullOrWhiteSpace($script:GitHubRepo)) { $script:GitHubRepo = $detected.Repo }
            }
        }

        if (-not $script:DisableBranches) {
            if ([string]::IsNullOrWhiteSpace($script:GitHubOwner) -or [string]::IsNullOrWhiteSpace($script:GitHubRepo)) {
                Write-Err "Error: GitHub owner and repo are required for PR automation. Use --owner/--repo or run from a GitHub repository."
                exit 1
            }
        }
    }
}

function Validate-Requirements {
    Require-Command (Get-AgentCommand $script:AgentProvider) (Get-AgentInstallUrl $script:AgentProvider)
    if (-not [string]::IsNullOrWhiteSpace($script:ReviewPrompt) -and -not [string]::IsNullOrWhiteSpace($script:ReviewProvider)) {
        Require-Command (Get-AgentCommand $script:ReviewProvider) (Get-AgentInstallUrl $script:ReviewProvider)
    }
    Require-Command "git" "https://git-scm.com/download/win"
    if ($script:EnableCommits -and -not $script:DisableBranches) {
        Require-Command "gh" "https://cli.github.com"
    }
}

function Convert-JsonLines {
    param([string]$Text)

    $records = [System.Collections.Generic.List[object]]::new()
    foreach ($line in ($Text -split "\r?\n")) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try {
            [void]$records.Add(($line | ConvertFrom-Json))
        } catch {
            # Provider output can contain non-JSON noise; ignore it here and let
            # exit-code handling produce diagnostics if the command failed.
        }
    }
    return $records.ToArray()
}

function Get-RecordValue {
    param(
        [object]$Record,
        [string]$Name
    )
    if ($null -eq $Record) { return $null }
    $property = $Record.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Get-AgentResultText {
    param([object[]]$Records)

    $parts = [System.Collections.Generic.List[string]]::new()
    foreach ($record in $Records) {
        $type = Get-RecordValue $record "type"
        if ($script:AgentProvider -eq "claude" -and $type -eq "result") {
            $result = Get-RecordValue $record "result"
            if ($result) { [void]$parts.Add([string]$result) }
        } elseif ($script:AgentProvider -eq "codex" -and $type -eq "item.completed") {
            $item = Get-RecordValue $record "item"
            if ((Get-RecordValue $item "type") -eq "agent_message") {
                $text = Get-RecordValue $item "text"
                if ($text) { [void]$parts.Add([string]$text) }
            }
        }
    }
    return ($parts -join "`n")
}

function Write-AgentDisplay {
    param([object[]]$Records, [string]$IterationDisplay)

    foreach ($record in $Records) {
        $type = Get-RecordValue $record "type"
        if ($script:AgentProvider -eq "claude" -and $type -eq "assistant") {
            $message = Get-RecordValue $record "message"
            $content = Get-RecordValue $message "content"
            foreach ($item in @($content)) {
                if ((Get-RecordValue $item "type") -eq "text") {
                    $text = Get-RecordValue $item "text"
                    if ($text) {
                        foreach ($line in ([string]$text -split "\r?\n")) {
                            Write-Err "   $IterationDisplay $line"
                        }
                    }
                }
            }
        } elseif ($script:AgentProvider -eq "codex" -and $type -eq "item.completed") {
            $item = Get-RecordValue $record "item"
            if ((Get-RecordValue $item "type") -eq "agent_message") {
                $text = Get-RecordValue $item "text"
                if ($text) {
                    foreach ($line in ([string]$text -split "\r?\n")) {
                        Write-Err "   $IterationDisplay $line"
                    }
                }
            }
        }
    }
}

function Get-AgentCost {
    param([object[]]$Records)

    if ($script:AgentProvider -eq "claude") {
        if ($Records.Count -eq 0) { return $null }
        $last = $Records[-1]
        $cost = Get-RecordValue $last "total_cost_usd"
        if ($null -ne $cost) { return [double]$cost }
        return $null
    }

    if ($script:AgentProvider -eq "codex") {
        if ([string]::IsNullOrWhiteSpace($script:CodexInputCostPerMillion) -or [string]::IsNullOrWhiteSpace($script:CodexOutputCostPerMillion)) {
            return $null
        }
        $inputRate = [double]::Parse($script:CodexInputCostPerMillion, [Globalization.CultureInfo]::InvariantCulture)
        $outputRate = [double]::Parse($script:CodexOutputCostPerMillion, [Globalization.CultureInfo]::InvariantCulture)
        $cachedRate = if ([string]::IsNullOrWhiteSpace($script:CodexCachedInputCostPerMillion)) { $inputRate } else { [double]::Parse($script:CodexCachedInputCostPerMillion, [Globalization.CultureInfo]::InvariantCulture) }

        $inputTokens = 0
        $cachedInputTokens = 0
        $outputTokens = 0
        foreach ($record in $Records) {
            if ((Get-RecordValue $record "type") -eq "turn.completed") {
                $usage = Get-RecordValue $record "usage"
                $inputTokens += [int]((Get-RecordValue $usage "input_tokens") ?? 0)
                $cachedInputTokens += [int]((Get-RecordValue $usage "cached_input_tokens") ?? 0)
                $outputTokens += [int]((Get-RecordValue $usage "output_tokens") ?? 0)
            }
        }

        return (($inputTokens - $cachedInputTokens) * $inputRate + $cachedInputTokens * $cachedRate + $outputTokens * $outputRate) / 1000000
    }

    return $null
}

function Test-AgentSuccess {
    param([object[]]$Records, [ref]$ErrorCode)

    if ($Records.Count -eq 0) {
        $ErrorCode.Value = "invalid_json"
        return $false
    }

    if ($script:AgentProvider -eq "claude") {
        $last = $Records[-1]
        if ((Get-RecordValue $last "is_error") -eq $true) {
            $ErrorCode.Value = "claude_error"
            return $false
        }
        return $true
    }

    if ($script:AgentProvider -eq "codex") {
        $hasCompletedTurn = $false
        foreach ($record in $Records) {
            $type = Get-RecordValue $record "type"
            if ($type -eq "error" -or $type -eq "turn.failed") {
                $ErrorCode.Value = "codex_error"
                return $false
            }
            if ($type -eq "turn.completed") {
                $hasCompletedTurn = $true
            }
        }
        if (-not $hasCompletedTurn) {
            $ErrorCode.Value = "codex_incomplete"
            return $false
        }
        return $true
    }

    $ErrorCode.Value = "unsupported_provider"
    return $false
}

function Get-JsonError {
    param([object[]]$Records)

    if ($script:AgentProvider -eq "claude" -and $Records.Count -gt 0) {
        $last = $Records[-1]
        if ((Get-RecordValue $last "is_error") -eq $true) {
            $result = Get-RecordValue $last "result"
            if ($result) { return [string]$result }
        }
    }

    if ($script:AgentProvider -eq "codex") {
        for ($index = $Records.Count - 1; $index -ge 0; $index--) {
            $record = $Records[$index]
            $type = Get-RecordValue $record "type"
            if ($type -eq "error" -or $type -eq "turn.failed") {
                $message = Get-RecordValue $record "message"
                if ($message) { return [string]$message }
                $errorValue = Get-RecordValue $record "error"
                if ($errorValue) { return [string]$errorValue }
            }
        }
    }

    return ""
}

function Invoke-AgentIteration {
    param(
        [string]$PromptText,
        [string]$IterationDisplay,
        [string]$Provider = $script:AgentProvider
    )

    $previousProvider = $script:AgentProvider
    $script:AgentProvider = $Provider
    try {
        $displayName = Get-AgentDisplayName
        if ($script:DryRun) {
            Write-Err "(DRY RUN) Would run $displayName with prompt: $PromptText"
            if ($script:AgentProvider -eq "codex") {
                $records = @()
                $records += @(Convert-JsonLines '{"type":"item.completed","item":{"type":"agent_message","text":"This is a simulated response from Codex CLI."}}')
                $records += @(Convert-JsonLines '{"type":"turn.completed","usage":{"input_tokens":0,"cached_input_tokens":0,"output_tokens":0}}')
            } else {
                $records = @(Convert-JsonLines '{"type":"result","is_error":false,"result":"This is a simulated response from Claude Code.","total_cost_usd":0}')
            }
            return [pscustomobject]@{ Success = $true; ExitCode = 0; Records = @($records); Error = "" }
        }

        if ($script:AgentProvider -eq "codex") {
            $arguments = @("exec") + $script:CodexFlags + @("-C", (Get-Location).Path) + @($script:ExtraAgentFlags) + @($PromptText)
            $result = Invoke-ExternalCommand "codex" $arguments
        } else {
            $arguments = @("-p", $PromptText) + $script:ClaudeFlags + @($script:ExtraAgentFlags)
            $result = Invoke-ExternalCommand "claude" $arguments
        }

        if (-not [string]::IsNullOrWhiteSpace($result.StdErr)) {
            Write-Err $result.StdErr.TrimEnd()
        }

        $records = @(Convert-JsonLines $result.StdOut)
        Write-AgentDisplay $records $IterationDisplay

        if ($result.ExitCode -ne 0) {
            $jsonError = Get-JsonError $records
            $errorMessage = if (-not [string]::IsNullOrWhiteSpace($result.StdErr)) {
                $result.StdErr.Trim()
            } elseif (-not [string]::IsNullOrWhiteSpace($jsonError)) {
                $jsonError
            } else {
                "$displayName exited with code $($result.ExitCode) but produced no error output"
            }
            return [pscustomobject]@{ Success = $false; ExitCode = $result.ExitCode; Records = @($records); Error = $errorMessage }
        }

        $parseError = ""
        if (-not (Test-AgentSuccess $records ([ref]$parseError))) {
            return [pscustomobject]@{ Success = $false; ExitCode = 0; Records = @($records); Error = $parseError }
        }

        return [pscustomobject]@{ Success = $true; ExitCode = 0; Records = @($records); Error = "" }
    } finally {
        $script:AgentProvider = $previousProvider
    }
}

function Invoke-AgentQuiet {
    param([string]$PromptText)

    if ($script:DryRun) {
        Write-Err "(DRY RUN) Would run quiet agent prompt: $PromptText"
        return $true
    }

    if ($script:AgentProvider -eq "codex") {
        $arguments = @("exec") + $script:CodexFlags + @("-C", (Get-Location).Path) + @($script:ExtraAgentFlags) + @($PromptText)
        $result = Invoke-ExternalCommand "codex" $arguments
    } else {
        $arguments = @("-p", $PromptText, "--allowedTools", "Bash(git)", "--dangerously-skip-permissions") + @($script:ExtraAgentFlags)
        $result = Invoke-ExternalCommand "claude" $arguments
    }

    if ($result.ExitCode -ne 0) {
        if (-not [string]::IsNullOrWhiteSpace($result.StdErr)) {
            Write-Err $result.StdErr.TrimEnd()
        }
        return $false
    }
    return $true
}

function Render-NotesInstruction {
    if (Test-Path $script:NotesFile) {
        return "Update the ``$($script:NotesFile)`` file with relevant context for the next iteration. Add new notes and remove outdated information to keep it current and useful."
    }
    return "Create a ``$($script:NotesFile)`` file with relevant context and instructions for the next iteration."
}

function Build-IterationPrompt {
    $workflow = $script:PromptWorkflowContext.Replace("COMPLETION_SIGNAL_PLACEHOLDER", $script:CompletionSignal)
    return @"
$workflow

$($script:Prompt)

## ITERATION NOTES

$(Render-NotesInstruction)$($script:PromptNotesGuidelines)
"@
}

function Build-ReviewerPrompt {
    return @"
$($script:PromptReviewerContext)

## USER REVIEW INSTRUCTIONS

$($script:ReviewPrompt)
"@
}

function Get-IterationDisplay {
    param([int]$IterationNumber, [int]$ExtraIterations)
    if ([string]::IsNullOrWhiteSpace($script:MaxRuns) -or [int]$script:MaxRuns -eq 0) {
        return "($IterationNumber)"
    }
    $total = [int]$script:MaxRuns + $ExtraIterations
    return "($IterationNumber/$total)"
}

function New-IterationBranch {
    param([string]$IterationDisplay, [int]$IterationNumber)

    $timestamp = Get-Date -Format "yyyy-MM-dd-HHmmss"
    $suffix = [Guid]::NewGuid().ToString("N").Substring(0, 8)
    $branchName = "$($script:GitBranchPrefix)iteration-$IterationNumber/$timestamp-$suffix"

    Write-Err "$IterationDisplay Creating branch: $branchName"
    if ($script:DryRun) {
        Write-Err "   (DRY RUN) Would create branch $branchName"
        return $branchName
    }

    $result = Invoke-Git @("checkout", "-b", $branchName)
    if ($result.ExitCode -ne 0) {
        Write-Err $result.StdErr.TrimEnd()
        throw "Failed to create branch"
    }
    return $branchName
}

function Test-HasGitChanges {
    $status = Invoke-Git @("status", "--porcelain")
    if ($status.ExitCode -ne 0) { return $false }
    return -not [string]::IsNullOrWhiteSpace($status.StdOut)
}

function Commit-Changes {
    param([string]$IterationDisplay)

    if (-not (Test-HasGitChanges)) {
        Write-Err "$IterationDisplay No changes to commit"
        return $false
    }

    Write-Err "$IterationDisplay Committing changes..."
    if (-not (Invoke-AgentQuiet $script:PromptCommitMessage)) {
        Write-Err "$IterationDisplay Failed to commit changes"
        return $false
    }

    if (-not $script:DryRun -and (Test-HasGitChanges)) {
        Write-Err "$IterationDisplay Commit command ran but changes still remain"
        return $false
    }

    Write-Err "$IterationDisplay Changes committed"
    return $true
}

function Wait-ForPrChecks {
    param(
        [string]$PrNumber,
        [string]$IterationDisplay
    )

    if ($script:DryRun) {
        Write-Err "$IterationDisplay (DRY RUN) Would wait for PR checks"
        return $true
    }

    for ($attempt = 1; $attempt -le 180; $attempt++) {
        Write-Err "$IterationDisplay Checking PR status ($attempt/180)..."
        $result = Invoke-Gh @("pr", "view", $PrNumber, "--repo", "$($script:GitHubOwner)/$($script:GitHubRepo)", "--json", "mergeStateStatus,reviewDecision,statusCheckRollup")
        if ($result.ExitCode -ne 0) {
            Write-Err $result.StdErr.TrimEnd()
            Start-Sleep -Seconds 10
            continue
        }

        $data = $result.StdOut | ConvertFrom-Json
        $checks = @($data.statusCheckRollup)
        $pending = 0
        $failed = 0
        foreach ($check in $checks) {
            $status = Get-RecordValue $check "status"
            $conclusion = Get-RecordValue $check "conclusion"
            if ($status -and $status -ne "COMPLETED") { $pending++ }
            if ($conclusion -and $conclusion -notin @("SUCCESS", "NEUTRAL", "SKIPPED")) { $failed++ }
        }

        if ($failed -gt 0) {
            Write-Err "$IterationDisplay PR checks failed"
            return $false
        }
        if ($pending -eq 0 -and (Get-RecordValue $data "reviewDecision") -ne "CHANGES_REQUESTED") {
            Write-Err "$IterationDisplay All PR checks and reviews passed"
            return $true
        }

        Start-Sleep -Seconds 10
    }

    Write-Err "$IterationDisplay Timed out waiting for PR checks"
    return $false
}

function Complete-BranchPr {
    param(
        [string]$IterationDisplay,
        [string]$BranchName,
        [string]$MainBranch
    )

    if (-not (Commit-Changes $IterationDisplay)) {
        return $false
    }

    if ($script:DryRun) {
        Write-Err "$IterationDisplay (DRY RUN) Would push branch, create PR, wait for checks, and merge"
        return $true
    }

    $push = Invoke-Git @("push", "-u", "origin", $BranchName)
    if ($push.ExitCode -ne 0) {
        Write-Err $push.StdErr.TrimEnd()
        return $false
    }

    $commitMessage = (Invoke-Git @("log", "-1", "--format=%B", $BranchName)).StdOut.Trim()
    $lines = @($commitMessage -split "\r?\n")
    $title = if ($lines.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($lines[0])) { $lines[0] } else { "Continuous Claude iteration" }
    $body = if ($lines.Count -gt 2) { ($lines[2..($lines.Count - 1)] -join "`n") } else { "" }

    $pr = Invoke-Gh @("pr", "create", "--repo", "$($script:GitHubOwner)/$($script:GitHubRepo)", "--title", $title, "--body", $body, "--base", $MainBranch)
    if ($pr.ExitCode -ne 0) {
        Write-Err $pr.StdErr.TrimEnd()
        return $false
    }

    if ($pr.StdOut -notmatch "/pull/(\d+)") {
        Write-Err "$IterationDisplay Could not determine PR number from gh output"
        return $false
    }
    $prNumber = $matches[1]

    if (-not (Wait-ForPrChecks $prNumber $IterationDisplay)) {
        [void](Invoke-Gh @("pr", "close", $prNumber, "--repo", "$($script:GitHubOwner)/$($script:GitHubRepo)", "--delete-branch"))
        return $false
    }

    $mergeFlag = "--$($script:MergeStrategy)"
    $merge = Invoke-Gh @("pr", "merge", $prNumber, "--repo", "$($script:GitHubOwner)/$($script:GitHubRepo)", $mergeFlag, "--delete-branch")
    if ($merge.ExitCode -ne 0) {
        Write-Err $merge.StdErr.TrimEnd()
        return $false
    }

    [void](Invoke-Git @("checkout", $MainBranch))
    [void](Invoke-Git @("pull", "--ff-only"))
    [void](Invoke-Git @("branch", "-D", $BranchName))
    Write-Err "$IterationDisplay PR #$prNumber merged: $title"
    return $true
}

function Invoke-SingleIteration {
    param(
        [int]$IterationNumber,
        [int]$ExtraIterations
    )

    $iterationDisplay = Get-IterationDisplay $IterationNumber $ExtraIterations
    Write-Err "$iterationDisplay Starting iteration..."

    $mainBranch = "main"
    $currentBranch = Invoke-Git @("rev-parse", "--abbrev-ref", "HEAD")
    if ($currentBranch.ExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($currentBranch.StdOut)) {
        $mainBranch = $currentBranch.StdOut.Trim()
    }

    $branchName = ""
    if ($script:EnableCommits -and -not $script:DisableBranches) {
        $branchName = New-IterationBranch $iterationDisplay $IterationNumber
    }

    $displayName = Get-AgentDisplayName
    Write-Err "$iterationDisplay Running $displayName..."
    $result = Invoke-AgentIteration (Build-IterationPrompt) $iterationDisplay
    if (-not $result.Success) {
        Write-Err "$iterationDisplay Error: $($result.Error)"
        if (-not [string]::IsNullOrWhiteSpace($branchName) -and -not $script:DryRun) {
            [void](Invoke-Git @("checkout", $mainBranch))
            [void](Invoke-Git @("branch", "-D", $branchName))
        }
        return [pscustomobject]@{ Success = $false; Completed = $false; Cost = 0.0 }
    }

    $cost = Get-AgentCost $result.Records
    if ($null -ne $cost) {
        Write-Err ("$iterationDisplay Iteration cost: {0:C3}" -f $cost)
    } else {
        $cost = 0.0
    }

    if (-not [string]::IsNullOrWhiteSpace($script:ReviewPrompt)) {
        $reviewProvider = if ([string]::IsNullOrWhiteSpace($script:ReviewProvider)) { $script:AgentProvider } else { $script:ReviewProvider }
        $reviewDisplay = Get-AgentDisplayName $reviewProvider
        Write-Err "$iterationDisplay Running reviewer pass with $reviewDisplay..."
        $review = Invoke-AgentIteration (Build-ReviewerPrompt) $iterationDisplay $reviewProvider
        if (-not $review.Success) {
            Write-Err "$iterationDisplay Reviewer failed: $($review.Error)"
            return [pscustomobject]@{ Success = $false; Completed = $false; Cost = $cost }
        }
        $previousProvider = $script:AgentProvider
        $script:AgentProvider = $reviewProvider
        try {
            $reviewCost = Get-AgentCost $review.Records
        } finally {
            $script:AgentProvider = $previousProvider
        }
        if ($null -ne $reviewCost) {
            $cost += $reviewCost
            Write-Err ("$iterationDisplay Reviewer cost: {0:C3}" -f $reviewCost)
        }
        Write-Err "$iterationDisplay Reviewer pass completed"
    }

    $text = Get-AgentResultText $result.Records
    $completed = $text -like "*$($script:CompletionSignal)*"
    Write-Err "$iterationDisplay Work completed"

    if (-not $script:EnableCommits) {
        Write-Err "$iterationDisplay Skipping commits (--disable-commits flag set)"
    } elseif ($script:DisableBranches) {
        if (-not (Commit-Changes $iterationDisplay)) {
            return [pscustomobject]@{ Success = $false; Completed = $completed; Cost = $cost }
        }
    } else {
        if (-not (Complete-BranchPr $iterationDisplay $branchName $mainBranch)) {
            return [pscustomobject]@{ Success = $false; Completed = $completed; Cost = $cost }
        }
    }

    return [pscustomobject]@{ Success = $true; Completed = $completed; Cost = $cost }
}

function Main {
    Parse-Arguments @($args)
    Validate-Arguments
    Validate-Requirements

    $startTime = if (-not [string]::IsNullOrWhiteSpace($script:MaxDuration)) { Get-Date } else { $null }
    $totalCost = 0.0
    $successfulIterations = 0
    $completionSignals = 0
    $errors = 0
    $extraIterations = 0
    $iteration = 1

    while ($true) {
        $shouldContinue = $false
        if ([string]::IsNullOrWhiteSpace($script:MaxRuns) -or [int]$script:MaxRuns -eq 0 -or $successfulIterations -lt [int]$script:MaxRuns) {
            $shouldContinue = $true
        }
        if (-not [string]::IsNullOrWhiteSpace($script:MaxCost) -and $totalCost -ge [double]::Parse($script:MaxCost, [Globalization.CultureInfo]::InvariantCulture)) {
            $shouldContinue = $false
        }
        if ($null -ne $startTime -and ((Get-Date) - $startTime).TotalSeconds -ge [int]$script:MaxDuration) {
            Write-Err "Maximum duration reached ($(Format-Duration ([int]((Get-Date) - $startTime).TotalSeconds)))"
            $shouldContinue = $false
        }
        if ($completionSignals -ge $script:CompletionThreshold) {
            $shouldContinue = $false
        }
        if (-not $shouldContinue) { break }

        $iterationResult = Invoke-SingleIteration $iteration $extraIterations
        if (-not $iterationResult.Success) {
            $errors++
            $extraIterations++
            if ($errors -ge 3) {
                Write-Err "Fatal: 3 consecutive errors occurred. Exiting."
                exit 1
            }
        } else {
            $errors = 0
            if ($extraIterations -gt 0) { $extraIterations-- }
            $successfulIterations++
            $totalCost += [double]$iterationResult.Cost
            if ($iterationResult.Completed) {
                $completionSignals++
                Write-Err "Completion signal detected ($completionSignals/$($script:CompletionThreshold))"
            } else {
                $completionSignals = 0
            }
        }

        $iteration++
        Start-Sleep -Seconds 1
    }

    if ($completionSignals -ge $script:CompletionThreshold) {
        Write-Err "Project completed! Detected completion signal $completionSignals times in a row."
    } else {
        Write-Err ("Done with total cost: {0:C3}" -f $totalCost)
    }
}

Main @args
