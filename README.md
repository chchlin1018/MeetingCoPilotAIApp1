# MeetingCopilot v4.0 — Dual-Engine Real-time Audio Pipeline

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                    MeetingAICoordinator (Orchestrator)               │
│                   @Observable · @MainActor                          │
│                                                                     │
│  ┌──────────────┐   transcript   ┌─────────────────┐               │
│  │ Audio Engine  │──── stream ──→│  Dual-Path       │               │
│  │ (Protocol)    │               │  Router           │               │
│  └──────┬───────┘               │  ┌──────────────┐ │               │
│         │                        │  │Path 1: Local  │ │  🔵 < 200ms │
│  ┌──────┴──────────┐            │  │KeywordMatcher│─┼──→ Blue Card  │
│  │ System (Primary) │            │  └──────────────┘ │               │
│  │ ScreenCaptureKit│            │         │ No match │               │
│  └─────────────────┘            │         ▼          │               │
│  ┌──────────────────┐           │  ┌──────────────┐ │  🟣 1.5-3s   │
│  │ Mic (Fallback)    │           │  │Path 2: Claude│─┼──→ Purple Card│
│  │ AVAudioEngine    │           │  │  Streaming   │ │               │
│  └──────────────────┘           │  └──────────────┘ │               │
│                                  └─────────────────┘               │
│  ┌──────────────────────┐                            🟠 Every 3min │
│  │ Background Strategy   │───────────────────────────→ Orange Card  │
│  └──────────────────────┘                                          │
└─────────────────────────────────────────────────────────────────────┘
```

## File Structure

```
Sources/
├── AudioCaptureEngine.swift         Protocol + shared types
├── SystemAudioCaptureEngine.swift   Primary: ScreenCaptureKit system audio
├── MicrophoneCaptureEngine.swift    Fallback: Microphone capture
├── KeywordMatcherAndClaude.swift    Local Q&A matching + Claude API streaming
├── MeetingAICoordinator.swift       Central orchestrator (dual-path routing)
└── UsageExample.swift               SwiftUI demo (UMC Digital Twin scenario)
```

## Latency Budget

| Step | Latency | Engine |
|------|---------|--------|
| Audio capture | Realtime | ScreenCaptureKit |
| Speech-to-text | 300-500ms | Apple Speech (partial) |
| Question detection | ~100ms | QuestionDetector |
| Q&A match (hit) | < 50ms | KeywordMatcher |
| Claude (miss) | 1.5-3s | Claude Sonnet Streaming |
| **End-to-end (matched)** | **< 1s** ✅ | |
| **End-to-end (unmatched)** | **< 5s** ⚠️ | |

## Token Economics

- Per Claude query: ~5,200 input + ~500 output tokens ≈ $0.022
- 60-min meeting: ~20-40 queries + ~20 background analyses ≈ **$1.00-1.50**
- Professional $49/mo plan (20 meetings): AI variable cost ≈ $30, margin 38%

## Requirements

- macOS 14.0+ (Sonoma)
- Screen Recording permission (System Settings → Privacy → Screen Recording)
- Speech recognition permission
- Network (Apple Speech server-side + Claude API)

## Quick Start

```swift
// 1. Create Coordinator
let coordinator = MeetingAICoordinator(
    claudeAPIKey: "sk-ant-...",
    meetingContext: yourMeetingContext
)

// 2. Load Q&A knowledge base
await coordinator.loadKnowledgeBase(yourQAItems)

// 3. Start meeting (auto-selects best engine)
await coordinator.startMeeting()

// 4. SwiftUI binding
ForEach(coordinator.cards) { card in
    AICardView(card: card)
}

// 5. End meeting
await coordinator.stopMeeting()
print(coordinator.stats.summary)
```

## Dual-Engine Architecture

**NotebookLM = Pre-meeting Brain, Claude = Live-meeting Brain**

- **NotebookLM** (slow but deep): Pre-meeting document parsing, RAG indexing, cross-meeting search, post-meeting Audio Overview (Meeting Podcast)
- **Claude** (fast and precise): Live question detection, 2-second strategy suggestions, intent analysis, negotiation tactics
- **Local App**: Audio capture, speech-to-text, Q&A matching, UI rendering

## Next Steps (V1.5 — NotebookLM Integration)

- [ ] Meeting Bridge Layer: Auto-create Notebook per meeting
- [ ] Pre-analysis results auto-fill MeetingContext.preAnalysisCache
- [ ] Post-meeting transcript auto-save to NotebookLM
- [ ] Audio Overview (Meeting Podcast) one-click generation
