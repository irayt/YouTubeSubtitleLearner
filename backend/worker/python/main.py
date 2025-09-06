import os
import time
import tempfile
import subprocess
import uuid
from datetime import datetime, timezone
from typing import List, Dict, Optional, Tuple

import requests
from openai import OpenAI
try:
    # Optional: local/offline STT via faster-whisper
    from faster_whisper import WhisperModel  # type: ignore
except Exception:
    WhisperModel = None  # type: ignore
try:
    from argostranslate import package as argos_package
    from argostranslate import translate as argos_translate
except Exception:
    argos_package = None
    argos_translate = None
import webvtt

# --- Environment ---
SUPABASE_URL = os.environ.get("SUPABASE_URL")  # e.g., https://<project>.supabase.co
SERVICE_ROLE = os.environ.get("SUPABASE_SERVICE_ROLE_KEY")
OPENAI_API_KEY = os.environ.get("OPENAI_API_KEY")
POLL_INTERVAL_SECONDS = int(os.environ.get("POLL_INTERVAL_SECONDS", "5"))
DISABLE_STT = os.environ.get("DISABLE_STT", "0") in ("1", "true", "TRUE", "yes", "on")
MAX_AUDIO_SECONDS_ENV = os.environ.get("MAX_AUDIO_SECONDS")
MAX_AUDIO_SECONDS = int(MAX_AUDIO_SECONDS_ENV) if MAX_AUDIO_SECONDS_ENV and MAX_AUDIO_SECONDS_ENV.isdigit() else None
SINGLE_VIDEO_ID = os.environ.get("VIDEO_ID")
SINGLE_LANG = os.environ.get("LANG")
TRANSLATE_ENABLED = os.environ.get("TRANSLATE_ENABLED", "1") in ("1", "true", "TRUE", "yes", "on")
STORE_SOURCE_LANG = os.environ.get("STORE_SOURCE_LANG", "1") in ("1", "true", "TRUE", "yes", "on")
TRANSLATE_ENGINE = os.environ.get("TRANSLATE_ENGINE", "argos").lower()
ARGOS_AUTO_DOWNLOAD = os.environ.get("ARGOS_AUTO_DOWNLOAD", "1") in ("1", "true", "TRUE", "yes", "on")


def now_utc_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def auth_headers() -> Dict[str, str]:
    return {
        "apikey": SERVICE_ROLE,
        "Authorization": f"Bearer {SERVICE_ROLE}",
        "Content-Type": "application/json",
        "Prefer": "return=representation",
    }


def rest(path: str) -> str:
    return f"{SUPABASE_URL}/rest/v1{path}"


def fetch_youtube_vtt(video_id: str, lang: str) -> str | None:
    url = f"https://www.youtube.com/api/timedtext?lang={lang}&v={video_id}&fmt=vtt"
    r = requests.get(url, timeout=15)
    if r.status_code == 200 and r.text.strip():
        return r.text
    return None


def parse_vtt_to_items(vtt_text: str) -> List[Dict]:
    with tempfile.NamedTemporaryFile("w+", suffix=".vtt", delete=False) as f:
        f.write(vtt_text)
        f.flush()
        path = f.name
    items: List[Dict] = []
    try:
        for caption in webvtt.read(path):
            start_s = _timestamp_to_seconds(caption.start)
            end_s = _timestamp_to_seconds(caption.end)
            text = caption.text.strip()
            if text:
                items.append({
                    "start": start_s,
                    "duration": max(0.0, end_s - start_s),
                    "text": text,
                })
    finally:
        try:
            os.remove(path)
        except Exception:
            pass
    return items

def split_items_to_words(items: List[Dict]) -> List[Dict]:
    out: List[Dict] = []
    for si, it in enumerate(items):
        text = (it.get("text") or "").strip()
        if not text:
            continue
        words = [w for w in text.split() if w]
        if not words:
            continue
        start = float(it.get("start", 0.0))
        dur = float(it.get("duration", 0.0))
        step = (dur / len(words)) if dur > 0 and len(words) > 0 else 0.0
        for wi, w in enumerate(words):
            w_start = start + step * wi
            w_dur = max(0.0, step)
            out.append({
                "start": w_start,
                "duration": w_dur,
                "text": w,
                "sent_index": si,
                "word_index": wi,
            })
    return out


def _timestamp_to_seconds(ts: str) -> float:
    h, m, s = ts.split(":")
    return int(h) * 3600 + int(m) * 60 + float(s)


def download_youtube_audio(video_id: str, out_dir: str) -> str:
    out_path = os.path.join(out_dir, f"{video_id}-{uuid.uuid4().hex}.wav")
    cmd = [
        "yt-dlp",
        f"https://www.youtube.com/watch?v={video_id}",
        "-x",
        "--audio-format",
        "wav",
        "-o",
        out_path,
    ]
    subprocess.run(cmd, check=True)
    return out_path


