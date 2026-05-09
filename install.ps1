$ErrorActionPreference = "Stop"

$installDir = if ($env:INSTALL_DIR) { $env:INSTALL_DIR } else { Join-Path $HOME ".local/bin" }
$binaryName = "continuous-claude.ps1"
$repoUrl = if ($env:CONTINUOUS_CLAUDE_REPO_URL) { $env:CONTINUOUS_CLAUDE_REPO_URL } else { "https://raw.githubusercontent.com/AnandChowdhary/continuous-claude/main" }
$targetPath = Join-Path $installDir $binaryName

Write-Host "Installing Continuous Claude PowerShell..."

New-Item -ItemType Directory -Force -Path $installDir | Out-Null

Write-Host "Downloading $binaryName..."
try {
    Invoke-WebRequest -Uri "$repoUrl/continuous_claude.ps1" -OutFile $targetPath
} catch {
    Write-Error "Failed to download $binaryName from $repoUrl"
    exit 1
}

Write-Host "Installed $binaryName to $targetPath"

$pathEntries = @($env:PATH -split [IO.Path]::PathSeparator)
if ($pathEntries -notcontains $installDir) {
    Write-Warning "$installDir is not in your PATH"
    Write-Host ""
    Write-Host "To add it for your current PowerShell session:"
    Write-Host "  `$env:PATH = `"$installDir$([IO.Path]::PathSeparator)`$env:PATH`""
    Write-Host ""
    Write-Host "To add it persistently for your user account:"
    Write-Host "  [Environment]::SetEnvironmentVariable('PATH', `"$installDir$([IO.Path]::PathSeparator)`" + [Environment]::GetEnvironmentVariable('PATH', 'User'), 'User')"
}

Write-Host ""
Write-Host "Checking dependencies..."

$missing = [System.Collections.Generic.List[string]]::new()
if (-not (Get-Command claude -ErrorAction SilentlyContinue) -and -not (Get-Command codex -ErrorAction SilentlyContinue)) {
    [void]$missing.Add("Claude Code CLI or Codex CLI")
}
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    [void]$missing.Add("Git")
}
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    [void]$missing.Add("GitHub CLI")
}

if ($missing.Count -eq 0) {
    Write-Host "All dependencies installed"
} else {
    Write-Warning "Missing dependencies:"
    foreach ($dependency in $missing) {
        Write-Host "  - $dependency"
    }
    Write-Host ""
    Write-Host "Install them with:"
    Write-Host "  winget install --id Git.Git -e"
    Write-Host "  winget install --id GitHub.cli -e"
    Write-Host "  npm install -g @anthropic-ai/claude-code"
    Write-Host "  npm install -g @openai/codex"
}

Write-Host ""
Write-Host "Installation complete."
Write-Host ""
Write-Host "Get started with:"
Write-Host "  pwsh $targetPath --prompt `"your task`" --max-runs 5"
Write-Host "  pwsh $targetPath --provider codex --prompt `"your task`" --max-runs 5"
