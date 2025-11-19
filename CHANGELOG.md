# CHANGELOG

## [v0.8.0] - 2025-11-19

### What's Changed

- :sparkles: Add PR branch update process (13db4cf)

**Full Changelog**: https://github.com/AnandChowdhary/continuous-claude/compare/v0.7.0...v0.8.0

### Installation

Install with a single command:

```bash
curl -fsSL https://raw.githubusercontent.com/AnandChowdhary/continuous-claude/refs/tags/v0.8.0/install.sh | bash
```

Or download the script directly:

```bash
curl -fsSL https://raw.githubusercontent.com/AnandChowdhary/continuous-claude/refs/tags/v0.8.0/continuous_claude.sh -o continuous-claude
chmod +x continuous-claude
sudo mv continuous-claude /usr/local/bin/
```

## [v0.7.0] - 2025-11-19

### What's Changed

- :white_check_mark: Add comprehensive tests for completion signal handling (a5c6234)
- :sparkles: Introduce completion signal feature to early stop project iterations (df7e912)
- :construction_worker: Add conditions to skip releases if the main script is unchanged or commits are test/CI/docs only (372e114)
- :construction_worker: Adjust markdown heading levels in generated changelog by replacing `##` with `###` in release bodies and notes. (20efb2d)

**Full Changelog**: https://github.com/AnandChowdhary/continuous-claude/compare/v0.6.4...v0.7.0

### Installation

Install with a single command:

```bash
curl -fsSL https://raw.githubusercontent.com/AnandChowdhary/continuous-claude/refs/tags/v0.7.0/install.sh | bash
```

Or download the script directly:

```bash
curl -fsSL https://raw.githubusercontent.com/AnandChowdhary/continuous-claude/refs/tags/v0.7.0/continuous_claude.sh -o continuous-claude
chmod +x continuous-claude
sudo mv continuous-claude /usr/local/bin/
```

## [v0.6.4] - 2025-11-19

## What's Changed

- :white_check_mark: Add new tests for `validate_requirements`, `get_iteration_display`, `parse_claude_result`, and `create_iteration_branch` functions. (a8dfb39)

**Full Changelog**: https://github.com/AnandChowdhary/continuous-claude/compare/v0.6.3...v0.6.4

## Installation

Install with a single command:

```bash
curl -fsSL https://raw.githubusercontent.com/AnandChowdhary/continuous-claude/refs/tags/v0.6.4/install.sh | bash
```

Or download the script directly:

```bash
curl -fsSL https://raw.githubusercontent.com/AnandChowdhary/continuous-claude/refs/tags/v0.6.4/continuous_claude.sh -o continuous-claude
chmod +x continuous-claude
sudo mv continuous-claude /usr/local/bin/
```

## [v0.6.3] - 2025-11-19

## What's Changed

- :construction_worker: update CHANGELOG.md generation to use `gh api` and `jq` for release body inclusion (76d326e)
- :construction_worker: Generate and commit CHANGELOG during release workflow. (0cd6732)

**Full Changelog**: https://github.com/AnandChowdhary/continuous-claude/compare/v0.6.2...v0.6.3

## Installation

Install with a single command:

```bash
curl -fsSL https://raw.githubusercontent.com/AnandChowdhary/continuous-claude/refs/tags/v0.6.3/install.sh | bash
```

Or download the script directly:

```bash
curl -fsSL https://raw.githubusercontent.com/AnandChowdhary/continuous-claude/refs/tags/v0.6.3/continuous_claude.sh -o continuous-claude
chmod +x continuous-claude
sudo mv continuous-claude /usr/local/bin/
```

## [v0.6.2] - 2025-11-19

## What's Changed

- :bookmark: Release version v0.6.2 (61ffd58)
- :bug: Remove accidental submodules and ignore tests/libs (af28abf)

**Full Changelog**: https://github.com/AnandChowdhary/continuous-claude/compare/v0.6.1...v0.6.2

## Installation

Install with a single command:

```bash
curl -fsSL https://raw.githubusercontent.com/AnandChowdhary/continuous-claude/refs/tags/v0.6.2/install.sh | bash
```

Or download the script directly:

```bash
curl -fsSL https://raw.githubusercontent.com/AnandChowdhary/continuous-claude/refs/tags/v0.6.2/continuous_claude.sh -o continuous-claude
chmod +x continuous-claude
sudo mv continuous-claude /usr/local/bin/
```



## [v0.6.1] - 2025-11-19

## What's Changed

- :bookmark: Release version v0.6.1 (6cb3974)
- :bug: Improve test dependency installation robustness and ignore generated test libraries. (bf834ab)

**Full Changelog**: https://github.com/AnandChowdhary/continuous-claude/compare/v0.6.0...v0.6.1

## Installation

Install with a single command:

