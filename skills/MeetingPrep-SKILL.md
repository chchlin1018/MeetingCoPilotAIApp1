# MeetingPrep-SKILL.md
# MeetingCopilot — Meeting Preparation Skill

> Version: 2026-03-12 | MeetingCopilot v4.3.1 + TranscriptOnly v1.0

---

## Overview

This skill covers the full meeting preparation and transcription workflow for MeetingCopilot, including:

1. **Pre-Meeting Prep** — Notion → TXT → GitHub → NotebookLM
2. **Live Transcription** — TranscriptOnly branch for pure STT testing
3. **Post-Meeting** — AI Summary → Action Items → Notion Export

---

## Branch Strategy

| Branch | Purpose | Files | Status |
|--------|---------|-------|--------|
| `main` | Full AI pipeline (18 Swift) | MeetingCopilot.xcodeproj | Stable |
| `feature/transcript-only` | Pure STT testing (7 Swift) | TranscriptOnly.xcodeproj | Testing |

---

## Supported Apps (11)

### Detection Priority (Smart Detection)

When user clicks "開始會議":
1. **Scan** all 11 apps for active windows (>200x200, on screen)
2. **0 apps** → Error message
3. **1 app** → Auto-start
4. **2+ apps** → Show App Picker for manual selection

| Tier | Apps | Priority |
|------|------|----------|
| 0 (Highest) | Zoom, Teams, Webex | Professional meetings |
| 1 | Google Meet (Chrome) | Browser meetings |
| 2 | Slack, Discord | Team collaboration |
| 3 (Lowest) | LINE, WhatsApp, Telegram, FaceTime | Messaging |

### Compatibility Status

| App | ScreenCaptureKit | Note |
|-----|:---:|------|
| YouTube (Chrome) | ✅ | Verified: Chinese content recognition |
| Google Meet (Chrome) | ✅ | Verified: Detection + capture |
| Zoom | 🔲 | To be tested (primary scenario) |
| Teams | 🔲 | To be tested (primary scenario) |
| FaceTime | ✅ | Detection OK, audio TBD |
| LINE Desktop | ❌ | HAL virtual device — use Chrome version |
| WhatsApp Desktop | 🔲 | May have same LINE limitation |

---

## Audio Architecture

### Dual-Stream Pipeline

```
Remote (對方):
  ScreenCaptureKit → SCStream → CMSampleBuffer → Direct Append → Apple Speech
  → TranscriptSegment (source: .systemAudio) → TranscriptPipeline

Local (我方):
  AVAudioEngine → installTap → AVAudioPCMBuffer → Apple Speech
  → TranscriptSegment (source: .microphone) → TranscriptPipeline

TranscriptPipeline → TranscriptUpdate → UI (cyan=remote, yellow=local, purple=partial)
```

### Audio Format Strategy (Three-Layer Fallback)

1. **Direct Append** — Feed 48kHz PCM to Apple Speech directly (Apple handles resampling)
2. **Dynamic Converter** — Lazy-create AVAudioConverter from actual buffer format
3. **Raw Append** — On converter error, reset and send raw buffer

### Speech Error Handling

| Error | Wait Time | Rationale |
|-------|-----------|----------|
| "No speech detected" | **5 seconds** | Normal silence — not an error. Old 0.3s caused restart loop |
| 60s timeout (code 216) | 0.3 seconds | Apple Speech normal limit |
| Other errors | 1 second | Log error code, then restart |

### MicrophoneCaptureEngine Bug Fix

**Old bug:** `restartRecognition()` called `start()`, but `start()` had `guard !_state.isActive` → state was `.capturing` → `return` → speech recognition died permanently.

**Fix:** `restartSpeechOnly()` — only restart Speech Recognition, keep AVAudioEngine running. Reinstall tap pointing to new request.

---

## Meeting Prep Workflow

### Notion → TXT → GitHub → NotebookLM

```
Step 1: Create Notion page (parent: 320f154a-6472-804f-a226-c3694c1bb319)
Step 2: Claude reads Notion API → generates TXT file
Step 3: Push TXT to GitHub repo (meetings/ folder)
Step 4: Upload to NotebookLM as source
Step 5: Meeting starts → TranscriptOnly captures live transcript
```

### TXT Format Template

```
# Meeting: [Meeting Name]
# Date: YYYY-MM-DD
# Participants: [names]
# Language: zh-TW / en-US

## Agenda
1. ...
2. ...

## Key Topics
- ...

## MUST Talking Points
1. ...

## Background Context
- ...
```

---

## System Check (7 Items)

TranscriptOnly includes a pre-meeting diagnostic tool (🩺 button):

| # | Check | Method |
|---|-------|--------|
| 1 | Mic Permission | AVCaptureDevice.authorizationStatus |
| 2 | Speech Permission | SFSpeechRecognizer.requestAuthorization |
| 3 | Screen Recording | SCShareableContent access test |
| 4 | Mic Audio Capture | AVAudioEngine format check |
| 5 | Speech Recognizer | Language availability + on-device support |
| 6 | App Detection | Scan all 11 supported apps |
| 7 | ScreenCaptureKit | SCStream creation test |

Results: ✅ Passed / ❌ Failed / ⚠️ Warning + latency (ms)

---

## TranscriptOnly File Structure

```
feature/transcript-only branch:
├── TranscriptOnly.xcodeproj/
│   └── project.pbxproj
├── TranscriptOnly/
│   ├── TranscriptOnlyApp.swift      # @main (no API keys)
│   ├── TranscriptOnlyView.swift     # Full UI + ViewModel + App Picker
│   ├── SystemCheckSheet.swift       # 7-item diagnostic
│   ├── Info.plist
│   ├── TranscriptOnly.entitlements
│   └── Assets.xcassets/
├── Sources/
│   ├── AudioCaptureEngine.swift     # Protocol + MeetingApp + AppScanner + DetectedAppInfo
│   ├── SystemAudioCaptureEngine.swift  # ScreenCaptureKit (remote)
│   ├── MicrophoneCaptureEngine.swift   # AVAudioEngine (local)
│   └── TranscriptPipeline.swift     # Dual-stream merge + AudioHealthStatus
└── TranscriptOnly-README.md
```

---

## Known Issues

### LINE Desktop (HAL Virtual Device)
```
HALC_ShellPlugIn.cpp:915 — no object
HALPlugIn.cpp:458 — Error 560947818 (!obj)
throwing -10877
```
**Root cause:** LINE audio uses macOS HAL plug-in, not standard window audio.
**Solution:** v4.5 BlackHole loopback integration (planned)

### TCC Permissions Reset
After Xcode rebuild, Screen Recording permission may need re-authorization:
```bash
tccutil reset ScreenCapture com.RealityMatrix.TranscriptOnly
tccutil reset ScreenCapture com.RealityMatrix.MeetingCopilot
```

---

## Established Meetings

| Meeting | Notion Page ID | NotebookLM ID | TXT |
|---------|---------------|---------------|-----|
| BiWeekly-Stanley-11Mar26 | 320f154a-6472-815c-8ad0-c214783dfe22 | ccaeee5e-8971-49e1-801d-2989ded2c61b | 2026-03-11_BiWeekly-Stanley.txt |
| BiWeekly-Mark-JJ-12Mar26 | 320f154a-6472-813f-bc2c-d98e570ab696 | 51364658-5c30-4b55-8118-5103095ae8d0 | 2026-03-12_BiWeekly-Mark-JJ.txt |

---

Updated: 2026-03-12 | Notion SSOT parent: 320f154a-6472-804f-a226-c3694c1bb319