def download_subtitles_via_ytdlp(video_id: str, lang: str, out_dir: str) -> Optional[str]:
    """Use yt-dlp to fetch subtitle VTT without downloading video.
    Returns path to a .vtt file if found, else None.
    """
    # Try human captions then auto captions
    for auto in (False, True):
        cmd = [
            "yt-dlp",
            f"https://www.youtube.com/watch?v={video_id}",
            "--skip-download",
            "--sub-format", "vtt",
            "--sub-lang", lang,
            "-o", os.path.join(out_dir, f"%(id)s.%(ext)s"),
        ]
        if auto:
            cmd.append("--write-auto-sub")
        else:
            cmd.append("--write-sub")
        try:
            subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except subprocess.CalledProcessError:
            continue
        # Find produced .vtt
        for fname in os.listdir(out_dir):
            if fname.endswith(".vtt") and video_id in fname:
                return os.path.join(out_dir, fname)
    return None


def clip_audio_if_needed(src_wav: str, out_dir: str) -> str:
    if not MAX_AUDIO_SECONDS:
        return src_wav
    clipped = os.path.join(out_dir, f"clipped-{os.path.basename(src_wav)}")
    # Resample to 16k mono for faster/cheaper STT
    cmd = [
        "ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
        "-i", src_wav,
        "-t", str(MAX_AUDIO_SECONDS),
        "-ac", "1", "-ar", "16000",
        clipped,
    ]
    subprocess.run(cmd, check=True)
    return clipped


def transcribe_with_whisper(audio_path: str, lang: str) -> Tuple[List[Dict], Optional[str], Optional[List[Dict]]]:
    """Unified STT: prefer local faster-whisper unless STT_ENGINE=openai."""
    if os.environ.get("STT_ENGINE", "faster_whisper").lower() != "openai":
        if WhisperModel is None:
            raise RuntimeError("faster-whisper not installed; set STT_ENGINE=openai or install faster-whisper")
        model_name = os.environ.get("FW_MODEL", "small")
        device = os.environ.get("FW_DEVICE", "cpu")
        compute_type = os.environ.get("FW_COMPUTE_TYPE", "int8")
        print(f"Transcribing with faster-whisper model={model_name} device={device} compute={compute_type} ...")
        model = WhisperModel(model_name, device=device, compute_type=compute_type)
        segments, info = model.transcribe(
            audio_path,
            language=lang or None,
            vad_filter=True,
            word_timestamps=True,
        )
        items: List[Dict] = []
        words_out: List[Dict] = []
        for seg in segments:
            txt = (seg.text or '').strip()
            if not txt:
                continue
            s = float(seg.start or 0.0)
            e = float(seg.end or 0.0)
            items.append({"start": s, "duration": max(0.0, e - s), "text": txt})
            for wi, w in enumerate(getattr(seg, 'words', []) or []):
                wtxt = (getattr(w, 'word', '') or '').strip()
                if not wtxt:
                    continue
                ws = float(getattr(w, 'start', 0.0) or 0.0)
                we = float(getattr(w, 'end', ws) or ws)
                words_out.append({
                    "start": ws,
                    "duration": max(0.0, we - ws),
                    "text": wtxt,
                    "sent_index": getattr(seg, 'id', None),
                    "word_index": wi,
                })
        src = getattr(info, 'language', None)
        print(f"Transcription done: {len(items)} segments; src_lang={src}")
        return items, src, (words_out if words_out else None)

    if not OPENAI_API_KEY:
        raise RuntimeError("Missing OPENAI_API_KEY")
    timeout = float(os.environ.get("OPENAI_REQUEST_TIMEOUT_SEC", "120"))
    print(f"Transcribing with Whisper (timeout={timeout}s)...")
    client = OpenAI(api_key=OPENAI_API_KEY, timeout=timeout)
    with open(audio_path, "rb") as f:
        tr = client.audio.transcriptions.create(
                model="whisper-1",
                file=f,
                response_format="verbose_json",
                language=lang if lang else None,
            )
    items: List[Dict] = []
    for seg in tr.segments:
        start = float(seg.get("start", 0.0))
        end = float(seg.get("end", start))
        text = (seg.get("text") or "").strip()
        if text:
            items.append({
                "start": start,
                "duration": max(0.0, end - start),
                "text": text,
            })
    src_lang = getattr(tr, "language", None)
    print(f"Transcription done: {len(items)} segments; src_lang={src_lang}")
    return items, src_lang, None