```bash
curl -fsSL https://raw.githubusercontent.com/AnandChowdhary/continuous-claude/refs/tags/v0.6.1/install.sh | bash
```

Or download the script directly:

```bash
curl -fsSL https://raw.githubusercontent.com/AnandChowdhary/continuous-claude/refs/tags/v0.6.1/continuous_claude.sh -o continuous-claude
chmod +x continuous-claude
sudo mv continuous-claude /usr/local/bin/
```



## [v0.6.0] - 2025-11-19

## What's Changed

- :bookmark: Release version v0.6.0 (31531c5)
- :sparkles: Update Bats testing framework and related libraries, add dry run mode (f571c81)

**Full Changelog**: https://github.com/AnandChowdhary/continuous-claude/compare/v0.5.1...v0.6.0

## Installation

Install with a single command:

```bash
curl -fsSL https://raw.githubusercontent.com/AnandChowdhary/continuous-claude/refs/tags/v0.6.0/install.sh | bash
```

Or download the script directly:

```bash
curl -fsSL https://raw.githubusercontent.com/AnandChowdhary/continuous-claude/refs/tags/v0.6.0/continuous_claude.sh -o continuous-claude
chmod +x continuous-claude
sudo mv continuous-claude /usr/local/bin/
```



## [v0.5.1] - 2025-11-17

## What's Changed

- :bookmark: Release version v0.5.1 (53e9f63)
- :pencil: Revise README story (a8a0aa0)

**Full Changelog**: https://github.com/AnandChowdhary/continuous-claude/compare/v0.5.0...v0.5.1

## Installation

Install with a single command:

```bash
curl -fsSL https://raw.githubusercontent.com/AnandChowdhary/continuous-claude/refs/tags/v0.5.1/install.sh | bash
```

Or download the script directly:

```bash
curl -fsSL https://raw.githubusercontent.com/AnandChowdhary/continuous-claude/refs/tags/v0.5.1/continuous_claude.sh -o continuous-claude
chmod +x continuous-claude
sudo mv continuous-claude /usr/local/bin/
```



## [v0.5.0] - 2025-11-17

## What's Changed

- :bookmark: Release version v0.5.0 (4a9a485)
- :green_heart: Improve version update logic in release workflow (68474aa)
- :sparkles: Add worktree support for parallel execution (0863bef)

**Full Changelog**: https://github.com/AnandChowdhary/continuous-claude/compare/v0.4.0...v0.5.0

## Installation

Install with a single command:

```bash
curl -fsSL https://raw.githubusercontent.com/AnandChowdhary/continuous-claude/refs/tags/v0.5.0/install.sh | bash
```

Or download the script directly:

```bash
curl -fsSL https://raw.githubusercontent.com/AnandChowdhary/continuous-claude/refs/tags/v0.5.0/continuous_claude.sh -o continuous-claude
chmod +x continuous-claude
sudo mv continuous-claude /usr/local/bin/
```



## [v0.4.0] - 2025-11-17

## What's Changed

- :bookmark: Release version v0.4.0 (561848d)
- :sparkles: Add versioning support to continuous_claude.sh and update release workflow (724f1d6)
- :sparkles: Add help message and usage instructions to continuous_claude.sh (6b55f70)

**Full Changelog**: https://github.com/AnandChowdhary/continuous-claude/compare/v0.3.2...v0.4.0

## Installation

Install with a single command:

```bash
curl -fsSL https://raw.githubusercontent.com/AnandChowdhary/continuous-claude/refs/tags/v0.4.0/install.sh | bash
```

Or download the script directly:

```bash
curl -fsSL https://raw.githubusercontent.com/AnandChowdhary/continuous-claude/refs/tags/v0.4.0/continuous_claude.sh -o continuous-claude
chmod +x continuous-claude
sudo mv continuous-claude /usr/local/bin/
```



## [v0.3.2] - 2025-11-17

## What's Changed

- :bookmark: Update installation commands in release workflow (0058d41)

**Full Changelog**: https://github.com/AnandChowdhary/continuous-claude/compare/v0.3.1...v0.3.2

## Installation

Install with a single command:

```bash
curl -fsSL https://raw.githubusercontent.com/AnandChowdhary/continuous-claude/refs/tags/v0.3.2/install.sh | bash
```

Or download the script directly:

```bash
curl -fsSL https://raw.githubusercontent.com/AnandChowdhary/continuous-claude/refs/tags/v0.3.2/continuous_claude.sh -o continuous-claude
chmod +x continuous-claude
sudo mv continuous-claude /usr/local/bin/
```



## [v0.3.1] - 2025-11-17

## What's Changed

- :bug: Update validation for conditional GitHub requirements (ed6c657)

**Full Changelog**: https://github.com/AnandChowdhary/continuous-claude/compare/v0.3.0...v0.3.1

## Installation

Install with a single command:

