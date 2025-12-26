// Package config provides configuration management for Continuous Claude.
package config

import (
	"fmt"
	"regexp"
	"strconv"
	"strings"
	"time"
)

// Config holds all configuration for a Continuous Claude run.
type Config struct {
	// Core settings
	Prompt              string
	MaxRuns             int
	MaxCost             float64
	MaxDuration         time.Duration
	Owner               string
	Repo                string
	MergeStrategy       string
	GitBranchPrefix     string
	NotesFile           string
	DisableCommits      bool
	DryRun              bool
	CompletionSignal    string
	CompletionThreshold int

	// Worktree settings
	Worktree        string
	WorktreeBaseDir string
	CleanupWorktree bool

	// Update settings
	AutoUpdate     bool
	DisableUpdates bool

	// Extra args to pass to Claude
	ExtraClaudeArgs []string
}

// DefaultConfig returns a Config with default values.
func DefaultConfig() *Config {
	return &Config{
		MaxRuns:             0,
		MaxCost:             0,
		MaxDuration:         0,
		MergeStrategy:       "squash",
		GitBranchPrefix:     "continuous-claude/",
		NotesFile:           "SHARED_TASK_NOTES.md",
		CompletionSignal:    "CONTINUOUS_CLAUDE_PROJECT_COMPLETE",
		CompletionThreshold: 3,
		WorktreeBaseDir:     "../continuous-claude-worktrees",
	}
}

// Validate checks if the configuration is valid.
func (c *Config) Validate() error {
	if c.Prompt == "" {
		return fmt.Errorf("prompt is required (use -p or --prompt)")
	}

	// At least one limit must be set
	if c.MaxRuns == 0 && c.MaxCost == 0 && c.MaxDuration == 0 {
		return fmt.Errorf("at least one limit must be set: --max-runs, --max-cost, or --max-duration")
	}

	if c.MaxRuns < 0 {
		return fmt.Errorf("--max-runs must be non-negative")
	}

	if c.MaxCost < 0 {
		return fmt.Errorf("--max-cost must be non-negative")
	}

	if c.MaxDuration < 0 {
		return fmt.Errorf("--max-duration must be non-negative")
	}

	if c.CompletionThreshold < 1 {
		return fmt.Errorf("--completion-threshold must be at least 1")
	}

	validStrategies := map[string]bool{"squash": true, "merge": true, "rebase": true}
	if !validStrategies[c.MergeStrategy] {
		return fmt.Errorf("--merge-strategy must be one of: squash, merge, rebase")
	}

	return nil
}

// HasMaxRuns returns true if a max runs limit is set.
func (c *Config) HasMaxRuns() bool {
	return c.MaxRuns > 0
}

// HasMaxCost returns true if a max cost limit is set.
func (c *Config) HasMaxCost() bool {
	return c.MaxCost > 0
}

// HasMaxDuration returns true if a max duration limit is set.
func (c *Config) HasMaxDuration() bool {
	return c.MaxDuration > 0
}

// ParseDuration parses a duration string like "2h", "30m", "1h30m".
func ParseDuration(s string) (time.Duration, error) {
	if s == "" {
		return 0, nil
	}

	// Try standard Go duration parsing first
	if d, err := time.ParseDuration(s); err == nil {
		return d, nil
	}

	// Parse custom format like "1h30m", "2h", "45m"
	re := regexp.MustCompile(`^(?:(\d+)h)?(?:(\d+)m)?(?:(\d+)s)?$`)
	matches := re.FindStringSubmatch(s)
	if matches == nil {
		return 0, fmt.Errorf("invalid duration format: %s (use format like '2h', '30m', '1h30m')", s)
	}

	var total time.Duration

	if matches[1] != "" {
		hours, _ := strconv.Atoi(matches[1])
		total += time.Duration(hours) * time.Hour
	}

	if matches[2] != "" {
		minutes, _ := strconv.Atoi(matches[2])
		total += time.Duration(minutes) * time.Minute
	}

	if matches[3] != "" {
		seconds, _ := strconv.Atoi(matches[3])
		total += time.Duration(seconds) * time.Second
	}

	if total == 0 {
		return 0, fmt.Errorf("invalid duration: %s", s)
	}

	return total, nil
}

// FormatDuration formats a duration in human-readable format.
func FormatDuration(d time.Duration) string {
	if d == 0 {
		return "0s"
	}

	var parts []string

	hours := int(d.Hours())
	minutes := int(d.Minutes()) % 60
	seconds := int(d.Seconds()) % 60

	if hours > 0 {
		parts = append(parts, fmt.Sprintf("%dh", hours))
	}
	if minutes > 0 {
		parts = append(parts, fmt.Sprintf("%dm", minutes))
	}
	if seconds > 0 {
		parts = append(parts, fmt.Sprintf("%ds", seconds))
	}

	return strings.Join(parts, "")
}