def translate_items(items: List[Dict], target_lang: str, source_lang: str | None = None) -> List[Dict]:
    if TRANSLATE_ENGINE == "openai":
        if not OPENAI_API_KEY:
            raise RuntimeError("Missing OPENAI_API_KEY for translation")
        client = OpenAI(api_key=OPENAI_API_KEY)
        out: List[Dict] = []
        chunk_size = 50
        sys = (
            f"You are a professional subtitle translator. Translate from {source_lang or 'auto-detected'} to {target_lang}. "
            "Keep the number of lines the same as the input. Return only the translations, one per line, no numbering."
        )
        for i in range(0, len(items), chunk_size):
            chunk = items[i:i+chunk_size]
            joined = "\n".join(x["text"].replace("\n", " ") for x in chunk)
            resp = client.chat.completions.create(
                model="gpt-4o-mini",
                messages=[{"role": "system", "content": sys}, {"role": "user", "content": joined}],
                temperature=0.2,
            )
            text = resp.choices[0].message.content or ""
            lines = [ln.strip() for ln in text.splitlines() if ln.strip()]
            if len(lines) != len(chunk):
                fixed: List[str] = []
                for x in chunk:
                    one = client.chat.completions.create(
                        model="gpt-4o-mini",
                        messages=[{"role": "system", "content": sys}, {"role": "user", "content": x["text"]}],
                        temperature=0.2,
                    ).choices[0].message.content or ""
                    fixed.append(one.strip())
                lines = fixed
            for j, ln in enumerate(lines):
                out.append({"start": chunk[j]["start"], "duration": chunk[j]["duration"], "text": ln})
        return out

    # Argos offline translation
    if argos_package is None or argos_translate is None:
        raise RuntimeError("argostranslate is not available; install it or set TRANSLATE_ENGINE=openai")
    if not source_lang:
        raise RuntimeError("source_lang is required for Argos translation (use STT-detected language)")
    # ensure package
    installed = argos_package.get_installed_packages()
    if not any(p.from_code == source_lang and p.to_code == target_lang for p in installed):
        if ARGOS_AUTO_DOWNLOAD:
            avail = argos_package.get_available_packages()
            match = next((p for p in avail if p.from_code == source_lang and p.to_code == target_lang), None)
            if match:
                path = argos_package.download_package(match)
                argos_package.install_from_path(path)
        installed = argos_package.get_installed_packages()
        if not any(p.from_code == source_lang and p.to_code == target_lang for p in installed):
            raise RuntimeError(f"Argos language pack not installed for {source_lang}->{target_lang}")
    translator = argos_translate.get_translation_from_codes(source_lang, target_lang)
    out: List[Dict] = []
    for it in items:
        out.append({"start": it["start"], "duration": it["duration"], "text": translator.translate(it["text"])})
    return out


def get_one_queued_job() -> Dict | None:
    r = requests.get(
        rest("/subtitle_jobs"),
        params={
            "select": "id,video_id,lang,created_at",
            "status": "eq.queued",
            "order": "created_at.asc",
            "limit": "1",
        },
        headers=auth_headers(),
        timeout=20,
    )
    r.raise_for_status()
    rows = r.json()
    return rows[0] if rows else None


def update_job(job_id: str, status: str, error_message: str | None = None) -> None:
    body = {"status": status, "updated_at": now_utc_iso()}
    if error_message:
        body["error_message"] = error_message[:500]
    r = requests.patch(
        rest("/subtitle_jobs"),
        params={"id": f"eq.{job_id}"},
        json=body,
        headers=auth_headers(),
        timeout=20,
    )
    r.raise_for_status()


def insert_subtitles(video_id: str, lang: str, items: List[Dict]) -> None:
    rows = [
        {
            "video_id": video_id,
            "lang": lang,
            "start": it["start"],
            "duration": it["duration"],
            "text": it["text"],
        }
        for it in items
    ]
    if not rows:
        return
    r = requests.post(rest("/subtitles"), json=rows, headers=auth_headers(), timeout=60)
    r.raise_for_status()

def insert_subtitle_words(video_id: str, lang: str, words: List[Dict]) -> None:
    if not words:
        return
    rows = [
        {
            "video_id": video_id,
            "lang": lang,
            "start": w["start"],
            "duration": w["duration"],
            "text": w["text"],
            "sent_index": w.get("sent_index"),
            "word_index": w.get("word_index"),
        }
        for w in words
    ]
    r = requests.post(rest("/subtitle_words"), json=rows, headers=auth_headers(), timeout=60)
    r.raise_for_status()


