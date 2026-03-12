# MeetingPrep-SKILL.md
# MeetingCopilot — Meeting Preparation Skill

> Version: 2026-03-12 | MeetingCopilot v4.3.1 + TranscriptOnly v1.0

---

## Overview

This skill covers the full meeting lifecycle for MeetingCopilot:
1. **Pre-Meeting Prep** — Notion → TXT → GitHub → NotebookLM
2. **Live Transcription** — TranscriptOnly branch (dual-stream STT)
3. **Post-Meeting** — AI Summary → Action Items → Notion Export

---

## ★ Dual-Pipeline Recognition (On-Device + Server)

### The Problem
macOS Apple Speech allows only ONE active server-based SFSpeechRecognitionTask.
When both engines used server mode, they canceled each other:
- Error [301]: Recognition request was canceled
- User speaks into mic → mic's task kills remote's task
- User stops → remote restarts but mic stays silent

### The Solution
| Engine | Recognition Mode | Purpose |
|--------|-----------------|----------|
| Remote (SystemAudioCaptureEngine) | **Server** (online) | Best quality for meeting audio |
| Local (MicrophoneCaptureEngine) | **On-Device** (offline) | No conflict with server task |

### On-Device Language Support
| Language | On-Device | Code |
|----------|:---------:|------|
| 繁體中文 (台灣) | ✅ | zh-TW |
| English (US) | ✅ | en-US |
| English (UK) | ✅ | en-GB |
| 简体中文 | ✅ | zh-CN |
| 日本語 | ✅ | ja-JP |

### Key Code
```swift
// MicrophoneCaptureEngine.swift
if recognizer.supportsOnDeviceRecognition {
    request.requiresOnDeviceRecognition = true  // ★ On-Device
}

// SystemAudioCaptureEngine.swift
// Uses default server-based recognition (no requiresOnDeviceRecognition)
```

---

## Audio Architecture

### Dual-Stream Pipeline
```
Remote (對方): ScreenCaptureKit → SCStream → Direct Append → Apple Speech [SERVER]
Local (我方):  AVAudioEngine → installTap → Apple Speech [ON-DEVICE]
                                    ↓
                         TranscriptPipeline (merge)
                                    ↓
              UI (cyan=remote, yellow=local, purple=partial)
```

### Audio Format Strategy (Three-Layer Fallback)
1. **Direct Append** — Feed 48kHz PCM to Apple Speech directly
2. **Dynamic Converter** — Lazy-create AVAudioConverter from actual buffer format
3. **Raw Append** — On converter error, reset and send raw buffer

### Speech Error Handling
| Error | Wait | Rationale |
|-------|------|-----------|
| "No speech detected" | **5 seconds** | Normal silence — old 0.3s caused restart loop |
| 60s timeout (code 216) | 0.3 seconds | Apple Speech normal limit |
| Canceled (code 301) | 1 second | Canceled by other recognition task |
| Other errors | 1 second | Log error code, then restart |

### MicrophoneCaptureEngine Bug Fixes
1. **Restart death bug**: `restartRecognition()` called `start()` → `guard !isActive` → return → dead
   - Fix: `restartSpeechOnly()` — only restart Speech, keep AVAudioEngine running
2. **Rapid restart loop**: 0.3s delay caused infinite "No speech detected" cycle
   - Fix: 5-second delay for normal silence
3. **Mutual cancellation**: Both engines used server mode → error [301]
   - Fix: Mic uses On-Device, Remote uses Server

---

## Smart App Detection

### Priority Tiers
When user clicks "開始會議":
1. Scan all 11 apps for active windows (>200x200, on screen)
2. 0 apps → Error / 1 app → Auto-start / 2+ apps → App Picker

| Tier | Apps | Priority |
|------|------|----------|
| 0 (Highest) | Zoom, Teams, Webex | Professional meetings |
| 1 | Google Meet (Chrome) | Browser meetings |
| 2 | Slack, Discord | Team collaboration |
| 3 (Lowest) | LINE, WhatsApp, Telegram, FaceTime | Messaging |

### Compatibility Status
| App | ScreenCaptureKit | Mic (On-Device) | Note |
|-----|:---:|:---:|------|
| YouTube (Chrome) | ✅ | ✅ | Dual-stream verified |
| Google Meet (Chrome) | ✅ | ✅ | Smart Detection OK |
| Zoom | 🔲 | 🔲 | Primary test target |
| Teams | 🔲 | 🔲 | Primary test target |
| FaceTime | ✅ detect | 🔲 | Audio TBD |
| LINE Desktop | ❌ | ❌ | HAL virtual device |

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

---

## System Check (7 Items)

| # | Check | Method |
|---|-------|--------|
| 1 | Mic Permission | AVCaptureDevice.authorizationStatus |
| 2 | Speech Permission | SFSpeechRecognizer.requestAuthorization |
| 3 | Screen Recording | SCShareableContent access test |
| 4 | Mic Audio Capture | AVAudioEngine format check |
| 5 | Speech Recognizer | Language + on-device support |
| 6 | App Detection | Scan all 11 supported apps |
| 7 | ScreenCaptureKit | SCStream creation test |

---

## File Structure (feature/transcript-only)

```
├── TranscriptOnly/
│   ├── TranscriptOnlyApp.swift
│   ├── TranscriptOnlyView.swift     # UI + App Picker
│   ├── SystemCheckSheet.swift       # 7-item diagnostic
│   ├── Info.plist / Entitlements / Assets
├── Sources/
│   ├── AudioCaptureEngine.swift     # Protocol + AppScanner + DetectedAppInfo
│   ├── SystemAudioCaptureEngine.swift  # ScreenCaptureKit [SERVER]
│   ├── MicrophoneCaptureEngine.swift   # AVAudioEngine [ON-DEVICE]
│   └── TranscriptPipeline.swift     # Dual-stream + AudioHealthStatus
```

---

## Known Issues

### LINE Desktop (HAL Virtual Device)
```
HALC_ShellPlugIn.cpp:915 — no object
throwing -10877
```
Solution: v4.5 BlackHole loopback integration (planned)

### TCC Permissions Reset
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
