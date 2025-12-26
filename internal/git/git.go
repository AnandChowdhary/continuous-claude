// Package git provides Git operations for Continuous Claude.
package git

import (
	"bytes"
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"os/exec"
	"regexp"
	"strings"
	"time"
)

// Client handles Git operations.
type Client struct {
	workDir string
}

// NewClient creates a new Git client.
func NewClient(workDir string) *Client {
	return &Client{workDir: workDir}
}

// IsRepo checks if the working directory is a git repository.
func (c *Client) IsRepo() bool {
	cmd := exec.Command("git", "rev-parse", "--is-inside-work-tree")
	cmd.Dir = c.workDir
	output, err := cmd.Output()
	return err == nil && strings.TrimSpace(string(output)) == "true"
}

// CurrentBranch returns the current branch name.
func (c *Client) CurrentBranch() (string, error) {
	cmd := exec.Command("git", "rev-parse", "--abbrev-ref", "HEAD")
	cmd.Dir = c.workDir
	output, err := cmd.Output()
	if err != nil {
		return "", fmt.Errorf("failed to get current branch: %w", err)
	}
	return strings.TrimSpace(string(output)), nil
}

// CreateBranch creates a new branch and switches to it.
func (c *Client) CreateBranch(name string) error {
	cmd := exec.Command("git", "checkout", "-b", name)
	cmd.Dir = c.workDir
	if output, err := cmd.CombinedOutput(); err != nil {
		return fmt.Errorf("failed to create branch %s: %w\n%s", name, err, output)
	}
	return nil
}

// SwitchBranch switches to an existing branch.
func (c *Client) SwitchBranch(name string) error {
	cmd := exec.Command("git", "checkout", name)
	cmd.Dir = c.workDir
	if output, err := cmd.CombinedOutput(); err != nil {
		return fmt.Errorf("failed to switch to branch %s: %w\n%s", name, err, output)
	}
	return nil
}

// DeleteBranch deletes a local branch.
func (c *Client) DeleteBranch(name string) error {
	cmd := exec.Command("git", "branch", "-D", name)
	cmd.Dir = c.workDir
	if output, err := cmd.CombinedOutput(); err != nil {
		return fmt.Errorf("failed to delete branch %s: %w\n%s", name, err, output)
	}
	return nil
}

// StageAll stages all changes.
func (c *Client) StageAll() error {
	cmd := exec.Command("git", "add", ".")
	cmd.Dir = c.workDir
	if output, err := cmd.CombinedOutput(); err != nil {
		return fmt.Errorf("failed to stage changes: %w\n%s", err, output)
	}
	return nil
}

// HasChanges checks if there are staged or unstaged changes.
func (c *Client) HasChanges() (bool, error) {
	cmd := exec.Command("git", "status", "--porcelain")
	cmd.Dir = c.workDir
	output, err := cmd.Output()
	if err != nil {
		return false, fmt.Errorf("failed to check git status: %w", err)
	}
	return len(strings.TrimSpace(string(output))) > 0, nil
}

// Commit creates a commit with the given message.
func (c *Client) Commit(message string) error {
	cmd := exec.Command("git", "commit", "-m", message)
	cmd.Dir = c.workDir
	if output, err := cmd.CombinedOutput(); err != nil {
		return fmt.Errorf("failed to commit: %w\n%s", err, output)
	}
	return nil
}

// Push pushes the current branch to origin.
func (c *Client) Push(branch string) error {
	cmd := exec.Command("git", "push", "-u", "origin", branch)
	cmd.Dir = c.workDir
	if output, err := cmd.CombinedOutput(); err != nil {
		return fmt.Errorf("failed to push: %w\n%s", err, output)
	}
	return nil
}

// PushWithRetry pushes with exponential backoff retry.
func (c *Client) PushWithRetry(branch string, maxRetries int) error {
	var lastErr error
	backoff := 2 * time.Second

	for i := 0; i <= maxRetries; i++ {
		if i > 0 {
			time.Sleep(backoff)
			backoff *= 2
		}

		err := c.Push(branch)
		if err == nil {
			return nil
		}
		lastErr = err

		// Only retry on network errors
		if !isNetworkError(err) {
			return err
		}
	}

	return fmt.Errorf("push failed after %d retries: %w", maxRetries, lastErr)
}

// Pull pulls the latest changes from origin for the given branch.
func (c *Client) Pull(branch string) error {
	cmd := exec.Command("git", "pull", "origin", branch)
	cmd.Dir = c.workDir
	if output, err := cmd.CombinedOutput(); err != nil {
		return fmt.Errorf("failed to pull: %w\n%s", err, output)
	}
	return nil
}

// Fetch fetches from origin.
func (c *Client) Fetch(branch string) error {
	cmd := exec.Command("git", "fetch", "origin", branch)
	cmd.Dir = c.workDir
	if output, err := cmd.CombinedOutput(); err != nil {
		return fmt.Errorf("failed to fetch: %w\n%s", err, output)
	}
	return nil
}

// GetRemoteURL returns the origin remote URL.
func (c *Client) GetRemoteURL() (string, error) {
	cmd := exec.Command("git", "remote", "get-url", "origin")
	cmd.Dir = c.workDir
	output, err := cmd.Output()
	if err != nil {
		return "", fmt.Errorf("failed to get remote URL: %w", err)
	}
	return strings.TrimSpace(string(output)), nil
}

