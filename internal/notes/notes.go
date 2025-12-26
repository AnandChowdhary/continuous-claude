// Package notes provides SHARED_TASK_NOTES.md file handling.
package notes

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// Manager handles notes file operations.
type Manager struct {
	filePath string
}

// NewManager creates a new notes manager.
func NewManager(filePath string) *Manager {
	return &Manager{filePath: filePath}
}

// Exists checks if the notes file exists.
func (m *Manager) Exists() bool {
	_, err := os.Stat(m.filePath)
	return err == nil
}

// Read returns the contents of the notes file.
func (m *Manager) Read() (string, error) {
	if !m.Exists() {
		return "", nil
	}

	content, err := os.ReadFile(m.filePath)
	if err != nil {
		return "", fmt.Errorf("failed to read notes file: %w", err)
	}

	return string(content), nil
}

// Write writes content to the notes file.
func (m *Manager) Write(content string) error {
	dir := filepath.Dir(m.filePath)
	if dir != "." && dir != "" {
		if err := os.MkdirAll(dir, 0755); err != nil {
			return fmt.Errorf("failed to create notes directory: %w", err)
		}
	}

	if err := os.WriteFile(m.filePath, []byte(content), 0644); err != nil {
		return fmt.Errorf("failed to write notes file: %w", err)
	}

	return nil
}

// Initialize creates the notes file with initial content if it doesn't exist.
func (m *Manager) Initialize(projectGoal string) error {
	if m.Exists() {
		return nil
	}

	content := fmt.Sprintf(`# Shared Task Notes

## Project Goal
%s

## Current Status
- Iteration 1 starting
- No previous work done yet

## Next Steps
- Begin initial implementation based on project goal

## Notes
- Created: %s

---
*This file is maintained by Continuous Claude to preserve context across iterations.*
`, projectGoal, time.Now().Format("2006-01-02 15:04:05"))

	return m.Write(content)
}

// GetPath returns the absolute path to the notes file.
func (m *Manager) GetPath() string {
	absPath, err := filepath.Abs(m.filePath)
	if err != nil {
		return m.filePath
	}
	return absPath
}

// Validate checks if the notes file content is reasonable.
func (m *Manager) Validate() error {
	content, err := m.Read()
	if err != nil {
		return err
	}

	// Check for verbose content (too long)
	lines := strings.Split(content, "\n")
	if len(lines) > 200 {
		return fmt.Errorf("notes file is too long (%d lines) - consider condensing", len(lines))
	}

	// Check for common issues
	if strings.Contains(strings.ToLower(content), "error log:") ||
		strings.Contains(strings.ToLower(content), "full output:") ||
		strings.Contains(strings.ToLower(content), "stack trace:") {
		return fmt.Errorf("notes file contains verbose logs - keep it concise and actionable")
	}

	return nil
}

// AppendIteration adds iteration summary to the notes.
func (m *Manager) AppendIteration(iteration int, summary string) error {
	content, err := m.Read()
	if err != nil {
		return err
	}

	timestamp := time.Now().Format("2006-01-02 15:04:05")
	newContent := fmt.Sprintf(`---

## Iteration %d Summary (%s)

%s

%s`, iteration, timestamp, summary, content)

	return m.Write(newContent)
}
