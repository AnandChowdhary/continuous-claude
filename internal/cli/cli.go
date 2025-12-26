// Package cli provides the command-line interface for Continuous Claude.
package cli

import (
	"fmt"
	"os"

	"github.com/guzus/continuous-claude/internal/config"
	"github.com/guzus/continuous-claude/internal/git"
	"github.com/guzus/continuous-claude/internal/orchestrator"
	"github.com/guzus/continuous-claude/internal/ui"
	"github.com/guzus/continuous-claude/internal/version"
	"github.com/spf13/cobra"
)

var (
	appVersion   string
	appBuildDate string
	appGitCommit string
)

// Execute runs the CLI.
func Execute(ver, buildDate, gitCommit string) error {
	appVersion = ver
	appBuildDate = buildDate
	appGitCommit = gitCommit

	return rootCmd.Execute()
}

var rootCmd = &cobra.Command{
	Use:   "continuous-claude",
	Short: "Continuous Claude - Autonomous AI development with GitHub integration",
	Long: `Continuous Claude orchestrates Claude Code to run iteratively with full GitHub integration.

It automates the entire PR lifecycle for large, multi-iteration AI development tasks -
enabling Claude to autonomously create PRs, monitor CI/CD checks, handle reviews,
and merge changes while maintaining persistent context across runs.

Example:
  continuous-claude -p "Add comprehensive test coverage" --max-runs 5
  continuous-claude -p "Refactor authentication" --max-cost 10.00
  continuous-claude -p "Fix all linting errors" --max-duration 2h`,
	RunE: runMain,
}

var (
	// Required flags
	prompt string

	// Limit flags (at least one required)
	maxRuns     int
	maxCost     float64
	maxDuration string

	// Optional flags
	owner               string
	repo                string
	mergeStrategy       string
	gitBranchPrefix     string
	notesFile           string
	disableCommits      bool
	dryRun              bool
	completionSignal    string
	completionThreshold int
	worktree            string
	worktreeBaseDir     string
	cleanupWorktree     bool
	autoUpdate          bool
	disableUpdates      bool
)

func init() {
	// Required
	rootCmd.Flags().StringVarP(&prompt, "prompt", "p", "", "Task description for Claude (required)")

	// Limits (at least one required)
	rootCmd.Flags().IntVarP(&maxRuns, "max-runs", "m", 0, "Maximum number of iterations (0 = unlimited)")
	rootCmd.Flags().Float64Var(&maxCost, "max-cost", 0, "Maximum cost in USD (0 = unlimited)")
	rootCmd.Flags().StringVar(&maxDuration, "max-duration", "", "Maximum duration (e.g., '2h', '30m', '1h30m')")

	// GitHub/Git options
	rootCmd.Flags().StringVar(&owner, "owner", "", "GitHub repository owner (auto-detected)")
	rootCmd.Flags().StringVar(&repo, "repo", "", "GitHub repository name (auto-detected)")
	rootCmd.Flags().StringVar(&mergeStrategy, "merge-strategy", "squash", "PR merge strategy: squash, merge, rebase")
	rootCmd.Flags().StringVar(&gitBranchPrefix, "git-branch-prefix", "continuous-claude/", "Branch name prefix")
	rootCmd.Flags().StringVar(&notesFile, "notes-file", "SHARED_TASK_NOTES.md", "Path to notes file for context")

	// Execution options
	rootCmd.Flags().BoolVar(&disableCommits, "disable-commits", false, "Run without creating commits/PRs")
	rootCmd.Flags().BoolVar(&dryRun, "dry-run", false, "Simulate without making changes")
	rootCmd.Flags().StringVar(&completionSignal, "completion-signal", "CONTINUOUS_CLAUDE_PROJECT_COMPLETE", "Signal phrase for early stop")
	rootCmd.Flags().IntVar(&completionThreshold, "completion-threshold", 3, "Consecutive signals needed to stop")

	// Worktree options
	rootCmd.Flags().StringVar(&worktree, "worktree", "", "Name for git worktree (parallel execution)")
	rootCmd.Flags().StringVar(&worktreeBaseDir, "worktree-base-dir", "../continuous-claude-worktrees", "Base directory for worktrees")
	rootCmd.Flags().BoolVar(&cleanupWorktree, "cleanup-worktree", false, "Remove worktree after completion")

	// Update options
	rootCmd.Flags().BoolVar(&autoUpdate, "auto-update", false, "Automatically install updates")
	rootCmd.Flags().BoolVar(&disableUpdates, "disable-updates", false, "Skip update checks")

	// Add subcommands
	rootCmd.AddCommand(versionCmd)
	rootCmd.AddCommand(updateCmd)
	rootCmd.AddCommand(listWorktreesCmd)
}

