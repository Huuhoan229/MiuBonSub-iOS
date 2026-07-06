# Rules - MiuBonSub-iOS

## Source Boundaries

- Do not edit `node_modules/`, `.git/`, `logs_extracted/`, `logs.zip`, or
  `backup_sync_*` content.
- Treat `old_app.swift` as reference unless the task specifically asks to
  resurrect or migrate old native code.
- If changing UI/API behavior in `www/static/js/app.js`, check the matching
  backend route in `MBVietSub/app.py`.
- If changing native iOS files, keep `Info.plist` capabilities and app id
  aligned with `capacitor.config.json`.

## Backend Contract

- Keep backend URL storage key `MIUBON_API_BASE` compatible unless migrating all
  clients.
- Preserve support for LAN backend and public tunnel modes.
- Do not move heavy media processing into the app. The iOS client should remain
  a controller/monitor.
- Keep upload queue API calls aligned with `MBVietSub`: queue status is
  platform-specific, while enable/disable and pause/resume go through
  `/api/upload-queues/control`.
- Do not implement queue pause by killing backend uploader processes from iOS.
- When adding series queue actions, preserve saved URL/context registry support
  through `/api/series/save-urls` so resume-series stays compatible.
- For webview video, thumbnail, and download URLs, use
  `apiAssetUrl(projectApiPath(...))` instead of relative `/api/project/...`
  paths. In native Swift, keep frontend domains such as `tool.miubon.xyz`
  normalized to the backend API domain before opening media.
- Keep the viewer on the 720p preview stream (`/stream/preview` /
  `final_video_preview.mp4`). Do not use the full `final_video.mp4` as the
  player source unless the user explicitly asks for full-resolution playback.

## Verification

- For JS changes, check syntax and relevant UI behavior.
- For Capacitor changes, run `npx cap sync ios`.
- For native changes, build in Xcode/macOS when available.
