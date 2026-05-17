# Birkin iPhone Mockup Prompts

Use these prompts with Midjourney v6, DALL-E 3, or Adobe Firefly to generate the iPhone mockup screenshots for the README and press kit.

---

## Mockup 1 — Open WebUI Chat Interface

**Midjourney v6:**
```
iPhone 15 Pro in natural titanium, held in one hand against a soft dark desk background, screen showing a clean mobile chat interface with dark theme, green accent color, message bubbles with "Run the daily brief" user message and a structured AI response showing bullet points about emails calendar and health status, Open WebUI logo in top left, microphone icon visible in input bar, ultra-realistic product photo, studio lighting, 4K, --ar 9:19 --style raw --v 6
```

**DALL-E 3:**
```
A photorealistic product photograph of an iPhone 15 Pro in natural titanium finish, slightly angled, held naturally against a dark linen background. The phone screen displays a dark-themed mobile chat interface with a conversation visible: a user message reading "Run the daily brief" followed by an AI assistant response in a structured format showing bullet points about emails, calendar events, and health status. The interface has a green accent color, a top navigation bar, and a voice input microphone button. Professional product photography lighting with subtle bokeh background.
```

---

## Mockup 2 — Health Endpoint JSON Response

**Midjourney v6:**
```
iPhone 15 Pro screen showing a mobile browser displaying a JSON health status response with monospace font, dark background, syntax highlighting in green and teal, showing keys like "status: healthy", "uptime_hours: 847", "audit_entries: 1247", "drift_status: PASS", "skills_loaded: 5", "last_action: daily-brief", elegant developer aesthetic, clean product shot, --ar 9:19 --style raw --v 6
```

**DALL-E 3:**
```
A clean product photograph of an iPhone screen showing a mobile web browser with a JSON response. The JSON is formatted with monospace font on a dark background with syntax highlighting. Visible keys include "status": "healthy", "uptime_hours": 847, "governance": "intact", "audit_entries": 1247, "drift_status": "PASS", "skills_loaded": 5. The design looks like a developer health dashboard. Professional lighting, slightly angled for depth.
```

---

## Mockup 3 — Governance Check Terminal Output

**Midjourney v6:**
```
iPhone 15 Pro screen showing a mobile SSH terminal app with dark theme and monospace green text, displaying the output of a governance check script with checkmarks and status lines reading "Hermes gateway active", "Audit log append-only intact", "Skills versioned in git", "Drift check passed", "Health endpoint responding", final line "AGENT GOVERNANCE INTACT" in bright green, authentic terminal look, --ar 9:19 --style raw --v 6
```

**DALL-E 3:**
```
A product photograph of an iPhone showing a mobile terminal app with dark background and green monospace text. The screen displays a governance check script output with green checkmark symbols next to lines like "Hermes gateway service active", "No tampered audit entries", "Skills directory is a git repo", "Drift check passed (similarity: 0.92)", "Health endpoint responds". The final line reads "AGENT GOVERNANCE INTACT" in brighter green. Authentic SSH terminal aesthetic.
```

---

## Mockup 4 — Add to Home Screen

**Midjourney v6:**
```
iPhone 15 Pro home screen with a custom PWA app icon called "Birkin" showing a small circuit-like geometric logo in dark green on black background, icon placed among other apps, iOS 18 home screen, natural titanium frame, shot from slightly above and to the side, soft background, realistic app icon grid visible, --ar 9:19 --style raw --v 6
```

**DALL-E 3:**
```
A product photograph of an iPhone home screen showing iOS app icons arranged in a grid. One app icon is labeled "Birkin" with a clean geometric logo in dark green on black background. The surrounding app icons are realistic iOS-style icons. The phone is in natural titanium iPhone 15 Pro finish. The shot is slightly angled, showing the home screen clearly. Soft, professional lighting.
```

---

## Mockup 5 — Telegram Alert (for push notification demo)

**Midjourney v6:**
```
iPhone 15 Pro lock screen showing an iOS notification banner from Telegram, notification preview reading "DIRECTORA HEALTH ALERT — Service degraded, p99 latency 2847ms, action required", dark lock screen wallpaper with subtle texture, notification bubble with Telegram logo, realistic iOS notification design, --ar 9:19 --style raw --v 6
```

**DALL-E 3:**
```
An iPhone 15 Pro lock screen photograph showing an iOS push notification banner at the top of the screen. The notification is from Telegram and reads "🔴 DIRECTORA HEALTH ALERT — 2026-05-17 09:32 — Service degraded. p99 latency 2,847ms. SSH and check database." The lock screen has a dark blurred wallpaper. The notification has the Telegram app icon in the corner. Realistic iOS design.
```

---

## Composite Banner Prompt (for README header)

**Midjourney v6:**
```
Three iPhones in natural titanium displayed side by side in a fan arrangement against a very dark almost-black background, center phone showing a dark mobile chat interface, left phone showing a terminal with green text and checkmarks, right phone showing a JSON health response, professional product photography, studio lighting with subtle rim light, 4K, --ar 16:9 --style raw --v 6
```

---

## Usage Notes

- For Midjourney: use `--quality 2` for highest quality renders
- For DALL-E 3: use "HD" quality setting
- For Adobe Firefly: enable "Photo" style and "Shot on iPhone" reference
- Scale all generated images to 390×844px (iPhone 15 Pro screen resolution) before adding to repo
- Save as `assets/mockup-{1-5}.png` in the repo

## Alternative: Use MockupPhotos or SmartMockups

If you don't want to use AI generation, take real screenshots of:
1. The Open WebUI running locally via `docker compose up -d`
2. `curl http://localhost:9999/health | jq .` in a browser
3. A mobile SSH client showing `governance-check.sh` output

Then drop the screenshots into [MockupPhotos](https://mockuphotos.co) or [SmartMockups](https://smartmockups.com) for realistic iPhone frames.
