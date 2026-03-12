# MeetingPrep-SKILL.md

> Version: 2026-03-12 | v4.3.1 | 19 Swift files | Zoom ✅ Verified

## ❗ Required: Screen Recording Permission (TCC)

System Settings > Privacy & Security > Screen & System Audio Recording > Enable MeetingCopilot

Without this: `DualStream: SystemAudio failed — 使用者拒絕應用程式、視窗、顯示器擷取的TCC`

Reset if needed: `tccutil reset ScreenCapture com.RealityMatrix.MeetingCopilot`

## Pre-Meeting Checklist

1. System Settings > Screen & System Audio Recording > MeetingCopilot ✅
2. System Settings > Sound > Input > MacBook built-in mic (auto-handled)
3. Sources/APIKeys.swift has valid Claude API Key
4. Run System Check (🩺) > all items pass
5. Open Zoom/Teams/Meet and join meeting
6. Click "開始會議" > select app > start
7. Meeting ends > Log auto-saved to MeetingTEXT/

## ★ Post-Meeting Diagnostic Logger

PostMeetingLogger.swift (19th Swift file) auto-saves diagnostic log on meeting end.

File: `MeetingTEXT/YYYY-MM-DD_HHMM_title_LOG.txt`

Integration:
- UsageExample.swift: `coordinator.setMeetingInfo(title:language:)` in loadPrepAndStart()
- MeetingAICoordinator.stopMeeting(): collects diagnostics before stopping engines
- PostMeetingLogger.saveLog(): writes TXT to MeetingTEXT folder

### Log Sections

| Section | Content |
|---------|----------|
| [STATUS] | ✅ ALL OK / ⚠️ WARNINGS / ❌ ISSUES |
| [MEETING] | title, duration, language, audio_source_app, dual_stream |
| [SYSTEM] | screen_recording TCC, mic_device, bluetooth_detected |
| [CONNECTIONS] | Claude API, Notion API, NotebookLM (connected/failed/not configured) |
| [REMOTE_ENGINE] | segments, buffers, restarts, errors, detected app |
| [LOCAL_ENGINE] | segments, buffers, restarts, RMS, silent%, on-device mode |
| [SPEAKING_TIME] | remote/local minutes, speaking ratio %, silence minutes |
| [AI_USAGE] | api calls, cards, latency, tokens, cost USD |
| [TALKING_POINTS] | total/completed, must completion rate |
| [ERROR_LOG] | collected errors |
| [SUMMARY] | human-readable one-liner |

### Bug Fixes (2026-03-12)

**start_time=N/A fix:**
- Root cause: `stats = await orchestrator.stats` overwrites sessionStartTime
- Fix: Save to `_sessionStartTime` private var, restore after orchestrator.stats assignment
- Log now uses `_sessionStartTime` directly

**speaking_time all zeros fix:**
- Root cause: computeSpeakingTime only counts isFinal entries; partial-only = 0
- Fix: Fallback to engine diagnosticInfo.segmentCount when no isFinal entries
- Estimate: each segment ≈ 20 chars (zh) or 30 chars (en)
- Now: remote 33 segments → ~3.7 min estimated speaking

### Overall Status Logic
- ✅ ALL OK: no issues
- ⚠️ WARNINGS: bluetooth detected, high restart count
- ❌ ISSUES: TCC denied, no speech received, Claude API failed

### Speaking Time Estimation
- zh: ~3 chars/sec → chars / 3 / 60 = minutes
- en: ~2.5 chars/sec → chars / 2.5 / 60 = minutes
- Fallback: segments × avgCharsPerSegment (20 zh / 30 en)

## Microphone Compatibility

AirPods Pro bluetooth mic NOT compatible with ScreenCaptureKit.
Program auto-detects bluetooth and switches to built-in mic.

| Device | Voice Capture | Compatible |
|--------|:---:|:---:|
| MacBook Built-in Mic | ✅ | ✅ Recommended |
| AirPods Pro | ❌ | Auto-switched to built-in |
| External USB Mic | ✅ | ✅ Should work |

## Verified Apps

| App | Remote | Local | Status |
|-----|:---:|:---:|--------|
| Zoom | ✅ | ✅ | Verified (English) |
| YouTube (Chrome) | ✅ | ✅ | Verified |
| Google Meet (Chrome) | ✅ | ✅ | Verified |
| Teams | 🔲 | 🔲 | Pending |
| LINE Desktop | ❌ | ❌ | HAL limitation |

## Dual-Pipeline Recognition

Remote: ScreenCaptureKit > Apple Speech [SERVER]
Local: AVAudioEngine > Apple Speech [ON-DEVICE]

On-Device languages: zh-TW, en-US, en-GB, zh-CN, ja-JP

## App Selection (v4.3.1)

MeetingPrepView: scanAndStart() > AppScanner.scanActiveApps()
- 0 apps: auto-detect
- 1 app: auto-start
- 2+ apps: App Picker Sheet

## Speech Error Handling

| Error | Wait | Rationale |
|-------|------|-----------|
| No speech detected | 5s | Normal silence |
| 60s timeout (216) | 0.3s | Apple limit |
| Canceled (301) | 1s | Other task conflict |

## Mic Debug Logging

Filter Xcode Console: MIC-DEBUG
- Start: permission, format, on-device, bluetooth detection
- RMS: first 10 buffers with dB + silent/quiet/audio
- Bluetooth auto-switch log

## Established Meetings

| Meeting | Notion Page ID | NotebookLM ID |
|---------|---------------|---------------|
| BiWeekly-Stanley-11Mar26 | 320f154a-6472-815c-8ad0-c214783dfe22 | ccaeee5e-8971-49e1-801d-2989ded2c61b |
| BiWeekly-Mark-JJ-12Mar26 | 320f154a-6472-813f-bc2c-d98e570ab696 | 51364658-5c30-4b55-8118-5103095ae8d0 |

Updated: 2026-03-12
