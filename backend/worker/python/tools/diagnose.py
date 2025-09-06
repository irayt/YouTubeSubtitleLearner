#!/usr/bin/env python3
import os, subprocess, json, sys

def ok(msg):
    print(f"[ OK ] {msg}")

def warn(msg):
    print(f"[WARN] {msg}")

def fail(msg):
    print(f"[FAIL] {msg}")

def check_env():
    print("\n=== 1) ENV ===")
    need = ["SUPABASE_URL", "SUPABASE_SERVICE_ROLE_KEY"]
    missing = [k for k in need if not os.environ.get(k)]
    for k in need:
        v = os.environ.get(k, '')
        if v:
            ok(f"{k} set ({k=='SUPABASE_URL' and v or '***'})")
        else:
            fail(f"{k} missing")
    print("STT_ENGINE=", os.environ.get("STT_ENGINE", "(not set)"))
    print("TRANSLATE_ENGINE=", os.environ.get("TRANSLATE_ENGINE", "(not set)"))
    return not missing

def check_cmd(cmd, name):
    try:
        out = subprocess.check_output(cmd, stderr=subprocess.STDOUT, text=True)
        ok(f"{name}: {out.splitlines()[0]}")
        return True
    except Exception as e:
        fail(f"{name}: {e}")
        return False

def check_system():
    print("\n=== 2) System deps ===")
    a = check_cmd(["ffmpeg", "-version"], "ffmpeg")
    b = check_cmd(["yt-dlp", "--version"], "yt-dlp")
    return a and b

def check_args_translate():
    print("\n=== 3) Argos Translate ===")
    try:
        from argostranslate import package
        installed = package.get_installed_packages()
        pairs = [(p.from_code, p.to_code) for p in installed]
        print("installed:", pairs[:10], ("..." if len(pairs)>10 else ""))
        ok("argostranslate import OK")
        return True
    except Exception as e:
        fail(f"argostranslate import: {e}")
        return False

def check_faster_whisper():
    print("\n=== 4) faster-whisper ===")
    try:
        from faster_whisper import WhisperModel  # noqa: F401
        ok("faster-whisper import OK")
        print("(モデルのダウンロードは行いません。環境変数 FW_MODEL, FW_DEVICE を確認してください)")
        return True
    except Exception as e:
        fail(f"faster-whisper import: {e}")
        return False

def main():
    all_ok = True
    all_ok &= check_env()
    all_ok &= check_system()
    all_ok &= check_args_translate()
    all_ok &= check_faster_whisper()
    print("\n=== RESULT ===")
    if all_ok:
        ok("環境は概ね整っています。次は ./run-single.sh で単発テスト、または ./run-queue.sh --daemon で常駐を開始してください。")
        sys.exit(0)
    else:
        fail("不足があります。上の [FAIL] を順に解消してください。")
        sys.exit(1)

if __name__ == '__main__':
    main()

