# MeetingCopilot v4.3.1 — 雙串流即時 AI 會議助手

> 會前準備 × 會中即時 × 會後回看 — 專為高壓商務場景設計的 AI 提詞板

## 產品定位

MeetingCopilot 是一款 macOS 原生 AI 會議助手，透過即時擷取線上會議音訊，自動偵測**對方提問**，並在秒級延遲內提供 AI 建議回答。

### 支援的應用程式（11 個）

| 類型 | App | Bundle ID |
|------|-----|----------|
| 會議 | Microsoft Teams | `com.microsoft.teams2` |
| 會議 | Zoom | `us.zoom.xos` |
| 會議 | Google Meet (Chrome) | `com.google.Chrome` |
| 會議 | Webex | `com.cisco.webexmeetingsapp` |
| 會議 | Slack | `com.tinyspeck.slackmacgap` |
| 通訊 | **LINE** | `jp.naver.line.mac` |
| 通訊 | **WhatsApp** | `net.whatsapp.WhatsApp` |
| 通訊 | **WhatsApp (Native)** | `WhatsApp` |
| 通訊 | **Telegram** | `ru.keepcoder.Telegram` |
| 通訊 | **Discord** | `com.hnc.Discord` |
| 通訊 | **FaceTime** | `com.apple.FaceTime` |

### 三大使用場景

| 場景 | AI 角色 | 即時性 |
|------|---------|--------|
| **多人線上會議** | 秘書 — TP 追蹤 + 偏離提醒 | 中等 |
| **高壓會議**（Board / 提案） | 隱形顧問 — 2 秒給數字和反駁論點 | 最高 |
| **面試 / Review** | 提詞板 + 教練 — 預載答案 + AI 即時補位 | 高 |

## 分支策略

| 分支 | 用途 | Xcode 專案 | 狀態 |
|------|------|-----------|------|
| `main` | 完整版（18 Swift + AI 全管線） | `MeetingCopilot.xcodeproj` | ✅ 穩定 |
| `feature/transcript-only` | 精簡版（6 Swift，純語音辨識測試） | `TranscriptOnly.xcodeproj` | ✅ 測試中 |

### TranscriptOnly 分支

專門測試 Zoom/Teams/LINE/WhatsApp/FaceTime 等會議通話的雙串流即時語音辨識，不含任何 AI 層：

```bash
git checkout feature/transcript-only
open TranscriptOnly.xcodeproj
# ⌘R → 開任何支援的 App 通話 → 按「開始會議」
```

只編譯 6 個 Swift 檔案（vs main 的 18 個），無需 API Key。詳見 [TranscriptOnly-README.md](TranscriptOnly-README.md)。

## 會前準備工作流（MeetingPrep Skill）

核心原則：**Notion 是唯一的資料來源（Single Source of Truth）**。TXT 只是 App 的載入格式，由 Claude 從 Notion 自動擷取產生。

```
會前 1-2 天：NotebookLM（文件萃取）
│  上傳 PDF / PPTX / XLSX / 影片 / URL
│  Google 語意搜尋 + 向量索引 → 精確數據
│
會前半天：Claude + Notion（策略規劃）
│  Goals、Talking Points、Q&A 建議、談判策略
│  搜尋 Gmail、Google Doc → 整合到 Notion
│
會前 5 分鐘：MeetingCopilot App
│  Claude 讀 Notion → 產生 TXT → push GitHub
│  git pull → System Check → 載入 TXT → 選語言 → 開始會議
│
會中即時：雙串流 + 雙來源並行 RAG
│  對方問「ROI 怎麼算？」
│  ├─ NotebookLM → 「財報 p.17: OEE +2.1%, $450K」
│  └─ Notion     → 「策略：強調 3.2 月回收期」
│  → Claude 合併 → 同時有數據佐證 + 策略建議
│
會後：AI 摘要 + Action Items → Notion / Markdown / TXT
```

完整 Skill 文件：[skills/MeetingPrep-SKILL.md](skills/MeetingPrep-SKILL.md)

## 軟體架構（v4.3.1）

```
┌─────────────────────────────────────────────────────────┐
│  MeetingAICoordinator + SwiftData Persistence           │
│  @Observable @MainActor                                 │
│                                                          │
│  ┌─────────────────────┐  ┌───────────────────────────┐ │
│  │ TranscriptPipeline  │  │ ResponseOrchestrator       │ │
│  │ ★ 雙串流 + 分色    │  │ ★ 雙來源並行 RAG          │ │
│  │ SystemAudio→remote│→→│ NotebookLM(文件數據)      │ │
│  │ Microphone →local │  │ Notion(個人策略)          │ │
│  │ ★ Live Partial    │  │ → 並行查詢 → 合併 → Claude │ │
│  └─────────────────────┘  └───────────────────────────┘ │
│                                                          │
│  ┌─────────────────────┐  ┌───────────────────────────┐ │
│  │ TalkingPointsTracker│  │ MeetingPrepView            │ │
│  │ • MUST/SHOULD/NICE  │  │ • 會前資料輸入 UI          │ │
│  │ • detectedSpeech   │  │ • TXT 儲存/讀取           │ │
│  └─────────────────────┘  └───────────────────────────┘ │
└─────────────────────────────────────────────────────────┘
```

