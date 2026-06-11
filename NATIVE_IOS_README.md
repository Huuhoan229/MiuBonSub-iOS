# MiuBon Vietsub Native iOS

This is the new SwiftUI iOS shell for the `E:\MiuBonVSub\MBVietSub` backend.

The iPhone app is a controller/monitor for the desktop backend. Heavy tasks still run on the backend machine:

- Douyin/TikTok scraping through Playwright
- ffmpeg render
- TTS/STT/translation
- YouTube, TikTok, Facebook and Google Drive uploads

## Build IPA for TrollStore

Run on macOS with Xcode installed:

```bash
cd /path/to/MiuBonSub-iOS
bash build_trollstore_ipa.sh
```

Output:

```text
dist/MiuBonVietsub-TrollStore.ipa
```

Install that IPA with TrollStore.

## Backend URL

On the first run, open `Settings` and set:

```text
http://YOUR_PC_IP:2209
```

The backend must be reachable from the iPhone on the same Wi-Fi or through your public tunnel.

## Native Features

- SwiftUI native layout, no WebView UI.
- iPhone-safe layout with scrollable log/status rows.
- Light, dark and auto theme.
- Local iOS notifications when pipeline, queue, upload or scrape jobs finish or fail.
- Bottom tab shell for Pipeline, Running, Scraper, Projects, Uploads and Settings.
