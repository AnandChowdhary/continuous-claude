# 🔂 Continuous Claude

<details data-embed="anandchowdhary.com" data-title="Continuous Claude" data-summary="Run Claude Code in a loop repeatedly to do large projects">
  <summary>Automated workflow that orchestrates Claude Code in a continuous loop, autonomously creating PRs, waiting for checks, and merging - so multi-step projects complete while you sleep.</summary>

This all started because I was contractually obligated to write unit tests for a codebase with hundreds of thousands of lines of code and go from 0% to 80%+ coverage in the next few weeks - seems like something Claude should do. So I built Continuous Claude, a CLI tool to run Claude Code in a loop that maintains a persistent context across multiple iterations.

Current AI coding tools tend to halt after completing a task once they think the job is done and they don't really have an opportunity for self-criticism or further improvement. And this one-shot pattern then makes it difficult to tackle larger projects. So in contrast to running Claude Code "as is" (which provides help in isolated bursts), what you want is to run Claude code for a long period of time without exhausting the context window.

Turns out, it's as simple as just running Claude Code in a continuous loop - but drawing inspiration from CI/CD practices and persistent agents - you can take it a step further by running it on a schedule or through triggers and connecting it to your GitHub pull requests workflow. And by persisting relevant context and results from one iteration to the next, this process ensures that knowledge gained in earlier steps is not lost, which is currently not possible in stateless AI queries and something you have to slap on top by setting up markdown files to store progress and context engineer accordingly.

## While + git + persistence

When you have a task that is too complex to complete in a single step, for example migrating from Next.js to TanStack Start or adding documentation for a previously undocumented codebase, you need to break down the task into many small tasks (e.g., only document this one file first, then the rest of the folder, and so on). So all you need is a while loop that stops eventually, a version control and PR reviews integrations, and a persistent context mechanism.

I wrote a Bash script that acts as the conductor, repeatedly invoking Claude Code with the appropriate prompts and handling the surrounding tooling. The script accepts the prompt (task description), the maximum number of iterations to run, and repository information (owner and repo name for the GitHub integration). When started, it goes into a loop (potentially infinite) where each loop iteration corresponds to Claude attempting a unit of work towards the overall goal.

This loop runs Claude Code with the prompt that the user supplies but also explicitly tells the model: "This is part of a continuous development loop... you don't need to complete the entire goal in one iteration, just make meaningful progress on one thing, then leave clear notes for the next iteration (human or AI)... think of it as a relay race where you're passing the baton." This sets the right expectations for the model that it should aim for incremental progress, not rush to finish everything at once.

The script handles also the git operations around the code changes. For each loop, it creates a new branch, generates the commit, pushes it, and creates a pull request using GitHub's CLI. Next step is monitoring and control: it enters a time-interval loop where it periodically checks the status of CI checks and reviews on that PR using `gh pr checks` and waits for the PR to get all green statuses and required approvals. If everything looks good (tests passed, etc.), it merges the PR, then pulls the updated main branch and cleans up the local feature branch, so essentially implementing a merge queue.

Should an iteration fail, it can just close the PR, delete the branch, and disregard the work. This is indeed wasteful, but now with knowledge of the test failures, the next attempt can choose to try something different. And because it piggybacks on top of GitHub, you can combine things like code review and preview environments without any additional work, for example if the repo requires at least one code owner review or has specific CI checks that must pass, it will simply be constrained by those and will not merge until they are satisfied.

## Context continuity

It's a common practice to use a shared persistent markdown file like TASKS.md to maintain context continuity across different agents working on the same task. The MVP of this is just a single file that serves as an external memory where Claude can record what it has done and what should be done next, any new insights or mistakes, and so on.

The default prompt includes guidelines about what these notes should contain: they should be concise and action-oriented, focusing on context that will help the next step, and should not become a verbose log or include information that can be deduced from the code or test results GitHub. Without these specific prompting instructions, it would go rogue and create a really long file that harms more than helps, when the intent is to keep the notes as a clean handoff package between runs.

An actual production example I saw was that the previous iteration ended with "Note: I tried adding tests to X but they paid because of an edge case, need to handle null input in function Y" and the very next Claude invocation saw that and prioritized addressing it. I think you can definitely have a much better mechanism but I found that a single tiny file already reduces the chances of context drift, where it might forget earlier reasoning or work and go in circles.

I am not yet sure whether I want this file to be checked into the git commit history. This file serves as an external scratchpad for Claude, giving it a long-term memory that survives beyond the context window of any single invocation, so one can argue that it makes sense to have a more sophisticated system that can manage multiple tasks while tracking the changes to the living document, but I'm not sure yet. Either way, the trade-off is that the notes rely on Claude to faithfully maintain them (which I observed it generally will because of the prompting).

