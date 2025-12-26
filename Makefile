# Continuous Claude Makefile

# Build variables
BINARY_NAME := continuous-claude
VERSION := $(shell git describe --tags --always --dirty 2>/dev/null || echo "dev")
BUILD_DATE := $(shell date -u +"%Y-%m-%dT%H:%M:%SZ")
GIT_COMMIT := $(shell git rev-parse --short HEAD 2>/dev/null || echo "unknown")

# Go variables
GOPATH := $(shell go env GOPATH)
GOBIN := $(GOPATH)/bin
GOOS := $(shell go env GOOS)
GOARCH := $(shell go env GOARCH)

# Build flags
LDFLAGS := -ldflags "-s -w \
	-X main.Version=$(VERSION) \
	-X main.BuildDate=$(BUILD_DATE) \
	-X main.GitCommit=$(GIT_COMMIT)"

# Directories
BUILD_DIR := build
CMD_DIR := cmd/continuous-claude

.PHONY: all build clean install test lint fmt help

# Default target
all: build

# Build the binary
build:
	@echo "Building $(BINARY_NAME)..."
	@mkdir -p $(BUILD_DIR)
	go build $(LDFLAGS) -o $(BUILD_DIR)/$(BINARY_NAME) ./$(CMD_DIR)
	@echo "Built $(BUILD_DIR)/$(BINARY_NAME)"

# Build for all platforms
build-all: build-linux build-darwin build-windows

build-linux:
	@echo "Building for Linux..."
	@mkdir -p $(BUILD_DIR)
	GOOS=linux GOARCH=amd64 go build $(LDFLAGS) -o $(BUILD_DIR)/$(BINARY_NAME)-linux-amd64 ./$(CMD_DIR)
	GOOS=linux GOARCH=arm64 go build $(LDFLAGS) -o $(BUILD_DIR)/$(BINARY_NAME)-linux-arm64 ./$(CMD_DIR)

build-darwin:
	@echo "Building for macOS..."
	@mkdir -p $(BUILD_DIR)
	GOOS=darwin GOARCH=amd64 go build $(LDFLAGS) -o $(BUILD_DIR)/$(BINARY_NAME)-darwin-amd64 ./$(CMD_DIR)
	GOOS=darwin GOARCH=arm64 go build $(LDFLAGS) -o $(BUILD_DIR)/$(BINARY_NAME)-darwin-arm64 ./$(CMD_DIR)

build-windows:
	@echo "Building for Windows..."
	@mkdir -p $(BUILD_DIR)
	GOOS=windows GOARCH=amd64 go build $(LDFLAGS) -o $(BUILD_DIR)/$(BINARY_NAME)-windows-amd64.exe ./$(CMD_DIR)

# Install to GOBIN
install:
	@echo "Installing $(BINARY_NAME)..."
	go install $(LDFLAGS) ./$(CMD_DIR)
	@echo "Installed to $(GOBIN)/$(BINARY_NAME)"

# Clean build artifacts
clean:
	@echo "Cleaning..."
	@rm -rf $(BUILD_DIR)
	@go clean

# Run tests
test:
	@echo "Running tests..."
	go test -v -race -cover ./...

# Run tests with coverage
test-coverage:
	@echo "Running tests with coverage..."
	go test -v -race -coverprofile=coverage.out ./...
	go tool cover -html=coverage.out -o coverage.html
	@echo "Coverage report: coverage.html"

# Run linter
lint:
	@echo "Running linter..."
	@which golangci-lint > /dev/null || (echo "golangci-lint not found, installing..." && go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest)
	golangci-lint run ./...

# Format code
fmt:
	@echo "Formatting code..."
	go fmt ./...
	@echo "Done"

# Tidy dependencies
tidy:
	@echo "Tidying dependencies..."
	go mod tidy

# Download dependencies
deps:
	@echo "Downloading dependencies..."
	go mod download

# Run the application
run:
	@go run ./$(CMD_DIR) $(ARGS)

# Generate checksums
checksums:
	@echo "Generating checksums..."
	@cd $(BUILD_DIR) && sha256sum * > checksums.txt
	@cat $(BUILD_DIR)/checksums.txt

# Development build (no optimization)
dev:
	@echo "Building development version..."
	go build -o $(BUILD_DIR)/$(BINARY_NAME) ./$(CMD_DIR)

# Help
help:
	@echo "Continuous Claude - Build Commands"
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@echo "  build        Build the binary for current platform"
	@echo "  build-all    Build for all platforms (Linux, macOS, Windows)"
	@echo "  install      Install to GOBIN"
	@echo "  clean        Remove build artifacts"
	@echo "  test         Run tests"
	@echo "  test-coverage Run tests with coverage report"
	@echo "  lint         Run linter"
	@echo "  fmt          Format code"
	@echo "  tidy         Tidy go.mod dependencies"
	@echo "  deps         Download dependencies"
	@echo "  run          Run the application (use ARGS= for arguments)"
	@echo "  checksums    Generate SHA256 checksums for builds"
	@echo "  dev          Build development version"
	@echo "  help         Show this help message"
