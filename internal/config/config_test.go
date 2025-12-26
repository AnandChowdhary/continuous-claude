package config

import (
	"testing"
	"time"
)

func TestParseDuration(t *testing.T) {
	tests := []struct {
		input    string
		expected time.Duration
		wantErr  bool
	}{
		{"2h", 2 * time.Hour, false},
		{"30m", 30 * time.Minute, false},
		{"1h30m", 90 * time.Minute, false},
		{"2h30m15s", 2*time.Hour + 30*time.Minute + 15*time.Second, false},
		{"45s", 45 * time.Second, false},
		{"", 0, false},
		{"invalid", 0, true},
		{"abc123", 0, true},
	}

	for _, tt := range tests {
		t.Run(tt.input, func(t *testing.T) {
			result, err := ParseDuration(tt.input)
			if tt.wantErr {
				if err == nil {
					t.Errorf("ParseDuration(%q) expected error, got nil", tt.input)
				}
				return
			}
			if err != nil {
				t.Errorf("ParseDuration(%q) unexpected error: %v", tt.input, err)
				return
			}
			if result != tt.expected {
				t.Errorf("ParseDuration(%q) = %v, want %v", tt.input, result, tt.expected)
			}
		})
	}
}

func TestFormatDuration(t *testing.T) {
	tests := []struct {
		input    time.Duration
		expected string
	}{
		{0, "0s"},
		{30 * time.Second, "30s"},
		{5 * time.Minute, "5m"},
		{2 * time.Hour, "2h"},
		{90 * time.Minute, "1h30m"},
		{2*time.Hour + 30*time.Minute + 15*time.Second, "2h30m15s"},
	}

	for _, tt := range tests {
		t.Run(tt.expected, func(t *testing.T) {
			result := FormatDuration(tt.input)
			if result != tt.expected {
				t.Errorf("FormatDuration(%v) = %q, want %q", tt.input, result, tt.expected)
			}
		})
	}
}

func TestConfigValidate(t *testing.T) {
	tests := []struct {
		name    string
		config  *Config
		wantErr bool
	}{
		{
			name: "valid config with max runs",
			config: &Config{
				Prompt:              "test prompt",
				MaxRuns:             5,
				MergeStrategy:       "squash",
				CompletionThreshold: 3,
			},
			wantErr: false,
		},
		{
			name: "valid config with max cost",
			config: &Config{
				Prompt:              "test prompt",
				MaxCost:             10.00,
				MergeStrategy:       "squash",
				CompletionThreshold: 3,
			},
			wantErr: false,
		},
		{
			name: "valid config with max duration",
			config: &Config{
				Prompt:              "test prompt",
				MaxDuration:         2 * time.Hour,
				MergeStrategy:       "squash",
				CompletionThreshold: 3,
			},
			wantErr: false,
		},
		{
			name: "missing prompt",
			config: &Config{
				MaxRuns:             5,
				MergeStrategy:       "squash",
				CompletionThreshold: 3,
			},
			wantErr: true,
		},
		{
			name: "no limits set",
			config: &Config{
				Prompt:              "test prompt",
				MergeStrategy:       "squash",
				CompletionThreshold: 3,
			},
			wantErr: true,
		},
		{
			name: "invalid merge strategy",
			config: &Config{
				Prompt:              "test prompt",
				MaxRuns:             5,
				MergeStrategy:       "invalid",
				CompletionThreshold: 3,
			},
			wantErr: true,
		},
		{
			name: "invalid completion threshold",
			config: &Config{
				Prompt:              "test prompt",
				MaxRuns:             5,
				MergeStrategy:       "squash",
				CompletionThreshold: 0,
			},
			wantErr: true,
		},
		{
			name: "negative max runs",
			config: &Config{
				Prompt:              "test prompt",
				MaxRuns:             -1,
				MergeStrategy:       "squash",
				CompletionThreshold: 3,
			},
			wantErr: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := tt.config.Validate()
			if tt.wantErr {
				if err == nil {
					t.Errorf("Validate() expected error, got nil")
				}
			} else {
				if err != nil {
					t.Errorf("Validate() unexpected error: %v", err)
				}
			}
		})
	}
}

func TestDefaultConfig(t *testing.T) {
	cfg := DefaultConfig()

	if cfg.MergeStrategy != "squash" {
		t.Errorf("default MergeStrategy = %q, want %q", cfg.MergeStrategy, "squash")
	}

	if cfg.GitBranchPrefix != "continuous-claude/" {
		t.Errorf("default GitBranchPrefix = %q, want %q", cfg.GitBranchPrefix, "continuous-claude/")
	}

	if cfg.NotesFile != "SHARED_TASK_NOTES.md" {
		t.Errorf("default NotesFile = %q, want %q", cfg.NotesFile, "SHARED_TASK_NOTES.md")
	}

	if cfg.CompletionThreshold != 3 {
		t.Errorf("default CompletionThreshold = %d, want %d", cfg.CompletionThreshold, 3)
	}
}