```bash
curl -fsSL https://raw.githubusercontent.com/AnandChowdhary/continuous-claude/main/install.sh | bash
```

Or download the script directly:

```bash
curl -fsSL https://raw.githubusercontent.com/AnandChowdhary/continuous-claude/main/continuous_claude.sh -o continuous-claude
chmod +x continuous-claude
sudo mv continuous-claude /usr/local/bin/
```



## [v0.3.0] - 2025-11-17

## What's Changed

- :sparkles: Add support for forwarding additional Claude Code CLI flags (#21) (b1822b3)

**Full Changelog**: https://github.com/AnandChowdhary/continuous-claude/compare/v0.2.0...v0.3.0

## Installation

Install with a single command:

```bash
curl -fsSL https://raw.githubusercontent.com/AnandChowdhary/continuous-claude/main/install.sh | bash
```

Or download the script directly:

```bash
curl -fsSL https://raw.githubusercontent.com/AnandChowdhary/continuous-claude/main/continuous_claude.sh -o continuous-claude
chmod +x continuous-claude
sudo mv continuous-claude /usr/local/bin/
```



## [v0.2.0] - 2025-11-16

## What's Changed

- :sparkles: Add --notes-file optional flag (d23fc3b)

**Full Changelog**: https://github.com/AnandChowdhary/continuous-claude/compare/v0.1.1...v0.2.0

## Installation

Install with a single command:

```bash
curl -fsSL https://raw.githubusercontent.com/AnandChowdhary/continuous-claude/main/install.sh | bash
```

Or download the script directly:

```bash
curl -fsSL https://raw.githubusercontent.com/AnandChowdhary/continuous-claude/main/continuous_claude.sh -o continuous-claude
chmod +x continuous-claude
sudo mv continuous-claude /usr/local/bin/
```



## [v0.1.1] - 2025-11-15

## What's Changed

- :pencil: Revise output example in README.md (4a7ba33)

**Full Changelog**: https://github.com/AnandChowdhary/continuous-claude/compare/v0.1.0...v0.1.1

## Installation

Install with a single command:

```bash
curl -fsSL https://raw.githubusercontent.com/AnandChowdhary/continuous-claude/main/install.sh | bash
```

Or download the script directly:

```bash
curl -fsSL https://raw.githubusercontent.com/AnandChowdhary/continuous-claude/main/continuous_claude.sh -o continuous-claude
chmod +x continuous-claude
sudo mv continuous-claude /usr/local/bin/
```



## [v0.1.0] - 2025-11-15

## What's Changed

- :construction_worker: Update release workflow to support gitmoji for version bump detection (4f60420)
- :sparkles: Enhance continuous_claude.sh with new flags for cost and merge strategy (4104455)
- :pencil: Update README.md to remove GitHub link from summary (47872d9)

**Full Changelog**: https://github.com/AnandChowdhary/continuous-claude/compare/v0.0.3...v0.1.0

## Installation

Install with a single command:

```bash
curl -fsSL https://raw.githubusercontent.com/AnandChowdhary/continuous-claude/main/install.sh | bash
```

Or download the script directly:

```bash
curl -fsSL https://raw.githubusercontent.com/AnandChowdhary/continuous-claude/main/continuous_claude.sh -o continuous-claude
chmod +x continuous-claude
sudo mv continuous-claude /usr/local/bin/
```



## [v0.0.3] - 2025-11-15

## What's Changed

- :pencil: Revise README.md to enhance project description and context (7fc34a4)

**Full Changelog**: https://github.com/AnandChowdhary/continuous-claude/compare/v0.0.2...v0.0.3

## Installation

Install with a single command:

```bash
curl -fsSL https://raw.githubusercontent.com/AnandChowdhary/continuous-claude/main/install.sh | bash
```

Or download the script directly:

```bash
curl -fsSL https://raw.githubusercontent.com/AnandChowdhary/continuous-claude/main/continuous_claude.sh -o continuous-claude
chmod +x continuous-claude
sudo mv continuous-claude /usr/local/bin/
```



## [v0.0.2] - 2025-11-15

## What's Changed

- :pencil: Update README.md to consolidate uninstall instructions (6d4174a)

**Full Changelog**: https://github.com/AnandChowdhary/continuous-claude/compare/v0.0.1...v0.0.2

## Installation

Install with a single command:

```bash
curl -fsSL https://raw.githubusercontent.com/AnandChowdhary/continuous-claude/main/install.sh | bash
```

Or download the script directly:

```bash
curl -fsSL https://raw.githubusercontent.com/AnandChowdhary/continuous-claude/main/continuous_claude.sh -o continuous-claude
chmod +x continuous-claude
sudo mv continuous-claude /usr/local/bin/
```



## [v0.0.1] - 2025-11-15

## What's Changed

- :pencil: Update README.md with installation instructions and usage examples (4c9c64d)
- :recycle: Improve PR status logging and change detection in continuous_claude.sh (9b7f2e1)
- :loud_sound: Add iteration display message in continuous_claude.sh (e2b15c8)
- :bug: Improve change detection in continuous_claude_commit (52e0163)
- :bug: Enhance error handling and cleanup in continuous_claude_commit (ae2012f)
- :bug: Refactor branch handling and commit logic (0312227)
- :pencil: Lead with Claude Code in 'How it works' intro sentence (#20) (5834a53)
- :poop: Add debug logging for PR review status in continuous_claude.sh (ce6ec6c)
- :bug: Ensure branch checkout after PR merge in continuous_claude.sh (d44022b)
- :pencil: Clarify prerequisites in Quick start section (#19) (cc577c6)
- :pencil: Enhance SHARED_TASK_NOTES.md description in README.md (#18) (e2655e4)
- :pencil: Emphasize full PR lifecycle automation in README.md (#17) (ca387dd)
- :bug: Refine PR merge conditions in continuous_claude.sh (534a81b)
- :pencil: Refactor enhanced prompt handling in continuous_claude.sh (1ac2c9f)
- :recycle: Extract AI prompts into constants in continuous_claude.sh (#16) (9db2193)
- :pencil: Improve SHARED_TASK_NOTES.md description in README.md (#15) (7b6b9e4)
- :sparkles: Update PR checks output formatting in continuous_claude.sh (a1efdb1)
- :bug: Refine review decision handling in continuous_claude.sh (c90c684)
- :recycle: Add randomness to branch names (18e84b5)
- :bug: Fix PR checks status handling in continuous_claude.sh (91e5c2e)
- :pencil: Improve quick start prerequisites in README.md (#12) (e810700)
- :sparkles: Improve PR checks feedback and waiting logic in continuous_claude.sh (827789a)
- :bug: Improve waiting logic for PR checks in continuous_claude.sh (5c5b436)
- :sparkles: Enhance PR checks and review status handling in continuous_claude.sh (60a8f36)
- :pencil: Add SHARED_TASK_NOTES example (9658d10)
- :memo: Clarify workflow description in README.md (#9) (5a7f38c)
- :memo: Simplify shared notes description in README.md (#8) (04475bb)
- :memo: Refine project description in README.md (#7) (80f47db)
- :recycle: Update notes file references from ITERATION_NOTES.md to SHARED_TASK_NOTES.md in .gitignore, continuous_claude.sh, and README.md for improved clarity and consistency. (5a23622)
- :sparkles: Enhance continuous workflow context in continuous_claude.sh (1abe574)
- :memo: Add iteration notes collaboration section to README.md (0ab1081)
- :see_no_evil: Add ITERATION_NOTES.md to .gitignore (aed9e61)
- :fire: Remove test functions (50ba34c)
- :memo: Improve project description clarity in README.md (#6) (14e11ab)
- :memo: Refine project description for clarity in README.md (#5) (6a94eda)
- :memo: Simplify project description in README.md (#4) (e2d36df)
- :recycle: Update merging strategy and enhance error logging in continuous_claude.sh (e048d62)
- :memo: Update project description in README.md (bc8e42b)
- :bug: Improve PR checks handling in continuous_claude.sh (0e5c23f)
- :sparkles: Add commit control feature to continuous_claude.sh (5623cca)
- :recycle: Refactor error logging in continuous_claude.sh (69f9a03)
- :sparkles: Enhance continuous_claude.sh with GitHub integration and error handling (83d2bcf)
- :sparkles: Enhance continuous_claude.sh with dynamic branch creation (bbb9c1a)
- :recycle: Refactor continuous_claude.sh into modular functions (d162c2b)
- :truck: Rename run_claude ->  continuous_claude.sh (74a45a5)
- 📃 Add MIT license (073535e)
- :pencil: Update README with quick start instructions (39210f8)
- :pencil: Add basic README (0d34bca)
- :sparkles: Add cost tracking and total cost summary (a904844)
- :recycle: Add command-line argument parsing for prompt and max-runs (d83c2e2)
- :sparkles: Add automatic git commit functionality to continuous mode (a625f96)
- :sparkles: Add error handling, infinite mode, iteration display improvements (c5d6063)
- :sparkles: Add loop for running Claude Code (44f0aac)

**Full Changelog**: https://github.com/AnandChowdhary/continuous-claude/compare/v0.0.0...v0.0.1

## Installation

Install with a single command:

```bash
curl -fsSL https://raw.githubusercontent.com/AnandChowdhary/continuous-claude/main/install.sh | bash
```

Or download the script directly:

```bash
curl -fsSL https://raw.githubusercontent.com/AnandChowdhary/continuous-claude/main/continuous_claude.sh -o continuous-claude
chmod +x continuous-claude
sudo mv continuous-claude /usr/local/bin/
```



