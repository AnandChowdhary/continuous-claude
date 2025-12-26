// Package ui provides terminal output and formatting.
package ui

import (
	"fmt"
	"os"
	"strings"
	"time"

	"github.com/briandowns/spinner"
	"github.com/fatih/color"
)

// Colors
var (
	Green   = color.New(color.FgGreen).SprintFunc()
	Yellow  = color.New(color.FgYellow).SprintFunc()
	Red     = color.New(color.FgRed).SprintFunc()
	Blue    = color.New(color.FgBlue).SprintFunc()
	Cyan    = color.New(color.FgCyan).SprintFunc()
	Bold    = color.New(color.Bold).SprintFunc()
	Dim     = color.New(color.Faint).SprintFunc()
)

// Printer handles formatted output.
type Printer struct {
	verbose bool
	spinner *spinner.Spinner
}

// NewPrinter creates a new printer.
func NewPrinter(verbose bool) *Printer {
	s := spinner.New(spinner.CharSets[14], 100*time.Millisecond)
	s.Writer = os.Stderr
	return &Printer{
		verbose: verbose,
		spinner: s,
	}
}

// Header prints a section header.
func (p *Printer) Header(text string) {
	fmt.Printf("\n%s %s\n", Bold("==="), Bold(text))
}

// SubHeader prints a sub-section header.
func (p *Printer) SubHeader(text string) {
	fmt.Printf("\n%s %s\n", Bold("---"), text)
}

// Info prints an info message.
func (p *Printer) Info(format string, args ...interface{}) {
	fmt.Printf("%s %s\n", Blue("ℹ"), fmt.Sprintf(format, args...))
}

// Success prints a success message.
func (p *Printer) Success(format string, args ...interface{}) {
	fmt.Printf("%s %s\n", Green("✓"), fmt.Sprintf(format, args...))
}

// Warning prints a warning message.
func (p *Printer) Warning(format string, args ...interface{}) {
	fmt.Printf("%s %s\n", Yellow("⚠"), fmt.Sprintf(format, args...))
}

// Error prints an error message.
func (p *Printer) Error(format string, args ...interface{}) {
	fmt.Printf("%s %s\n", Red("✗"), fmt.Sprintf(format, args...))
}

// Debug prints a debug message (only if verbose).
func (p *Printer) Debug(format string, args ...interface{}) {
	if p.verbose {
		fmt.Printf("%s %s\n", Dim("[debug]"), fmt.Sprintf(format, args...))
	}
}

// Iteration prints iteration start.
func (p *Printer) Iteration(current, max int) {
	var display string
	if max > 0 {
		display = fmt.Sprintf("(%d/%d)", current, max)
	} else {
		display = fmt.Sprintf("(%d)", current)
	}
	fmt.Printf("\n%s %s Starting iteration %s\n", Blue("🔄"), Bold(display), Cyan(fmt.Sprintf("#%d", current)))
}

// Cost prints cost information.
func (p *Printer) Cost(iterationCost, totalCost float64) {
	fmt.Printf("%s Iteration cost: %s | Total: %s\n",
		Dim("💰"),
		Yellow(fmt.Sprintf("$%.4f", iterationCost)),
		Bold(fmt.Sprintf("$%.4f", totalCost)))
}

// Duration prints duration information.
func (p *Printer) Duration(elapsed, max time.Duration) {
	var maxStr string
	if max > 0 {
		maxStr = fmt.Sprintf(" / %s", formatDuration(max))
	}
	fmt.Printf("%s Elapsed: %s%s\n", Dim("⏱"), formatDuration(elapsed), maxStr)
}

// PRStatus prints PR check status.
func (p *Printer) PRStatus(checksPassed, hasPending, hasFailed bool, reviewStatus string) {
	var checkIcon, checkMsg string
	if hasFailed {
		checkIcon = Red("✗")
		checkMsg = Red("Checks failed")
	} else if hasPending {
		checkIcon = Yellow("○")
		checkMsg = Yellow("Checks pending")
	} else {
		checkIcon = Green("✓")
		checkMsg = Green("All checks passed")
	}

	var reviewIcon, reviewMsg string
	switch reviewStatus {
	case "APPROVED":
		reviewIcon = Green("✓")
		reviewMsg = Green("Approved")
	case "CHANGES_REQUESTED":
		reviewIcon = Red("✗")
		reviewMsg = Red("Changes requested")
	case "":
		reviewIcon = Dim("○")
		reviewMsg = Dim("No reviews")
	default:
		reviewIcon = Yellow("○")
		reviewMsg = Yellow("Review pending")
	}

	fmt.Printf("  %s Checks: %s | %s Review: %s\n", checkIcon, checkMsg, reviewIcon, reviewMsg)
}

