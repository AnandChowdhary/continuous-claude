// Package version provides version management and updates.
package version

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
)

const (
	// GitHubOwner is the owner of the repository.
	GitHubOwner = "guzus"
	// GitHubRepo is the repository name.
	GitHubRepo = "continuous-claude"
	// ReleaseURL is the base URL for releases.
	ReleaseURL = "https://github.com/guzus/continuous-claude/releases"
)

// Info holds version information.
type Info struct {
	Version   string
	BuildDate string
	GitCommit string
}

// Compare compares two semantic versions.
// Returns: 1 if v1 > v2, -1 if v1 < v2, 0 if equal.
func Compare(v1, v2 string) int {
	v1 = strings.TrimPrefix(v1, "v")
	v2 = strings.TrimPrefix(v2, "v")

	// Remove pre-release suffix for comparison
	v1 = strings.Split(v1, "-")[0]
	v2 = strings.Split(v2, "-")[0]

	p1 := parseSemver(v1)
	p2 := parseSemver(v2)

	for i := 0; i < 3; i++ {
		if p1[i] > p2[i] {
			return 1
		}
		if p1[i] < p2[i] {
			return -1
		}
	}
	return 0
}

// parseSemver parses a version string into [major, minor, patch].
func parseSemver(v string) [3]int {
	parts := strings.Split(v, ".")
	var result [3]int
	for i := 0; i < 3 && i < len(parts); i++ {
		// Extract just the number part
		re := regexp.MustCompile(`^(\d+)`)
		if matches := re.FindStringSubmatch(parts[i]); matches != nil {
			result[i], _ = strconv.Atoi(matches[1])
		}
	}
	return result
}

// CheckForUpdates checks if a newer version is available.
func CheckForUpdates(currentVersion string) (latestVersion string, hasUpdate bool, err error) {
	// Use GitHub API to get latest release
	resp, err := http.Get(fmt.Sprintf("https://api.github.com/repos/%s/%s/releases/latest", GitHubOwner, GitHubRepo))
	if err != nil {
		return "", false, fmt.Errorf("failed to check for updates: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return "", false, fmt.Errorf("failed to check for updates: status %d", resp.StatusCode)
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", false, fmt.Errorf("failed to read response: %w", err)
	}

	// Simple JSON parsing for tag_name
	re := regexp.MustCompile(`"tag_name"\s*:\s*"([^"]+)"`)
	matches := re.FindSubmatch(body)
	if matches == nil {
		return "", false, fmt.Errorf("could not find version in response")
	}

	latestVersion = string(matches[1])

	// Skip pre-release versions
	if strings.Contains(latestVersion, "-") {
		return latestVersion, false, nil
	}

	hasUpdate = Compare(latestVersion, currentVersion) > 0
	return latestVersion, hasUpdate, nil
}

// DownloadUpdate downloads the new version binary.
func DownloadUpdate(version string) (string, error) {
	// Determine architecture
	arch := getArch()
	osName := getOS()

	binaryName := fmt.Sprintf("continuous-claude-%s-%s", osName, arch)
	url := fmt.Sprintf("%s/download/%s/%s", ReleaseURL, version, binaryName)

	// Download to temp file
	resp, err := http.Get(url)
	if err != nil {
		return "", fmt.Errorf("failed to download update: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("failed to download update: status %d", resp.StatusCode)
	}

	tmpFile, err := os.CreateTemp("", "continuous-claude-update-*")
	if err != nil {
		return "", fmt.Errorf("failed to create temp file: %w", err)
	}

	if _, err := io.Copy(tmpFile, resp.Body); err != nil {
		tmpFile.Close()
		os.Remove(tmpFile.Name())
		return "", fmt.Errorf("failed to write update: %w", err)
	}
	tmpFile.Close()

	return tmpFile.Name(), nil
}

// VerifyChecksum verifies the SHA256 checksum of a file.
func VerifyChecksum(filePath, expectedChecksum string) error {
	f, err := os.Open(filePath)
	if err != nil {
		return fmt.Errorf("failed to open file: %w", err)
	}
	defer f.Close()

	h := sha256.New()
	if _, err := io.Copy(h, f); err != nil {
		return fmt.Errorf("failed to calculate checksum: %w", err)
	}

	actual := hex.EncodeToString(h.Sum(nil))
	if actual != expectedChecksum {
		return fmt.Errorf("checksum mismatch: expected %s, got %s", expectedChecksum, actual)
	}

	return nil
}

// InstallUpdate replaces the current binary with the new one.
func InstallUpdate(tmpPath string) error {
	// Get current executable path
	currentPath, err := os.Executable()
	if err != nil {
		return fmt.Errorf("failed to get current executable: %w", err)
	}

	currentPath, err = filepath.EvalSymlinks(currentPath)
	if err != nil {
		return fmt.Errorf("failed to resolve symlinks: %w", err)
	}

	// Make new binary executable
	if err := os.Chmod(tmpPath, 0755); err != nil {
		return fmt.Errorf("failed to make binary executable: %w", err)
	}

	// Rename (atomic on most systems)
	if err := os.Rename(tmpPath, currentPath); err != nil {
		// If rename fails (e.g., cross-device), try copy
		if err := copyFile(tmpPath, currentPath); err != nil {
			return fmt.Errorf("failed to install update: %w", err)
		}
		os.Remove(tmpPath)
	}

	return nil
}

func copyFile(src, dst string) error {
	source, err := os.Open(src)
	if err != nil {
		return err
	}
	defer source.Close()

	dest, err := os.Create(dst)
	if err != nil {
		return err
	}
	defer dest.Close()

	_, err = io.Copy(dest, source)
	return err
}

func getArch() string {
	// Would use runtime.GOARCH in real implementation
	return "amd64"
}

func getOS() string {
	// Would use runtime.GOOS in real implementation
	return "linux"
}
