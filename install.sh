#!/bin/bash

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"
BINARY_NAME="continuous-claude"
REPO_URL="https://raw.githubusercontent.com/AnandChowdhary/continuous-claude/main"

echo "🔂 Installing Continuous Claude..."

# Create install directory if it doesn't exist
mkdir -p "$INSTALL_DIR"

# Download the script
echo "📥 Downloading $BINARY_NAME..."
if ! curl -fsSL "$REPO_URL/continuous_claude.sh" -o "$INSTALL_DIR/$BINARY_NAME"; then
    echo -e "${RED}❌ Failed to download $BINARY_NAME${NC}" >&2
    exit 1
fi

# Make it executable
chmod +x "$INSTALL_DIR/$BINARY_NAME"

echo -e "${GREEN}✅ $BINARY_NAME installed to $INSTALL_DIR/$BINARY_NAME${NC}"

# Check if install directory is in PATH
if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
    echo -e "${YELLOW}⚠️  Warning: $INSTALL_DIR is not in your PATH${NC}"
    echo ""
    echo "To add it to your PATH, add this line to your shell profile:"
    echo ""
    
    # Detect shell
    if [[ "$SHELL" == *"zsh"* ]]; then
        echo "  echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.zshrc"
        echo "  source ~/.zshrc"
    elif [[ "$SHELL" == *"bash"* ]]; then
        echo "  echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.bashrc"
        echo "  source ~/.bashrc"
    else
        echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
    fi
    echo ""
fi

# Check for dependencies
echo ""
echo "🔍 Checking dependencies..."

missing_deps=()

has_agent=false
if command -v claude &> /dev/null || command -v codex &> /dev/null; then
    has_agent=true
fi

if [ "$has_agent" = "false" ]; then
    missing_deps+=("Claude Code CLI or Codex CLI")
fi

if ! command -v gh &> /dev/null; then
    missing_deps+=("GitHub CLI")
fi

if ! command -v jq &> /dev/null; then
    missing_deps+=("jq")
fi

if [ ${#missing_deps[@]} -eq 0 ]; then
    echo -e "${GREEN}✅ All dependencies installed${NC}"
else
    echo -e "${YELLOW}⚠️  Missing dependencies:${NC}"
    for dep in "${missing_deps[@]}"; do
        echo "   - $dep"
    done
    echo ""
    echo "Install them with:"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "  brew install gh jq"
        echo "  brew install --cask claude-code"
        echo "  npm install -g @openai/codex  # optional Codex provider"
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        echo "  # Install GitHub CLI: https://github.com/cli/cli#installation"
        echo "  sudo apt-get install jq  # or equivalent for your distro"
        echo "  # Install Claude Code CLI: https://code.claude.com"
        echo "  # Install Codex CLI: https://help.openai.com/en/articles/11096431"
    fi
fi

echo ""
echo -e "${GREEN}🎉 Installation complete!${NC}"
echo ""
echo "Get started with:"
echo "  $BINARY_NAME --prompt \"your task\" --max-runs 5 --owner YourGitHubUser --repo your-repo"
echo "  $BINARY_NAME --provider codex --prompt \"your task\" --max-runs 5 --owner YourGitHubUser --repo your-repo"
echo ""
echo "For more information, visit: https://github.com/AnandChowdhary/continuous-claude"
