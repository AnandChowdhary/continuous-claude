package version

import (
	"testing"
)

func TestCompare(t *testing.T) {
	tests := []struct {
		v1       string
		v2       string
		expected int
	}{
		{"v1.0.0", "v1.0.0", 0},
		{"1.0.0", "1.0.0", 0},
		{"v1.0.1", "v1.0.0", 1},
		{"v1.1.0", "v1.0.0", 1},
		{"v2.0.0", "v1.0.0", 1},
		{"v1.0.0", "v1.0.1", -1},
		{"v1.0.0", "v1.1.0", -1},
		{"v1.0.0", "v2.0.0", -1},
		{"v0.15.0", "v0.14.0", 1},
		{"v0.14.0", "v0.15.0", -1},
		{"v1.0.0-dev", "v1.0.0", 0}, // Pre-release suffix ignored
		{"v1.0.0-alpha", "v1.0.0-beta", 0},
	}

	for _, tt := range tests {
		t.Run(tt.v1+"_vs_"+tt.v2, func(t *testing.T) {
			result := Compare(tt.v1, tt.v2)
			if result != tt.expected {
				t.Errorf("Compare(%q, %q) = %d, want %d", tt.v1, tt.v2, result, tt.expected)
			}
		})
	}
}

func TestParseSemver(t *testing.T) {
	tests := []struct {
		input    string
		expected [3]int
	}{
		{"1.2.3", [3]int{1, 2, 3}},
		{"0.15.0", [3]int{0, 15, 0}},
		{"10.20.30", [3]int{10, 20, 30}},
		{"1.0", [3]int{1, 0, 0}},
		{"1", [3]int{1, 0, 0}},
		{"", [3]int{0, 0, 0}},
	}

	for _, tt := range tests {
		t.Run(tt.input, func(t *testing.T) {
			result := parseSemver(tt.input)
			if result != tt.expected {
				t.Errorf("parseSemver(%q) = %v, want %v", tt.input, result, tt.expected)
			}
		})
	}
}