// StartSpinner starts the spinner with a message.
func (p *Printer) StartSpinner(message string) {
	p.spinner.Suffix = " " + message
	p.spinner.Start()
}

// UpdateSpinner updates the spinner message.
func (p *Printer) UpdateSpinner(message string) {
	p.spinner.Suffix = " " + message
}

// StopSpinner stops the spinner.
func (p *Printer) StopSpinner() {
	p.spinner.Stop()
}

// Box prints text in a box.
func (p *Printer) Box(title, content string) {
	width := 60
	fmt.Println()
	fmt.Println(strings.Repeat("─", width))
	if title != "" {
		fmt.Printf("│ %s\n", Bold(title))
		fmt.Println(strings.Repeat("─", width))
	}
	for _, line := range strings.Split(content, "\n") {
		fmt.Printf("│ %s\n", line)
	}
	fmt.Println(strings.Repeat("─", width))
}

// Summary prints a run summary.
func (p *Printer) Summary(iterations int, totalCost float64, elapsed time.Duration, completed bool) {
	fmt.Println()
	fmt.Println(strings.Repeat("═", 50))
	fmt.Printf("  %s\n", Bold("Run Summary"))
	fmt.Println(strings.Repeat("─", 50))
	fmt.Printf("  Iterations completed: %s\n", Cyan(fmt.Sprintf("%d", iterations)))
	fmt.Printf("  Total cost: %s\n", Yellow(fmt.Sprintf("$%.4f", totalCost)))
	fmt.Printf("  Total time: %s\n", formatDuration(elapsed))

	if completed {
		fmt.Printf("  Status: %s\n", Green("Completed (project goal reached)"))
	} else {
		fmt.Printf("  Status: %s\n", Yellow("Limit reached"))
	}
	fmt.Println(strings.Repeat("═", 50))
}

// Table prints a simple table.
func (p *Printer) Table(headers []string, rows [][]string) {
	// Calculate column widths
	widths := make([]int, len(headers))
	for i, h := range headers {
		widths[i] = len(h)
	}
	for _, row := range rows {
		for i, cell := range row {
			if len(cell) > widths[i] {
				widths[i] = len(cell)
			}
		}
	}

	// Print header
	for i, h := range headers {
		fmt.Printf("%-*s  ", widths[i], Bold(h))
	}
	fmt.Println()

	// Print separator
	for i := range headers {
		fmt.Printf("%s  ", strings.Repeat("─", widths[i]))
	}
	fmt.Println()

	// Print rows
	for _, row := range rows {
		for i, cell := range row {
			fmt.Printf("%-*s  ", widths[i], cell)
		}
		fmt.Println()
	}
}

// Prompt prints a prompt and waits for input.
func (p *Printer) Prompt(message string) string {
	fmt.Printf("%s %s: ", Blue("?"), message)
	var input string
	fmt.Scanln(&input)
	return strings.TrimSpace(input)
}

// Confirm prints a confirmation prompt.
func (p *Printer) Confirm(message string) bool {
	fmt.Printf("%s %s [y/N]: ", Yellow("?"), message)
	var input string
	fmt.Scanln(&input)
	input = strings.ToLower(strings.TrimSpace(input))
	return input == "y" || input == "yes"
}

func formatDuration(d time.Duration) string {
	if d < time.Minute {
		return fmt.Sprintf("%ds", int(d.Seconds()))
	}
	if d < time.Hour {
		return fmt.Sprintf("%dm%ds", int(d.Minutes()), int(d.Seconds())%60)
	}
	hours := int(d.Hours())
	minutes := int(d.Minutes()) % 60
	return fmt.Sprintf("%dh%dm", hours, minutes)
}