### 雙串流說話者分離

```
SystemAudioEngine (ScreenCaptureKit) → 「對方的聲音」 → .remote
  → 支援 11 個 App（Teams/Zoom/Meet/LINE/WhatsApp/Telegram/Discord/FaceTime...）
  → 觸發問題偵測 → 進入三層 AI 管線

MicrophoneEngine (AVAudioEngine) → 「我的聲音」 → .local
  → TP 追蹤 + 偵測到我方已講標示
```

硬體層級天然分離，零延遲、零成本，遠端會議場景準確率 ~95%+。

## 檔案結構

```
MeetingCoPilotAIApp1/
│
├── MeetingCopilot.xcodeproj/           # v4.3.1 build 8（完整版）
├── TranscriptOnly.xcodeproj/           # ★ v1.0 精簡版（feature/transcript-only）
│
├── MeetingCopilot/                     # 完整版 App 入口
├── TranscriptOnly/                     # 精簡版 App 入口
│
├── Sources/ (18 個 Swift)
│   ├── AudioCaptureEngine.swift         # Protocol + MeetingApp (11 個 App)
│   ├── SystemAudioCaptureEngine.swift   # ScreenCaptureKit → remote
│   ├── MicrophoneCaptureEngine.swift    # AVAudioEngine → local
│   ├── TranscriptPipeline.swift         # 雙串流 + Live Partial + Audio Health
│   ├── KeywordMatcherAndClaude.swift    # Layer 1: Q&A + Claude API
│   ├── NotebookLMService.swift          # Layer 2: NotebookLM RAG
│   ├── NotionRetrievalService.swift     # Layer 2: Notion RAG
│   ├── ResponseOrchestrator.swift       # 雙來源並行 RAG + Claude
│   └── ... (其他 10 個)
│
├── Tests/ (4 個測試)
├── bridge/                             # NotebookLM Bridge (Node.js)
├── skills/MeetingPrep-SKILL.md
├── scripts/ | templates/ | MeetingTEXT/
├── TODO.md | TranscriptOnly-README.md
└── README.md
```

## Quick Start

### 完整版（main）

```bash
git clone https://github.com/chchlin1018/MeetingCoPilotAIApp1.git
open MeetingCopilot.xcodeproj
# Signing → Development Team → ⌘R
# 設定 Claude + Notion API Key → 系統檢查 → 開始會議
```

### 精簡版（transcript-only）

```bash
git clone https://github.com/chchlin1018/MeetingCoPilotAIApp1.git
cd MeetingCoPilotAIApp1
git checkout feature/transcript-only
open TranscriptOnly.xcodeproj
# Signing → Development Team → ⌘R
# 開任何支援的 App 通話 → 按「開始會議」（不需 API Key）
```

### 權限

- **螢幕與系統錄音**：System Settings → Privacy & Security → Screen & System Audio Recording → 開啟
- 每次 Xcode rebuild 後可能需重新授權：`tccutil reset ScreenCapture com.RealityMatrix.MeetingCopilot`

## 版本演進

| 版本 | 主題 | 狀態 |
|------|------|:----:|
| v4.0 | 雙引擎即時管線 | ✅ |
| v4.1 | 三層管線 + TP 追蹤 + NotebookLM Bridge | ✅ |
| v4.2 | 工程化重構（Coordinator -57%） | ✅ |
| v4.3 | 雙串流 + 雙來源並行 RAG + 分色 UI | ✅ |
| v4.3.1 | SystemCheck + Live Partial + 11 App 支援 | ✅ |
| **TranscriptOnly** | **精簡分支 — 純語音辨識測試** | **✅ 測試中** |
| v4.4 | Evidence-based Card + Claude 動態關鍵字 | 🔜 |
| v5.0 | Speaker Diarization + WhisperKit | 🔮 |

## 技術規格

| 項目 | 值 |
|------|-----|
| 平台 | macOS 14.0+ (Sonoma) |
| 語言 | Swift 5.0, Strict Concurrency |
| UI | SwiftUI + @Observable |
| 支援 App | 11 個（Teams/Zoom/Meet/LINE/WhatsApp/Telegram/Discord/FaceTime...） |
| RAG | NotebookLM(文件) + Notion(策略) 並行 |
| 語音辨識 | Apple Speech（zh-TW / en-US / en-GB / zh-CN / ja-JP）|
| 主 Bundle ID | com.RealityMatrix.MeetingCopilot |
| 測試 Bundle ID | com.RealityMatrix.TranscriptOnly |
| 版本 | 4.3.1 (build 8) |
| Swift 檔案 | 18 + 2 (TranscriptOnly) + 4 測試 |

## 授權

Reality Matrix Inc. — com.RealityMatrix.MeetingCopilot
