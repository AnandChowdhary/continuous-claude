// Package claude provides Claude Code CLI integration.
package claude

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os/exec"
	"strings"
)

// Client handles Claude Code CLI operations.
type Client struct {
	workDir   string
	extraArgs []string
}

// Result represents the response from Claude Code.
type Result struct {
	Output    string
	Cost      float64
	IsError   bool
	RawOutput string
}

// NewClient creates a new Claude Code client.
func NewClient(workDir string, extraArgs []string) *Client {
	return &Client{
		workDir:   workDir,
		extraArgs: extraArgs,
	}
}

// CheckAvailable verifies Claude Code CLI is available.
func CheckAvailable() error {
	cmd := exec.Command("claude", "--version")
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("Claude Code CLI not found: %w", err)
	}
	return nil
}

// Run executes Claude Code with the given prompt.
func (c *Client) Run(prompt string) (*Result, error) {
	args := []string{
		"-p", prompt,
		"--output-format", "json",
		"--dangerously-skip-permissions",
	}
	args = append(args, c.extraArgs...)

	cmd := exec.Command("claude", args...)
	cmd.Dir = c.workDir

	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	err := cmd.Run()
	rawOutput := stdout.String()

	result := &Result{
		RawOutput: rawOutput,
	}

	// Parse the JSON output
	if rawOutput != "" {
		if err := parseClaudeOutput(rawOutput, result); err != nil {
			// If we can't parse, use raw output
			result.Output = rawOutput
		}
	}

	// Check for errors
	if err != nil {
		result.IsError = true
		if stderr.Len() > 0 {
			result.Output = stderr.String()
		}
		return result, nil
	}

	return result, nil
}

// RunCommit asks Claude to create a commit message and commit.
func (c *Client) RunCommit() (string, error) {
	prompt := `Review the staged changes and create an appropriate commit.

Instructions:
1. Review the changes with 'git diff --staged'
2. Write a clear, concise commit message following conventional commit style
3. The message should explain WHAT changed and WHY, not just describe the diff
4. Commit the changes with 'git commit -m "your message"'
5. Return the commit message you used`

	args := []string{
		"-p", prompt,
		"--output-format", "json",
		"--dangerously-skip-permissions",
		"--allowedTools", "Bash(git commit:*),Bash(git diff:*),Bash(git status:*)",
	}

	cmd := exec.Command("claude", args...)
	cmd.Dir = c.workDir

	var stdout bytes.Buffer
	cmd.Stdout = &stdout

	if err := cmd.Run(); err != nil {
		return "", fmt.Errorf("failed to run Claude commit: %w", err)
	}

	// Parse the output to get the result
	var result Result
	if err := parseClaudeOutput(stdout.String(), &result); err != nil {
		return stdout.String(), nil
	}

	return result.Output, nil
}

// parseClaudeOutput parses the JSON output from Claude Code.
func parseClaudeOutput(output string, result *Result) error {
	output = strings.TrimSpace(output)
	if output == "" {
		return fmt.Errorf("empty output")
	}

	// Try to parse as array first (multiple tool uses)
	var arrayResult []json.RawMessage
	if err := json.Unmarshal([]byte(output), &arrayResult); err == nil && len(arrayResult) > 0 {
		// Find the last text result
		for i := len(arrayResult) - 1; i >= 0; i-- {
			var item struct {
				Type    string  `json:"type"`
				Result  string  `json:"result"`
				Cost    float64 `json:"total_cost_usd"`
				IsError bool    `json:"is_error"`
			}
			if err := json.Unmarshal(arrayResult[i], &item); err == nil {
				if item.Type == "result" || item.Result != "" {
					result.Output = item.Result
					result.Cost = item.Cost
					result.IsError = item.IsError
					return nil
				}
			}
		}
		// If no result found, try to get cost from last item
		var lastItem struct {
			Cost float64 `json:"total_cost_usd"`
		}
		json.Unmarshal(arrayResult[len(arrayResult)-1], &lastItem)
		result.Cost = lastItem.Cost
		return nil
	}

	// Try to parse as single object
	var singleResult struct {
		Result  string  `json:"result"`
		Cost    float64 `json:"total_cost_usd"`
		IsError bool    `json:"is_error"`
	}
	if err := json.Unmarshal([]byte(output), &singleResult); err == nil {
		result.Output = singleResult.Result
		result.Cost = singleResult.Cost
		result.IsError = singleResult.IsError
		return nil
	}

	return fmt.Errorf("could not parse output as JSON")
}

// BuildPrompt constructs the full prompt with workflow context.
func BuildPrompt(userPrompt, notesContent, completionSignal string, iteration int) string {
	var sb strings.Builder

	sb.WriteString("## CONTINUOUS WORKFLOW CONTEXT\n\n")
	sb.WriteString("This is part of a **continuous development loop** - you are one runner in a relay race.\n")
	sb.WriteString("Your work will be committed, reviewed via PR, and then the next iteration will continue from where you left off.\n\n")
	sb.WriteString("**Key Points:**\n")
	sb.WriteString("- You are iteration #")
	sb.WriteString(fmt.Sprintf("%d", iteration))
	sb.WriteString("\n")
	sb.WriteString("- Focus on making incremental progress - you don't need to complete everything in one go\n")
	sb.WriteString("- Your changes will be committed and a PR created automatically\n")
	sb.WriteString("- The next iteration will continue your work based on the notes you leave\n\n")

	if completionSignal != "" {
		sb.WriteString("**Project Completion Signal**: If you believe the ENTIRE project goal has been fully achieved ")
		sb.WriteString("and no more iterations are needed, include this exact phrase in your response: \"")
		sb.WriteString(completionSignal)
		sb.WriteString("\"\n\n")
	}

	sb.WriteString("---\n\n")
	sb.WriteString("## PRIMARY GOAL\n\n")
	sb.WriteString(userPrompt)
	sb.WriteString("\n\n")

	if notesContent != "" {
		sb.WriteString("---\n\n")
		sb.WriteString("## CONTEXT FROM PREVIOUS ITERATION\n\n")
		sb.WriteString("The following is from SHARED_TASK_NOTES.md - these are notes left by the previous iteration:\n\n")
		sb.WriteString("```\n")
		sb.WriteString(notesContent)
		sb.WriteString("\n```\n\n")
	}

	sb.WriteString("---\n\n")
	sb.WriteString("## ITERATION NOTES\n\n")
	sb.WriteString("Before completing your work, update the `SHARED_TASK_NOTES.md` file with:\n")
	sb.WriteString("1. What you accomplished this iteration\n")
	sb.WriteString("2. What the next iteration should focus on\n")
	sb.WriteString("3. Any important context or decisions made\n")
	sb.WriteString("4. Known issues or blockers\n\n")
	sb.WriteString("**Keep notes concise and actionable** - no verbose logs, just key information for the next iteration.\n")

	return sb.String()
}

// ContainsCompletionSignal checks if the output contains the completion signal.
func ContainsCompletionSignal(output, signal string) bool {
	if signal == "" {
		return false
	}
	return strings.Contains(output, signal)
}
