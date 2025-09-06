#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

# Load .env
if [[ -f .env ]]; then
  set -a; source .env; set +a
fi

# Prefer Python 3.12 venv for stability (macOS)
if [[ -d .venv312 ]]; then
  source .venv312/bin/activate
elif command -v /opt/homebrew/opt/python@3.12/bin/python3.12 >/dev/null 2>&1; then
  /opt/homebrew/opt/python@3.12/bin/python3.12 -m venv .venv312
  source .venv312/bin/activate
else
  python3 -m venv .venv >/dev/null 2>&1 || true
  source .venv/bin/activate
fi

# Ensure temp dir exists for pip builds (macOS sandbox対策)
export TMPDIR=${TMPDIR:-/tmp}
# Prefer binary wheels to avoid local builds
export PIP_ONLY_BINARY=:\:all:\:

python -m pip install -U pip >/dev/null
# Preinstall wheels that sometimes trigger source builds
python -m pip install sentencepiece==0.2.0 tokenizers==0.22.0 onnxruntime==1.22.1 av==15.1.0 ctranslate2==4.6.0 >/dev/null 2>&1 || true
python -m pip install -r requirements.txt >/dev/null

if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "ffmpeg is required. Install with: brew install ffmpeg" >&2
  exit 1
fi

if [[ -z "${SUPABASE_URL:-}" || -z "${SUPABASE_SERVICE_ROLE_KEY:-}" ]]; then
  echo "Please set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY (in .env)" >&2
  exit 1
fi

if [[ "${1:-}" == "--daemon" ]]; then
  nohup python main.py > worker.log 2>&1 &
  echo "Worker started in background. Logs: backend/worker/python/worker.log"
  exit 0
fi

exec python main.py
