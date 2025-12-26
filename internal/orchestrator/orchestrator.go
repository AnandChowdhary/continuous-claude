// Package orchestrator provides the main loop logic for Continuous Claude.
package orchestrator

import (
	"fmt"
	"time"

	"github.com/guzus/continuous-claude/internal/claude"
	"github.com/guzus/continuous-claude/internal/config"
	"github.com/guzus/continuous-claude/internal/git"
	"github.com/guzus/continuous-claude/internal/github"
	"github.com/guzus/continuous-claude/internal/notes"
	"github.com/guzus/continuous-claude/internal/ui"
)

// Orchestrator manages the continuous development loop.
type Orchestrator struct {
	config   *config.Config
	git      *git.Client
	github   *github.Client
	claude   *claude.Client
	notes    *notes.Manager
	ui       *ui.Printer
	workDir  string

	// State
	iteration             int
	totalCost             float64
	completionSignalCount int
	startTime             time.Time
	baseBranch            string
}

// New creates a new orchestrator.
func New(cfg *config.Config, workDir string) (*Orchestrator, error) {
	gitClient := git.NewClient(workDir)

	// Detect owner/repo if not provided
	owner := cfg.Owner
	repo := cfg.Repo
	if owner == "" || repo == "" {
		detectedOwner, detectedRepo, err := gitClient.DetectGitHubRepo()
		if err != nil {
			return nil, fmt.Errorf("could not detect GitHub repository: %w\nPlease provide --owner and --repo flags", err)
		}
		if owner == "" {
			owner = detectedOwner
		}
		if repo == "" {
			repo = detectedRepo
		}
	}

	// Get current branch
	baseBranch, err := gitClient.CurrentBranch()
	if err != nil {
		return nil, fmt.Errorf("failed to get current branch: %w", err)
	}

	return &Orchestrator{
		config:     cfg,
		git:        gitClient,
		github:     github.NewClient(owner, repo, workDir),
		claude:     claude.NewClient(workDir, cfg.ExtraClaudeArgs),
		notes:      notes.NewManager(cfg.NotesFile),
		ui:         ui.NewPrinter(false),
		workDir:    workDir,
		baseBranch: baseBranch,
	}, nil
}

// Run starts the main orchestration loop.
func (o *Orchestrator) Run() error {
	o.startTime = time.Now()

	// Validate requirements
	if err := o.validateRequirements(); err != nil {
		return err
	}

	// Initialize notes file
	if err := o.notes.Initialize(o.config.Prompt); err != nil {
		o.ui.Warning("Could not initialize notes file: %v", err)
	}

	o.ui.Header("Continuous Claude")
	o.ui.Info("Starting continuous development loop")
	o.printConfig()

	// Main loop
	for {
		o.iteration++

		// Check stopping conditions
		if stop, reason := o.checkStopConditions(); stop {
			o.ui.Info("Stopping: %s", reason)
			break
		}

		// Run iteration
		if err := o.runIteration(); err != nil {
			o.ui.Error("Iteration %d failed: %v", o.iteration, err)
			// Continue to next iteration on error
			continue
		}
	}

	// Print summary
	o.ui.Summary(o.iteration-1, o.totalCost, time.Since(o.startTime),
		o.completionSignalCount >= o.config.CompletionThreshold)

	return nil
}

func (o *Orchestrator) validateRequirements() error {
	// Check Claude Code
	if err := claude.CheckAvailable(); err != nil {
		return err
	}

	// Check GitHub auth
	if err := o.github.CheckAuth(); err != nil {
		return err
	}

	// Check git repo
	if !o.git.IsRepo() {
		return fmt.Errorf("not in a git repository")
	}

	return nil
}

func (o *Orchestrator) printConfig() {
	o.ui.SubHeader("Configuration")

	if o.config.HasMaxRuns() {
		o.ui.Info("Max iterations: %d", o.config.MaxRuns)
	}
	if o.config.HasMaxCost() {
		o.ui.Info("Max cost: $%.2f", o.config.MaxCost)
	}
	if o.config.HasMaxDuration() {
		o.ui.Info("Max duration: %s", config.FormatDuration(o.config.MaxDuration))
	}
	o.ui.Info("Merge strategy: %s", o.config.MergeStrategy)
	o.ui.Info("Notes file: %s", o.notes.GetPath())
}

func (o *Orchestrator) checkStopConditions() (bool, string) {
	// Check max runs
	if o.config.HasMaxRuns() && o.iteration > o.config.MaxRuns {
		return true, fmt.Sprintf("reached max iterations (%d)", o.config.MaxRuns)
	}

	// Check max cost
	if o.config.HasMaxCost() && o.totalCost >= o.config.MaxCost {
		return true, fmt.Sprintf("reached max cost ($%.2f)", o.config.MaxCost)
	}

	// Check max duration
	if o.config.HasMaxDuration() && time.Since(o.startTime) >= o.config.MaxDuration {
		return true, fmt.Sprintf("reached max duration (%s)", config.FormatDuration(o.config.MaxDuration))
	}

	// Check completion signal
	if o.completionSignalCount >= o.config.CompletionThreshold {
		return true, "project completion signal detected"
	}

	return false, ""
}

