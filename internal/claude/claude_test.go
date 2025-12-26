package claude

import (
	"strings"
	"testing"
)

func TestContainsCompletionSignal(t *testing.T) {
	tests := []struct {
		output   string
		signal   string
		expected bool
	}{
		{"The project is done. CONTINUOUS_CLAUDE_PROJECT_COMPLETE", "CONTINUOUS_CLAUDE_PROJECT_COMPLETE", true},
		{"Normal output without signal", "CONTINUOUS_CLAUDE_PROJECT_COMPLETE", false},
		{"", "CONTINUOUS_CLAUDE_PROJECT_COMPLETE", false},
		{"CONTINUOUS_CLAUDE_PROJECT_COMPLETE", "", false},
		{"", "", false},
		{"Contains CUSTOM_SIGNAL in text", "CUSTOM_SIGNAL", true},
	}

	for _, tt := range tests {
		t.Run(tt.output[:min(20, len(tt.output))], func(t *testing.T) {
			result := ContainsCompletionSignal(tt.output, tt.signal)
			if result != tt.expected {
				t.Errorf("ContainsCompletionSignal(%q, %q) = %v, want %v", tt.output, tt.signal, result, tt.expected)
			}
		})
	}
}

func TestBuildPrompt(t *testing.T) {
	userPrompt := "Add test coverage"
	notesContent := "Previous work completed"
	completionSignal := "DONE"
	iteration := 3

	result := BuildPrompt(userPrompt, notesContent, completionSignal, iteration)

	// Check that key elements are present
	if !strings.Contains(result, "CONTINUOUS WORKFLOW CONTEXT") {
		t.Error("prompt should contain workflow context header")
	}

	if !strings.Contains(result, "iteration #3") {
		t.Error("prompt should contain iteration number")
	}

	if !strings.Contains(result, userPrompt) {
		t.Error("prompt should contain user prompt")
	}

	if !strings.Contains(result, notesContent) {
		t.Error("prompt should contain notes content")
	}

	if !strings.Contains(result, completionSignal) {
		t.Error("prompt should contain completion signal")
	}

	if !strings.Contains(result, "PRIMARY GOAL") {
		t.Error("prompt should contain primary goal section")
	}

	if !strings.Contains(result, "CONTEXT FROM PREVIOUS ITERATION") {
		t.Error("prompt should contain previous iteration context section")
	}

	if !strings.Contains(result, "ITERATION NOTES") {
		t.Error("prompt should contain iteration notes section")
	}
}

func TestBuildPromptWithoutNotes(t *testing.T) {
	result := BuildPrompt("Test prompt", "", "COMPLETE", 1)

	// Should not contain previous iteration section if no notes
	if strings.Contains(result, "CONTEXT FROM PREVIOUS ITERATION") {
		t.Error("prompt should not contain previous iteration section when notes are empty")
	}
}

func TestBuildPromptWithoutCompletionSignal(t *testing.T) {
	result := BuildPrompt("Test prompt", "", "", 1)

	// Should not contain completion signal section if empty
	if strings.Contains(result, "Project Completion Signal") {
		t.Error("prompt should not contain completion signal section when signal is empty")
	}
}

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}
