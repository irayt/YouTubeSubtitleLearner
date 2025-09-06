#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

# Prefer Python 3.12 venv for stability
if [ -d .venv312 ]; then
  source .venv312/bin/activate
else
  if command -v /opt/homebrew/opt/python@3.12/bin/python3.12 >/dev/null 2>&1; then
    /opt/homebrew/opt/python@3.12/bin/python3.12 -m venv .venv312
    source .venv312/bin/activate
  else
    python3 -m venv .venv
    source .venv/bin/activate
  fi
fi

# Make sure TMPDIR exists for pip build envs
export TMPDIR=${TMPDIR:-/tmp}

python -m pip install -U pip >/dev/null

# Preinstall wheels that sometimes trigger source builds
python -m pip install --only-binary=:all: sentencepiece==0.2.0 tokenizers==0.22.0 onnxruntime==1.22.1 av==15.1.0 ctranslate2==4.6.0 || true

python -m pip install -r requirements.txt >/dev/null
# Load .env if present so diagnose sees actual values
if [ -f .env ]; then
  set -a
  # shellcheck disable=SC1091
  . ./.env
  set +a
fi

python tools/diagnose.py
