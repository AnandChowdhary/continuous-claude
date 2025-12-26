// Package github provides GitHub operations for Continuous Claude.
package github

import (
	"encoding/json"
	"fmt"
	"os/exec"
	"strings"
	"time"
)

// Client handles GitHub operations via the gh CLI.
type Client struct {
	owner   string
	repo    string
	workDir string
}

// PRCheck represents a CI/CD check on a PR.
type PRCheck struct {
	Name   string `json:"name"`
	State  string `json:"state"`
	Bucket string `json:"bucket"`
}

// PRStatus represents the overall status of a PR.
type PRStatus struct {
	Checks         []PRCheck
	ReviewDecision string
	IsMergeable    bool
	AllChecksPassed bool
	HasPendingChecks bool
	HasFailedChecks  bool
}

// NewClient creates a new GitHub client.
func NewClient(owner, repo, workDir string) *Client {
	return &Client{
		owner:   owner,
		repo:    repo,
		workDir: workDir,
	}
}

// CheckAuth verifies GitHub CLI authentication.
func (c *Client) CheckAuth() error {
	cmd := exec.Command("gh", "auth", "status")
	cmd.Dir = c.workDir
	if output, err := cmd.CombinedOutput(); err != nil {
		return fmt.Errorf("GitHub CLI not authenticated: %w\n%s", err, output)
	}
	return nil
}

// CreatePR creates a new pull request.
func (c *Client) CreatePR(title, body, base string) (string, error) {
	args := []string{"pr", "create", "--title", title, "--body", body}
	if base != "" {
		args = append(args, "--base", base)
	}

	cmd := exec.Command("gh", args...)
	cmd.Dir = c.workDir
	output, err := cmd.CombinedOutput()
	if err != nil {
		return "", fmt.Errorf("failed to create PR: %w\n%s", err, output)
	}

	// The output contains the PR URL
	prURL := strings.TrimSpace(string(output))
	return prURL, nil
}

// GetPRNumber extracts the PR number from a URL.
func GetPRNumber(prURL string) string {
	parts := strings.Split(prURL, "/")
	if len(parts) > 0 {
		return parts[len(parts)-1]
	}
	return ""
}

// GetPRChecks returns the CI/CD checks for a PR.
func (c *Client) GetPRChecks(prNumber string) ([]PRCheck, error) {
	cmd := exec.Command("gh", "pr", "checks", prNumber, "--json", "name,state,bucket")
	cmd.Dir = c.workDir
	output, err := cmd.Output()
	if err != nil {
		// If no checks configured, return empty list
		if strings.Contains(string(output), "no checks") {
			return []PRCheck{}, nil
		}
		return nil, fmt.Errorf("failed to get PR checks: %w", err)
	}

	var checks []PRCheck
	if err := json.Unmarshal(output, &checks); err != nil {
		return nil, fmt.Errorf("failed to parse PR checks: %w", err)
	}

	return checks, nil
}

// GetPRReviewDecision returns the review decision for a PR.
func (c *Client) GetPRReviewDecision(prNumber string) (string, error) {
	cmd := exec.Command("gh", "pr", "view", prNumber, "--json", "reviewDecision")
	cmd.Dir = c.workDir
	output, err := cmd.Output()
	if err != nil {
		return "", fmt.Errorf("failed to get PR review status: %w", err)
	}

	var result struct {
		ReviewDecision string `json:"reviewDecision"`
	}
	if err := json.Unmarshal(output, &result); err != nil {
		return "", fmt.Errorf("failed to parse review decision: %w", err)
	}

	return result.ReviewDecision, nil
}

// GetPRStatus returns the full status of a PR.
func (c *Client) GetPRStatus(prNumber string) (*PRStatus, error) {
	checks, err := c.GetPRChecks(prNumber)
	if err != nil {
		return nil, err
	}

	reviewDecision, err := c.GetPRReviewDecision(prNumber)
	if err != nil {
		return nil, err
	}

	status := &PRStatus{
		Checks:         checks,
		ReviewDecision: reviewDecision,
	}

	// Analyze checks
	for _, check := range checks {
		switch check.State {
		case "SUCCESS", "NEUTRAL", "SKIPPED":
			// OK
		case "PENDING", "QUEUED", "IN_PROGRESS":
			status.HasPendingChecks = true
		case "FAILURE", "ERROR", "CANCELLED", "TIMED_OUT", "ACTION_REQUIRED":
			status.HasFailedChecks = true
		}
	}

	status.AllChecksPassed = len(checks) == 0 || (!status.HasPendingChecks && !status.HasFailedChecks)
	status.IsMergeable = status.AllChecksPassed &&
		(reviewDecision == "" || reviewDecision == "APPROVED")

	return status, nil
}

