Python Worker (Cloud Run or any container)

What it does
- Polls subtitle_jobs for queued jobs.
- Tries YouTube public captions first; if missing, downloads audio with yt-dlp and runs Whisper API.
- Inserts normalized subtitles into public.subtitles and marks job done/error.

Environment variables
- SUPABASE_URL: your project URL
- SUPABASE_SERVICE_ROLE_KEY: service role key (server-only secret)
- STT_ENGINE: `faster_whisper` (local, default) or `openai`
- OPENAI_API_KEY: required for `STT_ENGINE=openai` and for translation
- TRANSLATE_ENABLED: `1` to translate STT to requested lang (default 1)
- STORE_SOURCE_LANG: `1` to also store the original STT language (default 1)
- POLL_INTERVAL_SECONDS: optional, default 5
- DISABLE_STT: set `1` to skip STT and require public CC only
- MAX_AUDIO_SECONDS: e.g. `90` to transcribe only the first N seconds (faster/cheaper)
- FW_MODEL / FW_DEVICE / FW_COMPUTE_TYPE: faster-whisper options (e.g., small / cpu / int8)

Local run (single‑shot, no Docker)
1) Copy `.env.example` to `.env` and fill values (at least SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, VIDEO_ID, LANG). Keep DISABLE_STT=1 if you want CC-only.
2) Run single video import:
   ./run-single.sh

Local run (queue mode)
1) Copy `.env.example` to `.env` and fill SUPABASE_URL/SUPABASE_SERVICE_ROLE_KEY. For STT, set OPENAI_API_KEY and DISABLE_STT=0 (optionally MAX_AUDIO_SECONDS=90).
2) Start the worker:
   ./run-queue.sh            # foreground
   ./run-queue.sh --daemon   # background with logs at worker.log

Container run (Docker)
1) Build: docker build -t subtitle-worker:latest .
2) Run:
   docker run --rm \
     -e SUPABASE_URL=... \
     -e SUPABASE_SERVICE_ROLE_KEY=... \
     -e OPENAI_API_KEY=... \  # only if STT enabled
      subtitle-worker:latest

Deploy to Cloud Run (example)
1) gcloud auth login && gcloud config set project YOUR_PROJECT
2) gcloud builds submit --tag gcr.io/YOUR_PROJECT/subtitle-worker
3) gcloud run deploy subtitle-worker \
     --image gcr.io/YOUR_PROJECT/subtitle-worker \
     --region YOUR_REGION \
     --allow-unauthenticated \
     --set-env-vars SUPABASE_URL=...,SUPABASE_SERVICE_ROLE_KEY=...,OPENAI_API_KEY=...

Notes
- Requires ffmpeg and yt-dlp (yt-dlp is installed via requirements; ffmpeg via brew on macOS).
- Ensure RLS on subtitle_jobs blocks anon; only Service Role is used here.
- Use your own/authorized videos to comply with YouTube policies.
