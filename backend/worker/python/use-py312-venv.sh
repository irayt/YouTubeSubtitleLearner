#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

# Create a Python 3.12 virtualenv via Homebrew (macOS)
if ! command -v /opt/homebrew/opt/python@3.12/bin/python3.12 >/dev/null 2>&1; then
  echo "python@3.12 (Homebrew) not found. Install with: brew install python@3.12" >&2
  exit 1
fi

/opt/homebrew/opt/python@3.12/bin/python3.12 -m venv .venv312
echo "Created .venv312 with Python 3.12"
echo "Run: source .venv312/bin/activate && pip install -U pip && pip install -r requirements.txt"

