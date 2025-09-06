#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

if [[ -f .env ]]; then
  # Export all variables defined in .env to child processes
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

python3 -m venv .venv >/dev/null 2>&1 || true
source .venv/bin/activate
python -m pip install -U pip >/dev/null
python -m pip install -r requirements.txt >/dev/null

if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "ffmpeg is required. Install with: brew install ffmpeg" >&2
  exit 1
fi

if [[ -z "${SUPABASE_URL:-}" || -z "${SUPABASE_SERVICE_ROLE_KEY:-}" ]]; then
  echo "Please set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY (in .env)" >&2
  exit 1
fi

if [[ -z "${VIDEO_ID:-}" || -z "${LANG:-}" ]]; then
  echo "Please set VIDEO_ID and LANG (in .env)" >&2
  exit 1
fi

exec python main.py
