<h1><img width="512" height="294" alt="Continuous Claude" src="https://github.com/user-attachments/assets/26878379-6cff-4803-a50d-c1e3f9455f55" /></h1>

<details data-embed="anandchowdhary.com" data-title="Continuous Claude" data-summary="Run Claude Code in a loop repeatedly to do large projects">
  <summary>Automated workflow that orchestrates Claude Code in a continuous loop, autonomously creating PRs, waiting for checks, and merging - so multi-step projects complete while you sleep.</summary>

This all started because I was contractually obligated to write unit tests for a codebase with hundreds of thousands of lines of code and go from 0% to 80%+ coverage in the next few weeks - seems like something Claude should do. So I built [Continuous Claude](https://github.com/AnandChowdhary/continuous-claude), a CLI tool to run Claude Code in a loop that maintains a persistent context across multiple iterations.

Current AI coding tools tend to halt after completing a task once they think the job is done and they don't really have an opportunity for self-criticism or further improvement. And this one-shot pattern then makes it difficult to tackle larger projects. So in contrast to running Claude Code "as is" (which provides help in isolated bursts), what you want is to run Claude code for a long period of time without exhausting the context window.

Turns out, it's as simple as just running Claude Code in a continuous loop - but drawing inspiration from CI/CD practices and persistent agents - you can take it a step further by running it on a schedule or through triggers and connecting it to your GitHub pull requests workflow. And by persisting relevant context and results from one iteration to the next, this process ensures that knowledge gained in earlier steps is not lost, which is currently not possible in stateless AI queries and something you have to slap on top by setting up markdown files to store progress and context engineer accordingly.

## While + git + persistence

The first version of this idea was a simple while loop:

```bash
while true; do
  claude --dangerously-skip-permissions "Increase test coverage [...] write notes for the next developer in TASKS.md, [etc.]"
  sleep 1
done
```

to which my friend [Namanyay](https://nmn.gl) of Giga AI said "genius and hilarious". I spent all of Saturday building the rest of the tooling. Now, the Bash script acts as the conductor, repeatedly invoking Claude Code with the appropriate prompts and handling the surrounding tooling. For each iteration, the script:

1. Creates a new branch and runs Claude Code to generate a commit
2. Pushes changes and creates a pull request using GitHub's CLI
3. Monitors CI checks and reviews via `gh pr checks`
4. Merges on success or discards on failure
5. Pulls the updated main branch, cleans up, and repeats

When an iteration fails, it closes the PR and discards the work. This is wasteful, but with knowledge of test failures, the next attempt can try something different. Because it piggybacks on GitHub's existing workflows, you get code review and preview environments without additional work - if your repo requires code owner approval or specific CI checks, it will respect those constraints.

## Context continuity

A shared markdown file serves as external memory where Claude records what it has done and what should be done next. Without specific prompting instructions, it would create verbose logs that harm more than help - the intent is to keep notes as a clean handoff package between runs. So the key instruction to the model is: "This is part of a continuous development loop... you don't need to complete the entire goal in one iteration, just make meaningful progress on one thing, then leave clear notes for the next iteration... think of it as a relay race where you're passing the baton."

Here's an actual production example: the previous iteration ended with "Note: tried adding tests to X but failed on edge case, need to handle null input in function Y" and the very next Claude invocation saw that and prioritized addressing it. A single small file reduces context drift, where it might forget earlier reasoning and go in circles.

What's fascinating is how the markdown file enables self-improvement. A simple "increase coverage" from the user becomes "run coverage, find files with low coverage, do one at a time" as the system teaches itself through iteration and keeps track of its own progress.

## Continuous AI

My friends at GitHub Next have been exploring this idea in their project [Continuous AI](https://githubnext.com/projects/continuous-ai/) and I shared Continuous Claude with them.

One compelling idea from the team was running specialized agents simultaneously - one for development, another for tests, a third for refactoring. While this could divide and conquer complex tasks more efficiently, it possibly introduces coordination challenges. I'm trying a similar approach for adding tests in different parts of a monorepository at the same time.

The [agentics project](https://github.com/githubnext/agentics) combines an explicit research phase with pre-build steps to ensure the software is restored before agentic work begins. "The fault-tolerance of Agent in a Loop is really important. If things go wrong it just hits the resource limits and tries again. Or the user just throws the generated PR away if it's not helpful. It's so much better than having a frustrated user trying to guide an agent that's gone down a wrong path," said GitHub Next Principal Researcher [Don Syme](https://github.com/dsyme).

It reminded me of a concept in economics/mathematics called "radiation of probabilities" (I know, pretty far afield, but bear with me) and here, each agent run is like a random particle - not analyzed individually, but the general direction emerges from the distribution. Each run can even be thought of as idempotent: if GitHub Actions kills the process after six hours, you only lose some dirty files that the next agent will pick up anyway. All you care about is that it's moving in the right direction in general, for example increasing test coverage, rather than what an individual agent does. This wasteful-but-effective approach becomes viable as token costs approach zero, similar to Cursor's multiple agents.

## Dependabot on steroids

Tools like Dependabot handle dependency updates, but Continuous Claude can also fix post-update breaking changes using release notes. You could run a GitHub Actions workflow every morning that checks for updates and continuously fixes issues until all tests pass.

Large refactoring tasks become manageable: breaking a monolith into modules, modernizing callbacks to async/await, or updating to new style guidelines. It could perform a series of 20 pull requests over a weekend, each doing part of the refactor with full CI validation. There's a whole class of tasks that are too mundane for humans but still require attention to avoid breaking the build.

The model mirrors human development practices. Claude Code handles the grunt work, but humans remain in the loop through familiar mechanisms like PR reviews. Download the CLI from GitHub to get started!

</details>

## ⚙️ How it works

Using Claude Code or Codex CLI to drive iterative development, this script fully automates the PR lifecycle from code changes through to merged commits:

- The selected AI coding agent runs in a loop based on your prompt
- All changes are committed to a new branch
- A new pull request is created
- It waits for all required PR checks and code reviews to complete
- Once checks pass and reviews are approved, the PR is merged
- This process repeats until your task is complete
- A `SHARED_TASK_NOTES.md` file maintains continuity by passing context between iterations, enabling seamless handoffs across AI and human developers
- If multiple agents decide that the project is complete, the loop will stop early.

## 🚀 Quick start

### Installation

Install with a single command:

```bash
curl -fsSL https://raw.githubusercontent.com/AnandChowdhary/continuous-claude/main/install.sh | bash
```

This will:

- Install `continuous-claude` to `~/.local/bin`
- Check for required dependencies
- Guide you through adding it to your PATH if needed

On Windows with PowerShell 7:

```powershell
irm https://raw.githubusercontent.com/AnandChowdhary/continuous-claude/main/install.ps1 | iex
```

This installs the native PowerShell runner as `continuous-claude.ps1`, so Windows users can run Continuous Claude without WSL or Git Bash:

```powershell
pwsh ~/.local/bin/continuous-claude.ps1 --prompt "add unit tests until all code is covered" --max-runs 5
```

The PowerShell runner supports the core loop, Claude/Codex providers, reviewer passes, shared notes, duration/cost limits, local commits, and GitHub PR creation/merge. Worktree management, self-update, and automatic CI/comment retry workflows are still Bash-runner only.

### Manual installation

If you prefer to install manually:

```bash
# Download the script
curl -fsSL https://raw.githubusercontent.com/AnandChowdhary/continuous-claude/main/continuous_claude.sh -o continuous-claude

# Make it executable
chmod +x continuous-claude

# Move to a directory in your PATH
sudo mv continuous-claude /usr/local/bin/
```

For PowerShell:

```powershell
Invoke-WebRequest https://raw.githubusercontent.com/AnandChowdhary/continuous-claude/main/continuous_claude.ps1 -OutFile continuous-claude.ps1
pwsh ./continuous-claude.ps1 --help
```

To uninstall `continuous-claude`:

```bash
rm ~/.local/bin/continuous-claude
# or if you installed to /usr/local/bin:
sudo rm /usr/local/bin/continuous-claude
```

```powershell
rm ~/.local/bin/continuous-claude.ps1
```

### Prerequisites

Before using `continuous-claude`, you need:

1. **An AI coding agent CLI**:
   - **[Claude Code CLI](https://code.claude.com)** - Authenticate with `claude auth`
   - **[Codex CLI](https://help.openai.com/en/articles/11096431)** - Authenticate with `codex login`
2. **[GitHub CLI](https://cli.github.com)** - Authenticate with `gh auth login`
3. **jq** - Install with `brew install jq` (macOS) or `apt-get install jq` (Linux). The PowerShell runner uses native JSON parsing and does not require `jq`.

### Usage

```bash
# Run with your prompt, max runs, and GitHub repo (owner and repo auto-detected from git remote)
continuous-claude --prompt "add unit tests until all code is covered" --max-runs 5

# Run the same loop with Codex CLI instead of Claude Code
continuous-claude --provider codex --prompt "add unit tests until all code is covered" --max-runs 5

# Native Windows PowerShell runner
pwsh ~/.local/bin/continuous-claude.ps1 --prompt "add unit tests until all code is covered" --max-runs 5

# Or explicitly specify the owner and repo
continuous-claude --prompt "add unit tests until all code is covered" --max-runs 5 --owner AnandChowdhary --repo continuous-claude

# Or run with a cost budget instead
continuous-claude --prompt "add unit tests until all code is covered" --max-cost 10.00

# Or run for a specific duration (time-boxed bursts)
continuous-claude --prompt "add unit tests until all code is covered" --max-duration 2h
```

## 🎯 Flags

- `-p, --prompt`: Task prompt for the selected AI coding agent (required)
- `--provider`: AI coding provider, either `claude` or `codex` (default: `claude`)
- `-m, --max-runs`: Maximum number of iterations, use `0` for infinite (required unless --max-cost or --max-duration is provided)
- `--max-cost`: Maximum USD to spend (required unless --max-runs or --max-duration is provided)
- `--max-duration`: Maximum duration to run (e.g., `2h`, `30m`, `1h30m`) (required unless --max-runs or --max-cost is provided)
- `--codex-input-cost-per-million`: Input token rate used to estimate Codex cost budgets
- `--codex-output-cost-per-million`: Output token rate used to estimate Codex cost budgets
- `--codex-cached-input-cost-per-million`: Cached input token rate used to estimate Codex cost budgets (defaults to input rate)
- `--owner`: GitHub repository owner (auto-detected from git remote if not provided)
- `--repo`: GitHub repository name (auto-detected from git remote if not provided)
- `--merge-strategy`: Merge strategy: `squash`, `merge`, or `rebase` (default: `squash`)
- `--git-branch-prefix`: Prefix for git branch names (default: `continuous-claude/`)
- `--notes-file`: Path to shared task notes file (default: `SHARED_TASK_NOTES.md`)
- `--disable-commits`: Disable automatic git commits, PR creation, and merging (useful for testing)
- `--disable-branches`: Commit on current branch without creating branches or PRs
- `--worktree <name>`: Run in a git worktree for parallel execution (creates if needed)
- `--worktree-base-dir <path>`: Base directory for worktrees (default: `../continuous-claude-worktrees`)
- `--cleanup-worktree`: Remove worktree after completion
- `--list-worktrees`: List all active git worktrees and exit
- `--dry-run`: Simulate execution without making changes
- `--completion-signal <phrase>`: Phrase that agents output when entire project is complete (default: `CONTINUOUS_CLAUDE_PROJECT_COMPLETE`)
- `--completion-threshold <num>`: Number of consecutive completion signals required to stop early (default: `3`)
- `-r, --review-prompt [text]`: Run a reviewer pass after each iteration to validate changes. If you omit the text, Continuous Claude uses a comprehensive default review prompt that reviews the diff, runs available checks, simplifies changed code, and verifies the app where relevant.
- `--command-retry-max <number>`: Maximum attempts for transient commit/push/PR-create commands before starting a new iteration (default: `3`)
- `--command-retry-base-delay <seconds>`: Initial retry delay in seconds for transient commands, doubled after each failed attempt (default: `5`)

Any additional flags you provide that are not recognized by `continuous-claude` will be automatically forwarded to the selected provider command. You can also use `--` to explicitly stop parsing `continuous-claude` options and forward the rest to the provider CLI.

Codex CLI currently reports token usage but not USD cost. When using `--provider codex` with `--max-cost`, provide explicit token rates with `--codex-input-cost-per-million` and `--codex-output-cost-per-million` so `continuous-claude` can enforce the budget from Codex usage events.

## 📝 Examples

```bash
# Run 5 iterations (owner and repo auto-detected from git remote)
continuous-claude -p "improve code quality" -m 5

# Run 5 iterations with Codex CLI
continuous-claude --provider codex -p "improve code quality" -m 5

# Run infinitely until stopped
continuous-claude -p "add unit tests until all code is covered" -m 0

# Run until $10 budget exhausted
continuous-claude -p "add documentation" --max-cost 10.00

# Run Codex until a $10 estimated budget is exhausted
continuous-claude --provider codex -p "add documentation" --max-cost 10.00 \
  --codex-input-cost-per-million 1.25 --codex-output-cost-per-million 10.00

# Run for 2 hours (time-boxed burst)
continuous-claude -p "add unit tests" --max-duration 2h

# Run for 30 minutes
continuous-claude -p "refactor module" --max-duration 30m

# Run for 1 hour and 30 minutes
continuous-claude -p "add features" --max-duration 1h30m

# Run max 10 iterations or $5, whichever comes first
continuous-claude -p "refactor code" -m 10 --max-cost 5.00

# Combine duration and cost limits (whichever comes first)
continuous-claude -p "improve tests" --max-duration 1h --max-cost 5.00

# Use merge commits instead of squash
continuous-claude -p "add features" -m 5 --merge-strategy merge

# Use rebase strategy
continuous-claude -p "update dependencies" -m 3 --merge-strategy rebase

# Use custom branch prefix
continuous-claude -p "refactor code" -m 3 --git-branch-prefix "feature/"

# Use custom notes file
continuous-claude -p "add features" -m 5 --notes-file "PROJECT_CONTEXT.md"

# Test without creating commits or PRs
continuous-claude -p "test changes" -m 2 --disable-commits

# Commit on current branch without branches or PRs
continuous-claude -p "quick fixes" -m 3 --disable-branches

# Pass additional Claude Code CLI flags (e.g., restrict tools)
continuous-claude -p "add features" -m 3 --allowedTools "Write,Read"

# Pass additional Codex CLI flags after --
continuous-claude --provider codex -p "add features" -m 3 -- --model gpt-5.5

# Use a different model
continuous-claude -p "refactor code" -m 5 --model claude-haiku-4-5

# Enable early stopping when agents signal project completion
continuous-claude -p "add unit tests to all files" -m 50 --completion-threshold 3

# Use custom completion signal
continuous-claude -p "fix all bugs" -m 20 --completion-signal "ALL_BUGS_FIXED" --completion-threshold 2

# Use a reviewer to validate and fix changes after each iteration
continuous-claude -p "add new feature" -m 5 -r "Run npm test and npm run lint, fix any failures"

# Use the default reviewer prompt
continuous-claude -p "add new feature" -m 5 -r

# Retry transient commit/push/PR-create failures before abandoning the iteration
continuous-claude -p "add new feature" -m 5 --command-retry-max 4 --command-retry-base-delay 10

# Explicitly specify owner and repo (useful if git remote is not set up or not a GitHub repo)
continuous-claude -p "add features" -m 5 --owner myuser --repo myproject

# Check for and install updates
continuous-claude update

# An actual, production example from the author
continuous-claude -p "We are building... You should pick one thing to work on from SPEC.md, just one, and read SHARED_TASK_NOTES.md for the current status. If it's bigger than a single focused task, break it into small subtasks and only do the first one. Before you start, jot the breakdown into SHARED_TASK_NOTES.md so the next developer knows what's done, what's in flight, and what's queued. Work the one small piece end-to-end (build, test, verify it actually runs), then update SHARED_TASK_NOTES.md with where you left off, what's next, and any decisions or gotchas worth handing over. This is a relay so don't try to land the whole feature yourself. Leave the baton somewhere obvious for the next dev to grab (no need to commit or push)." -r "Review the currently changed files on this branch before I ship. Look at the diff and read everything that changed. Run the test suite, typecheck, and lint and fix anything that fails. Invoke the /simplify skill on the changed files to dedupe, extract clean abstractions where patterns repeat, and tighten naming, but don't over-abstract. Then start the dev server, drive the app with the agent-browser CLI (or whatever browser-test tooling you like), screenshot surfaces you touched, click through the golden path and edge cases, and watch the dev server logs and browser console for warnings or errors. Report back with what changed, what you simplified, test results, and a screenshot-backed walkthrough and flag anything you couldn't verify, so just make sure it's working as expected and "good" code (no need to commit or push)." -m 10
```

### Running in parallel

Use git worktrees to run multiple instances simultaneously without conflicts:

```bash
# Terminal 1 (owner and repo auto-detected)
continuous-claude -p "Add unit tests" -m 5 --worktree tests

# Terminal 2 (simultaneously)
continuous-claude -p "Add docs" -m 5 --worktree docs
```

Each instance creates its own worktree at `../continuous-claude-worktrees/<name>/`, pulls the latest changes, and runs independently. Worktrees persist for reuse.

```bash
# List worktrees
continuous-claude --list-worktrees

# Clean up after completion
continuous-claude -p "task" -m 1 --worktree temp --cleanup-worktree
```

## 📊 Example output

Here's what a successful run looks like:

```
🔄 (1/1) Starting iteration...
🌿 (1/1) Creating branch: continuous-claude/iteration-1/2025-11-15-be939873
🤖 (1/1) Running Claude Code...
📝 (1/1) Output: Perfect! I've successfully completed this iteration of the testing project. Here's what I accomplished: [...]
💰 (1/1) Cost: $0.042
✅ (1/1) Work completed
🌿 (1/1) Creating branch: continuous-claude/iteration-1/2025-11-15-be939873
💬 (1/1) Committing changes...
📦 (1/1) Changes committed on branch: continuous-claude/iteration-1/2025-11-15-be939873
📤 (1/1) Pushing branch...
🔨 (1/1) Creating pull request...
🔍 (1/1) PR #893 created, waiting 5 seconds for GitHub to set up...
🔍 (1/1) Checking PR status (iteration 1/180)...
   📊 Found 6 check(s)
   🟢 2    🟡 4    🔴 0
   👁️  Review status: None
⏳ Waiting for: checks to complete
✅ (1/1) All PR checks and reviews passed
🔀 (1/1) Merging PR #893...
📥 (1/1) Pulling latest from main...
🗑️ (1/1) Deleting local branch: continuous-claude/iteration-1/2025-11-15-be939873
✅ (1/1) PR #893 merged: Add unit tests for authentication module
🎉 Done with total cost: $0.042
```

## 📃 License

[MIT](./LICENSE) ©️ [Anand Chowdhary](https://anandchowdhary.com)