// DetectGitHubRepo extracts owner and repo from the remote URL.
func (c *Client) DetectGitHubRepo() (owner, repo string, err error) {
	url, err := c.GetRemoteURL()
	if err != nil {
		return "", "", err
	}

	// Match HTTPS URLs: https://github.com/owner/repo.git
	httpsRe := regexp.MustCompile(`https://github\.com/([^/]+)/([^/.]+)(?:\.git)?`)
	if matches := httpsRe.FindStringSubmatch(url); matches != nil {
		return matches[1], matches[2], nil
	}

	// Match SSH URLs: git@github.com:owner/repo.git
	sshRe := regexp.MustCompile(`git@github\.com:([^/]+)/([^/.]+)(?:\.git)?`)
	if matches := sshRe.FindStringSubmatch(url); matches != nil {
		return matches[1], matches[2], nil
	}

	return "", "", fmt.Errorf("could not parse GitHub URL from: %s", url)
}

// GenerateBranchName generates a unique branch name for an iteration.
func (c *Client) GenerateBranchName(prefix string, iteration int) string {
	date := time.Now().Format("2006-01-02")
	hash := generateShortHash()
	return fmt.Sprintf("%siteration-%d/%s-%s", prefix, iteration, date, hash)
}

// GetDiff returns the diff of staged changes.
func (c *Client) GetDiff() (string, error) {
	cmd := exec.Command("git", "diff", "--staged")
	cmd.Dir = c.workDir
	output, err := cmd.Output()
	if err != nil {
		return "", fmt.Errorf("failed to get diff: %w", err)
	}
	return string(output), nil
}

// GetStatus returns the git status.
func (c *Client) GetStatus() (string, error) {
	cmd := exec.Command("git", "status")
	cmd.Dir = c.workDir
	output, err := cmd.Output()
	if err != nil {
		return "", fmt.Errorf("failed to get status: %w", err)
	}
	return string(output), nil
}

// GetLastCommitMessage returns the last commit message.
func (c *Client) GetLastCommitMessage() (string, error) {
	cmd := exec.Command("git", "log", "-1", "--format=%B")
	cmd.Dir = c.workDir
	output, err := cmd.Output()
	if err != nil {
		return "", fmt.Errorf("failed to get last commit message: %w", err)
	}
	return strings.TrimSpace(string(output)), nil
}

// GetLastCommitTitle returns just the title of the last commit.
func (c *Client) GetLastCommitTitle() (string, error) {
	cmd := exec.Command("git", "log", "-1", "--format=%s")
	cmd.Dir = c.workDir
	output, err := cmd.Output()
	if err != nil {
		return "", fmt.Errorf("failed to get last commit title: %w", err)
	}
	return strings.TrimSpace(string(output)), nil
}

// WorktreeAdd creates a new worktree.
func (c *Client) WorktreeAdd(path, branch string) error {
	cmd := exec.Command("git", "worktree", "add", path, branch)
	cmd.Dir = c.workDir
	if output, err := cmd.CombinedOutput(); err != nil {
		return fmt.Errorf("failed to create worktree: %w\n%s", err, output)
	}
	return nil
}

// WorktreeRemove removes a worktree.
func (c *Client) WorktreeRemove(path string) error {
	cmd := exec.Command("git", "worktree", "remove", path, "--force")
	cmd.Dir = c.workDir
	if output, err := cmd.CombinedOutput(); err != nil {
		return fmt.Errorf("failed to remove worktree: %w\n%s", err, output)
	}
	return nil
}

// WorktreeList lists all worktrees.
func (c *Client) WorktreeList() ([]string, error) {
	cmd := exec.Command("git", "worktree", "list", "--porcelain")
	cmd.Dir = c.workDir
	output, err := cmd.Output()
	if err != nil {
		return nil, fmt.Errorf("failed to list worktrees: %w", err)
	}

	var worktrees []string
	for _, line := range strings.Split(string(output), "\n") {
		if strings.HasPrefix(line, "worktree ") {
			worktrees = append(worktrees, strings.TrimPrefix(line, "worktree "))
		}
	}
	return worktrees, nil
}

// Run executes a custom git command.
func (c *Client) Run(args ...string) (string, error) {
	cmd := exec.Command("git", args...)
	cmd.Dir = c.workDir
	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	err := cmd.Run()
	if err != nil {
		return "", fmt.Errorf("git %s failed: %w\n%s", strings.Join(args, " "), err, stderr.String())
	}
	return stdout.String(), nil
}

func generateShortHash() string {
	b := make([]byte, 4)
	rand.Read(b)
	return hex.EncodeToString(b)
}

func isNetworkError(err error) bool {
	if err == nil {
		return false
	}
	errStr := err.Error()
	return strings.Contains(errStr, "Could not resolve host") ||
		strings.Contains(errStr, "Connection refused") ||
		strings.Contains(errStr, "Network is unreachable") ||
		strings.Contains(errStr, "Connection timed out") ||
		strings.Contains(errStr, "SSL") ||
		strings.Contains(errStr, "443")
}