var versionCmd = &cobra.Command{
	Use:   "version",
	Short: "Print version information",
	Run: func(cmd *cobra.Command, args []string) {
		fmt.Printf("Continuous Claude %s\n", appVersion)
		fmt.Printf("  Build date: %s\n", appBuildDate)
		fmt.Printf("  Git commit: %s\n", appGitCommit)
	},
}

var updateCmd = &cobra.Command{
	Use:   "update",
	Short: "Check for and install updates",
	RunE: func(cmd *cobra.Command, args []string) error {
		printer := ui.NewPrinter(false)

		printer.Info("Checking for updates...")
		latestVersion, hasUpdate, err := version.CheckForUpdates(appVersion)
		if err != nil {
			return fmt.Errorf("failed to check for updates: %w", err)
		}

		if !hasUpdate {
			printer.Success("You are running the latest version (%s)", appVersion)
			return nil
		}

		printer.Info("New version available: %s (current: %s)", latestVersion, appVersion)

		if !printer.Confirm("Would you like to update now?") {
			printer.Info("Update cancelled")
			return nil
		}

		printer.StartSpinner("Downloading update...")
		tmpPath, err := version.DownloadUpdate(latestVersion)
		printer.StopSpinner()

		if err != nil {
			return fmt.Errorf("failed to download update: %w", err)
		}

		printer.StartSpinner("Installing update...")
		if err := version.InstallUpdate(tmpPath); err != nil {
			printer.StopSpinner()
			return fmt.Errorf("failed to install update: %w", err)
		}
		printer.StopSpinner()

		printer.Success("Updated to version %s", latestVersion)
		return nil
	},
}

var listWorktreesCmd = &cobra.Command{
	Use:   "list-worktrees",
	Short: "List active git worktrees",
	RunE: func(cmd *cobra.Command, args []string) error {
		cwd, _ := os.Getwd()
		gitClient := git.NewClient(cwd)

		worktrees, err := gitClient.WorktreeList()
		if err != nil {
			return err
		}

		if len(worktrees) == 0 {
			fmt.Println("No worktrees found")
			return nil
		}

		fmt.Println("Active worktrees:")
		for _, wt := range worktrees {
			fmt.Printf("  %s\n", wt)
		}
		return nil
	},
}

func runMain(cmd *cobra.Command, args []string) error {
	// Get working directory
	workDir, err := os.Getwd()
	if err != nil {
		return fmt.Errorf("failed to get working directory: %w", err)
	}

	// Parse duration
	duration, err := config.ParseDuration(maxDuration)
	if err != nil {
		return err
	}

	// Build config
	cfg := &config.Config{
		Prompt:              prompt,
		MaxRuns:             maxRuns,
		MaxCost:             maxCost,
		MaxDuration:         duration,
		Owner:               owner,
		Repo:                repo,
		MergeStrategy:       mergeStrategy,
		GitBranchPrefix:     gitBranchPrefix,
		NotesFile:           notesFile,
		DisableCommits:      disableCommits,
		DryRun:              dryRun,
		CompletionSignal:    completionSignal,
		CompletionThreshold: completionThreshold,
		Worktree:            worktree,
		WorktreeBaseDir:     worktreeBaseDir,
		CleanupWorktree:     cleanupWorktree,
		AutoUpdate:          autoUpdate,
		DisableUpdates:      disableUpdates,
		ExtraClaudeArgs:     args, // Pass remaining args to Claude
	}

	// Validate config
	if err := cfg.Validate(); err != nil {
		return err
	}

	// Check for updates (unless disabled)
	if !cfg.DisableUpdates {
		checkUpdates(cfg.AutoUpdate)
	}

	// Create and run orchestrator
	orch, err := orchestrator.New(cfg, workDir)
	if err != nil {
		return err
	}

	return orch.Run()
}

func checkUpdates(autoInstall bool) {
	printer := ui.NewPrinter(false)

	latestVersion, hasUpdate, err := version.CheckForUpdates(appVersion)
	if err != nil {
		// Silently ignore update check errors
		return
	}

	if !hasUpdate {
		return
	}

	if autoInstall {
		printer.Info("Installing update %s...", latestVersion)
		tmpPath, err := version.DownloadUpdate(latestVersion)
		if err != nil {
			printer.Warning("Failed to download update: %v", err)
			return
		}

		if err := version.InstallUpdate(tmpPath); err != nil {
			printer.Warning("Failed to install update: %v", err)
			return
		}

		printer.Success("Updated to %s, please restart", latestVersion)
		os.Exit(0)
	} else {
		printer.Info("New version available: %s (run 'continuous-claude update' to install)", latestVersion)
	}
}