func (o *Orchestrator) runIteration() error {
	o.ui.Iteration(o.iteration, o.config.MaxRuns)

	// Create feature branch
	branchName := o.git.GenerateBranchName(o.config.GitBranchPrefix, o.iteration)
	o.ui.Info("Creating branch: %s", branchName)

	if err := o.git.CreateBranch(branchName); err != nil {
		return fmt.Errorf("failed to create branch: %w", err)
	}

	// Read notes for context
	notesContent, _ := o.notes.Read()

	// Build prompt
	prompt := claude.BuildPrompt(
		o.config.Prompt,
		notesContent,
		o.config.CompletionSignal,
		o.iteration,
	)

	// Run Claude
	o.ui.StartSpinner("Running Claude...")
	result, err := o.claude.Run(prompt)
	o.ui.StopSpinner()

	if err != nil {
		return fmt.Errorf("Claude execution failed: %w", err)
	}

	// Track cost
	o.totalCost += result.Cost
	o.ui.Cost(result.Cost, o.totalCost)

	// Check for completion signal
	if claude.ContainsCompletionSignal(result.Output, o.config.CompletionSignal) {
		o.completionSignalCount++
		o.ui.Info("Completion signal detected (%d/%d)", o.completionSignalCount, o.config.CompletionThreshold)
	} else {
		o.completionSignalCount = 0
	}

	// Check for errors
	if result.IsError {
		o.ui.Warning("Claude reported an error in output")
	}

	// Print output summary
	o.ui.Box("Claude Output", truncateOutput(result.Output, 500))

	// Check for changes
	if o.config.DisableCommits {
		o.ui.Info("Commits disabled, skipping PR workflow")
		return nil
	}

	if o.config.DryRun {
		o.ui.Info("Dry run mode, skipping commit and PR")
		// Switch back to base branch and delete feature branch
		o.git.SwitchBranch(o.baseBranch)
		o.git.DeleteBranch(branchName)
		return nil
	}

	// Stage and check for changes
	if err := o.git.StageAll(); err != nil {
		return fmt.Errorf("failed to stage changes: %w", err)
	}

	hasChanges, err := o.git.HasChanges()
	if err != nil {
		return fmt.Errorf("failed to check for changes: %w", err)
	}

	if !hasChanges {
		o.ui.Info("No changes to commit")
		o.git.SwitchBranch(o.baseBranch)
		o.git.DeleteBranch(branchName)
		return nil
	}

	// Have Claude create commit
	o.ui.StartSpinner("Creating commit...")
	_, err = o.claude.RunCommit()
	o.ui.StopSpinner()

	if err != nil {
		return fmt.Errorf("failed to create commit: %w", err)
	}

	commitTitle, _ := o.git.GetLastCommitTitle()
	o.ui.Success("Committed: %s", commitTitle)

	// Push branch
	o.ui.StartSpinner("Pushing branch...")
	if err := o.git.PushWithRetry(branchName, 3); err != nil {
		o.ui.StopSpinner()
		return fmt.Errorf("failed to push: %w", err)
	}
	o.ui.StopSpinner()
	o.ui.Success("Pushed to origin/%s", branchName)

	// Create PR
	o.ui.StartSpinner("Creating PR...")
	commitMsg, _ := o.git.GetLastCommitMessage()
	prURL, err := o.github.CreatePR(commitTitle, formatPRBody(commitMsg, o.iteration), o.baseBranch)
	o.ui.StopSpinner()

	if err != nil {
		return fmt.Errorf("failed to create PR: %w", err)
	}
	o.ui.Success("Created PR: %s", prURL)

	// Wait for checks
	prNumber := github.GetPRNumber(prURL)
	o.ui.StartSpinner("Waiting for PR checks...")

	status, err := o.github.WaitForChecks(prNumber, 30*time.Minute, func(s *github.PRStatus) {
		o.ui.StopSpinner()
		o.ui.PRStatus(s.AllChecksPassed, s.HasPendingChecks, s.HasFailedChecks, s.ReviewDecision)
		if s.HasPendingChecks {
			o.ui.StartSpinner("Waiting for PR checks...")
		}
	})
	o.ui.StopSpinner()

	if err != nil {
		o.ui.Warning("Timeout waiting for checks: %v", err)
	}

	// Handle check results
	if status.HasFailedChecks {
		o.ui.Error("Checks failed, closing PR")
		o.github.ClosePR(prNumber, true)
		o.git.SwitchBranch(o.baseBranch)
		return nil
	}

	if !status.IsMergeable {
		o.ui.Warning("PR not mergeable (review required?)")
		o.git.SwitchBranch(o.baseBranch)
		return nil
	}

	// Merge PR
	o.ui.StartSpinner("Merging PR...")
	if err := o.github.MergePR(prNumber, o.config.MergeStrategy); err != nil {
		o.ui.StopSpinner()
		return fmt.Errorf("failed to merge PR: %w", err)
	}
	o.ui.StopSpinner()
	o.ui.Success("Merged PR")

	// Pull changes to base branch
	o.git.SwitchBranch(o.baseBranch)
	o.git.Pull(o.baseBranch)

	o.ui.Duration(time.Since(o.startTime), o.config.MaxDuration)

	return nil
}

func truncateOutput(s string, maxLen int) string {
	if len(s) <= maxLen {
		return s
	}
	return s[:maxLen] + "\n...[truncated]"
}

func formatPRBody(commitMsg string, iteration int) string {
	return fmt.Sprintf(`## Continuous Claude - Iteration %d

%s

---
*This PR was created automatically by Continuous Claude.*
`, iteration, commitMsg)
}