def process_one_job() -> bool:
    job = get_one_queued_job()
    if not job:
        return False
    job_id = job["id"]
    video_id = job["video_id"]
    lang = job["lang"]
    print(f"Processing job {job_id} {video_id} {lang}")
    update_job(job_id, "processing")
    try:
        items: List[Dict] = []
        # Prefer yt-dlp subtitle fetch for better compatibility
        with tempfile.TemporaryDirectory() as tmp_sub:
            vtt_path = download_subtitles_via_ytdlp(video_id, lang, tmp_sub)
            if vtt_path and os.path.exists(vtt_path):
                print("Subtitles via yt-dlp found. Parsing VTT...")
                with open(vtt_path, "r", encoding="utf-8", errors="ignore") as f:
                    vtt_text = f.read()
                items = parse_vtt_to_items(vtt_text)

        if not items:
            print("Trying public CC (timedtext)...")
            vtt = fetch_youtube_vtt(video_id, lang)
            if vtt:
                print("CC via timedtext. Parsing VTT...")
                items = parse_vtt_to_items(vtt)
        src_lang: str | None = None
        words: Optional[List[Dict]] = None
        if not items:
            if DISABLE_STT:
                raise RuntimeError("No CC and STT is disabled (set DISABLE_STT=0 to enable)")
            print("No CC or empty. Falling back to STT (yt-dlp + Whisper)...")
            with tempfile.TemporaryDirectory() as tmp:
                wav = download_youtube_audio(video_id, tmp)
                wav2 = clip_audio_if_needed(wav, tmp)
                items, src_lang, words = transcribe_with_whisper(wav2, lang)
        if not items:
            raise RuntimeError("No subtitles from CC nor STT")
        if words is None:
            words = split_items_to_words(items)
        # If we transcribed in another language, translate to requested
        if TRANSLATE_ENABLED and src_lang and src_lang.lower() != lang.lower():
            t_items = translate_items(items, target_lang=lang, source_lang=src_lang)
            insert_subtitles(video_id, lang, t_items)
            t_words = translate_items(words or [], target_lang=lang, source_lang=src_lang) if words else []
            insert_subtitle_words(video_id, lang, t_words)
            if STORE_SOURCE_LANG:
                insert_subtitles(video_id, src_lang, items)
                insert_subtitle_words(video_id, src_lang, words or [])
        else:
            insert_subtitles(video_id, lang, items)
            insert_subtitle_words(video_id, lang, words or [])
        update_job(job_id, "done")
        print(f"Job done: {len(items)} items")
    except Exception as e:
        update_job(job_id, "error", str(e))
        print(f"Job error: {e}")
    return True


def process_single(video_id: str, lang: str) -> None:
    print(f"Single-shot: {video_id} {lang}")
    try:
        items: List[Dict] = []
        src_lang: str | None = None
        words: Optional[List[Dict]] = None
        with tempfile.TemporaryDirectory() as tmp:
            vtt_path = download_subtitles_via_ytdlp(video_id, lang, tmp)
            if vtt_path and os.path.exists(vtt_path):
                with open(vtt_path, "r", encoding="utf-8", errors="ignore") as f:
                    items = parse_vtt_to_items(f.read())
        if not items:
            vtt = fetch_youtube_vtt(video_id, lang)
            if vtt:
                items = parse_vtt_to_items(vtt)
        if not items and not DISABLE_STT:
            with tempfile.TemporaryDirectory() as tmp:
                wav = download_youtube_audio(video_id, tmp)
                wav2 = clip_audio_if_needed(wav, tmp)
                items, src_lang, words = transcribe_with_whisper(wav2, lang)
        if not items:
            raise RuntimeError("No subtitles available (CC and STT disabled or failed)")
        # Ensure words
        if words is None:
            words = split_items_to_words(items)
        # Align with queue processing: translate if STT detected a different language
        if TRANSLATE_ENABLED and src_lang and src_lang.lower() != lang.lower():
            t_items = translate_items(items, target_lang=lang, source_lang=src_lang)
            insert_subtitles(video_id, lang, t_items)
            t_words = translate_items(words or [], target_lang=lang, source_lang=src_lang) if words else []
            insert_subtitle_words(video_id, lang, t_words)
            if STORE_SOURCE_LANG:
                insert_subtitles(video_id, src_lang, items)
                insert_subtitle_words(video_id, src_lang, words or [])
        else:
            insert_subtitles(video_id, lang, items)
            insert_subtitle_words(video_id, lang, words or [])
        print(f"Single-shot done: {len(items)} items")
    except Exception as e:
        print(f"Single-shot error: {e}")


def main():
    if not SUPABASE_URL or not SERVICE_ROLE:
        raise RuntimeError("Set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY")
    if SINGLE_VIDEO_ID and SINGLE_LANG:
        print("Worker started (single-shot mode)")
        process_single(SINGLE_VIDEO_ID, SINGLE_LANG)
        return
    print("Worker started (REST mode)")
    while True:
        try:
            did = process_one_job()
        except Exception as e:
            print(f"Fatal loop error: {e}")
            did = False
        time.sleep(1 if did else POLL_INTERVAL_SECONDS)


if __name__ == "__main__":
    main()