// WaitForChecks polls the PR checks until they complete or timeout.
func (c *Client) WaitForChecks(prNumber string, timeout time.Duration, onStatusChange func(*PRStatus)) (*PRStatus, error) {
	deadline := time.Now().Add(timeout)
	pollInterval := 10 * time.Second
	var lastStatus *PRStatus

	for time.Now().Before(deadline) {
		status, err := c.GetPRStatus(prNumber)
		if err != nil {
			return nil, err
		}

		// Notify on status change
		if onStatusChange != nil && hasStatusChanged(lastStatus, status) {
			onStatusChange(status)
		}
		lastStatus = status

		// Check if we can return
		if status.HasFailedChecks {
			return status, nil
		}
		if status.AllChecksPassed {
			return status, nil
		}

		time.Sleep(pollInterval)
	}

	return lastStatus, fmt.Errorf("timeout waiting for PR checks after %s", timeout)
}

// MergePR merges the PR with the given strategy.
func (c *Client) MergePR(prNumber, strategy string) error {
	args := []string{"pr", "merge", prNumber, "--" + strategy, "--delete-branch"}
	cmd := exec.Command("gh", args...)
	cmd.Dir = c.workDir
	if output, err := cmd.CombinedOutput(); err != nil {
		return fmt.Errorf("failed to merge PR: %w\n%s", err, output)
	}
	return nil
}

// ClosePR closes a PR without merging.
func (c *Client) ClosePR(prNumber string, deleteBranch bool) error {
	args := []string{"pr", "close", prNumber}
	if deleteBranch {
		args = append(args, "--delete-branch")
	}
	cmd := exec.Command("gh", args...)
	cmd.Dir = c.workDir
	if output, err := cmd.CombinedOutput(); err != nil {
		return fmt.Errorf("failed to close PR: %w\n%s", err, output)
	}
	return nil
}

// UpdatePRBranch updates the PR branch with the base branch.
func (c *Client) UpdatePRBranch(prNumber string) error {
	cmd := exec.Command("gh", "pr", "update-branch", prNumber)
	cmd.Dir = c.workDir
	output, err := cmd.CombinedOutput()
	if err != nil {
		// If already up to date, that's fine
		if strings.Contains(string(output), "already up to date") {
			return nil
		}
		return fmt.Errorf("failed to update PR branch: %w\n%s", err, output)
	}
	return nil
}

// GetLatestRelease returns the latest release version.
func (c *Client) GetLatestRelease(owner, repo string) (string, error) {
	cmd := exec.Command("gh", "release", "view", "--repo", fmt.Sprintf("%s/%s", owner, repo), "--json", "tagName")
	output, err := cmd.Output()
	if err != nil {
		return "", fmt.Errorf("failed to get latest release: %w", err)
	}

	var result struct {
		TagName string `json:"tagName"`
	}
	if err := json.Unmarshal(output, &result); err != nil {
		return "", fmt.Errorf("failed to parse release info: %w", err)
	}

	return result.TagName, nil
}

func hasStatusChanged(old, new *PRStatus) bool {
	if old == nil {
		return true
	}
	if old.AllChecksPassed != new.AllChecksPassed {
		return true
	}
	if old.HasPendingChecks != new.HasPendingChecks {
		return true
	}
	if old.HasFailedChecks != new.HasFailedChecks {
		return true
	}
	if old.ReviewDecision != new.ReviewDecision {
		return true
	}
	return false
}

// FormatCheckStatus returns a formatted string of check statuses.
func FormatCheckStatus(status *PRStatus) string {
	if len(status.Checks) == 0 {
		return "No checks configured"
	}

	var parts []string
	for _, check := range status.Checks {
		var icon string
		switch check.State {
		case "SUCCESS":
			icon = "✓"
		case "PENDING", "QUEUED", "IN_PROGRESS":
			icon = "○"
		case "FAILURE", "ERROR":
			icon = "✗"
		default:
			icon = "?"
		}
		parts = append(parts, fmt.Sprintf("%s %s", icon, check.Name))
	}
	return strings.Join(parts, ", ")
}
