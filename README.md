YouTubeSubtitleLearner – Offline Analyzer

Overview
- iPhone app that analyzes videos entirely on-device: caches video only when needed, extracts audio, performs on‑device speech recognition, builds word‑level timestamps, and generates subtitles. Data is saved locally per project.
- Network is used only when the user explicitly permits and provides an online video URL. For sites without direct media URLs, the app can play in an in‑app web view and capture app audio for analysis.

Key Features
- Local projects with subtitles + word tokens
- Long‑video chunked transcription with progress
- Language selection (locale) per analysis
- Auto‑scroll to current word during playback
- Import external subtitles (VTT/SRT/JSON)
- Project list with size meta, delete

No Server Dependencies
- Supabase and all remote backends have been removed. The repo folders that previously contained server code are no longer used.

Folders
- YouTubeSubtitleLearner/…  iOS app sources
- backend/                 Legacy (not used). Safe to delete if desired.
- subtitle-learner-expo/   Legacy (not used). Safe to delete if desired.

Build Notes
- Add `NSSpeechRecognitionUsageDescription` in Info.plist with a user‑visible reason.
- If you enable the web capture mode, ReplayKit screen/app‑audio capture must be available on device.