## Dependabot on steroids

I was thinking about what could be some other use cases for this. Tools like Renovate and Dependabot were the first to come to mind, while Continuous Code is not limited to only dependencies and also capable of fixing post-update issues. So you could run a GitHub Actions workflow that runs every morning, checks for dependency updates, and then continuously makes updates to the codebase based on the release notes of the dependency until you're all green again.

Also refactoring tasks like breaking a monolith into modules, modernizing callbacks to async/await, or updating code to new style guidelines can be done stepwise. For example, it could over a weekend perform a series of 20 pull requests, each doing part of the refactor, and each PR will have to pass all tests/CI. There's a whole class of tasks that are too mundane for us but still require attention to avoid breaking the build - can this be how we address technical debt?

In general, I think that the model of running the coding agent in a loop better mirrors human development practices and avoids the common pitfall it trying to solve everything in one go; even with plan mode, I think iterative refinement is the way to go for larger tasks. Also depending on your appetite, the system can be as human-in-the-loop as you like. Claude Code handles the grunt work of coding and iteration, but humans remain in the loop through familiar mechanisms like PR reviews and reading the markdown notes.

Continuous Claude emphasizes small, incremental changes rather than giant leaps. Download the CLI from GitHub to get started!

</details>

## ⚙️ How it works

Using Claude Code to drive iterative development, this script fully automates the PR lifecycle from code changes through to merged commits:

- Claude Code runs in a loop based on your prompt
- All changes are committed to a new branch
- A new pull request is created
- It waits for all required PR checks and code reviews to complete
- Once checks pass and reviews are approved, the PR is merged
- This process repeats until your task is complete
- A `SHARED_TASK_NOTES.md` file maintains continuity by passing context between iterations, enabling seamless handoffs across AI and human developers

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

To uninstall `continuous-claude`:

```bash
rm ~/.local/bin/continuous-claude
# or if you installed to /usr/local/bin:
sudo rm /usr/local/bin/continuous-claude
```

### Prerequisites

Before using `continuous-claude`, you need:

1. **[Claude Code CLI](https://code.claude.com)** - Authenticate with `claude auth`
2. **[GitHub CLI](https://cli.github.com)** - Authenticate with `gh auth login`
3. **jq** - Install with `brew install jq` (macOS) or `apt-get install jq` (Linux)

### Usage

```bash
# Run with your prompt, infinite max runs, and GitHub repo
continuous-claude --prompt "add unit tests until all code is covered" --max-runs 0 --owner AnandChowdhary --repo continuous-claude
```

## 🎯 Flags

- `-p, --prompt`: Task prompt for Claude Code (required)
- `-m, --max-runs`: Number of iterations, use `0` for infinite (required)
- `--owner`: GitHub repository owner (required)
- `--repo`: GitHub repository name (required)
- `--git-branch-prefix`: Prefix for git branch names (default: `continuous-claude/`)
- `--disable-commits`: Disable automatic git commits, PR creation, and merging (useful for testing)

## 📝 Examples

```bash
# Run 5 iterations
continuous-claude -p "improve code quality" -m 5 --owner AnandChowdhary --repo continuous-claude

# Run infinitely until stopped
continuous-claude -p "add unit tests until all code is covered" -m 0 --owner AnandChowdhary --repo continuous-claude

# Use custom branch prefix
continuous-claude -p "refactor code" -m 3 --owner AnandChowdhary --repo continuous-claude --git-branch-prefix "feature/"

# Test without creating commits or PRs
continuous-claude -p "test changes" -m 2 --owner AnandChowdhary --repo continuous-claude --disable-commits
```

## 📊 Example output

Here's what a successful run looks like:

```
💰 (1/1) Cost: $0.042
✅ (1/1) Work completed
🌿 (1/1) Creating branch: continuous-claude/1-1763205620
💬 (1/1) Committing changes...
📦 (1/1) Changes committed on branch: continuous-claude/1-1763205620
📤 (1/1) Pushing branch...
🔨 (1/1) Creating pull request...
🔍 (1/1) PR #3 created, waiting for checks...
✅ (1/1) No checks configured
✅ (1/1) All PR checks and reviews passed
🔀 (1/1) Merging PR #3...
📥 (1/1) Pulling latest from main...
🗑️  (1/1) Deleting local branch: continuous-claude/1-1763205620
✅ (1/1) PR merged and local branch cleaned up
🎉 Done with total cost: $0.042
```

## 📃 License

MIT ©️ [Anand Chowdhary](https://anandchowdhary.com)
