package main

import (
	"fmt"
	"os"

	"github.com/guzus/continuous-claude/internal/cli"
)

// Version information - set at build time
var (
	Version   = "0.15.0"
	BuildDate = "unknown"
	GitCommit = "unknown"
)

func main() {
	if err := cli.Execute(Version, BuildDate, GitCommit); err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}
}
