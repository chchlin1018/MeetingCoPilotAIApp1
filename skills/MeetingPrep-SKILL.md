# MeetingPrep-SKILL.md

> Version: 2026-03-13 | v4.3.1 | 19 Swift files | Zoom ✅ Verified

## Branch Strategy

| Branch | Purpose | Xcode Project | Swift Files |
|--------|---------|---------------|:-----------:|
| `main` | Full AI meeting assistant | MeetingCopilot.xcodeproj | 19 |
| `feature/transcript-only` | Pure STT testing | TranscriptOnly.xcodeproj | 7 |
| `feature/speaker-prompter` | Personal speech prompter | SpeakerPrompter.xcodeproj | 4 |

## ★ SpeakerPrompter Branch

Simplified personal speech/presentation prompter. No audio, no AI, no API, no network.

### Project Structure
```
SpeakerPrompter.xcodeproj
SpeakerPrompter/
  Info.plist
  SpeakerPrompter.entitlements
  Assets.xcassets/
  Sources/
    SpeakerPrompterApp.swift      ← App entry
    SpeechDataModel.swift         ← Models + TXT parser
    SpeechTimer.swift             ← Total + section timer
    SpeakerPrompterView.swift     ← Full UI + keyboard
  Speeches/
    demo-idtf-pitch.txt           ← IDTF investor pitch demo
    demo-jj-taiwan.txt            ← J&J Taiwan strategy demo
```

Bundle ID: `com.RealityMatrix.SpeakerPrompter`

### TXT Format
```
[SPEECH] title, type, total_minutes
[AGENDA] order|title|minutes
[TP] MUST|content
[NOTES] free text
```

### Keyboard Shortcuts
| Key | Action |
|:---:|--------|
| → | Next section |
| ← | Previous section |
| Space | Start/Pause |
| R | Reset |

### Features
- Agenda with active section highlight + completion tracking
- Per-section timer with overtime warning (red)
- Total timer with progress bar
- Talking Points checklist (MUST/SHOULD/NICE)
- Notes panel
- TXT file import
- Demo mode

---

## MeetingCopilot (main branch)

(... same as before ...)

### Required: Screen Recording Permission (TCC)
System Settings > Privacy & Security > Screen & System Audio Recording > Enable MeetingCopilot

### Browser Meeting Detection (New)
Supports Teams/Meet/Zoom/Webex on Chrome/Edge/Safari/Firefox via window title detection.

### Pre-Meeting Checklist
1. Screen Recording TCC ✅
2. MacBook built-in mic ✅
3. APIKeys.swift has valid Claude API Key
4. Run System Check
5. Open meeting app and join
6. Click "開始會議" > select app
7. Meeting ends > Log auto-saved

### Verified Apps
| App | Remote | Local | Status |
|-----|:---:|:---:|--------|
| Zoom | ✅ | ✅ | Verified (English) |
| Google Meet (any browser) | ✅ | ✅ | Verified |
| Teams Web (Edge/Chrome) | ✅ | ✅ | New — via BrowserMeetingDetector |
| Teams (native) | 🔲 | 🔲 | Pending |
| LINE Desktop | ❌ | ❌ | HAL limitation |

### Post-Meeting Logger
Auto-saves to MeetingTEXT/: STATUS, MEETING, SYSTEM, CONNECTIONS, ENGINES, SPEAKING_TIME, AI_USAGE, TP, ERRORS, SUMMARY

### Established Meetings
| Meeting | Notion Page ID | NotebookLM ID |
|---------|---------------|---------------|
| BiWeekly-Stanley-11Mar26 | 320f154a-6472-815c-8ad0-c214783dfe22 | ccaeee5e-8971-49e1-801d-2989ded2c61b |
| BiWeekly-Mark-JJ-12Mar26 | 320f154a-6472-813f-bc2c-d98e570ab696 | 51364658-5c30-4b55-8118-5103095ae8d0 |

Updated: 2026-03-13
