 iOS App Setup (Offline Edition)

1) Build & Run
- Xcode で `YouTubeSubtitleLearner` を開き、そのままビルド/実行

2) 字幕データの用意
- 画面上部の「インポート(VTT/SRT/JSON)」ボタンから、端末内の字幕ファイルを選択します
- 対応形式: WebVTT(.vtt) / SRT(.srt) / JSON（`[ { start, duration, text }, ... ]`）
- インポート後、単語ごとのタイムスタンプを近似生成し、自動追従スクロールが有効になります

3) ローカル保存
- 「保存」ボタンで、ドキュメントフォルダに `subtitles.json` / `words.json` として保存します
- 次回起動時は保存済みデータを自動で読み込みます

Notes
- 本アプリは完全オフラインで動作します。Supabase/ログイン等は不要です
- 同梱の `subtitles.json`（サンプル）が存在する場合は、初回起動時に単語近似を生成してローカル保存します
- より高度な学習帳/統計を行う場合は、今後Core Data/SQLiteへの移行を検討してください
