# MeetingCopilot v4.2 — 三層即時管線 AI 會議助手

> 會前準備 × 會中即時 × 會後整理 — 專為高壓商務場景設計的 AI 提詞板

## 產品定位

MeetingCopilot 是一款 macOS 原生 AI 會議助手，透過即時擷取線上會議音訊（Teams / Zoom / Meet），自動偵測對方提問，並在**秒級延遲內**提供 AI 建議回答。

### 三大使用場景

| 場景 | 痛點 | AI 角色 | 即時性要求 |
|------|------|---------|-----------|
| **多人線上會議** | 議題發散、忘記該講的重點 | 秘書 — TP 追蹤 + 偏離提醒 | 中等 |
| **高壓會議**（Board / 客戶提案） | 被問倒、數據記不住 | 隱形顧問 — 2 秒給數字和反駁論點 | 最高 |
| **面試 / Review Meeting** | 緊張遺漏準備內容 | 提詞板 + 教練 — 預載答案 + AI 即時補位 | 高 |

## 軟體架構（v4.2 — 工程化重構）

### 模組分層

```
┌─────────────────────────────────────────────────────┐
│  MeetingAICoordinator（瘦身版 — 只做 Orchestration）   │
│  @Observable @MainActor — UI 狀態代理                 │
│                                                      │
│  ┌──────────────────┐  ┌────────────────────────┐   │
│  │ TranscriptPipeline│  │ ResponseOrchestrator    │   │
│  │ (actor)           │  │ (actor)                 │   │
│  │                   │  │                         │   │
│  │ • 音訊引擎選擇    │  │ • 三層管線路由          │   │
│  │ • 轉錄消費        │→→│ • 背景策略分析          │   │
│  │ • 問題偵測        │  │ • 手動提問              │   │
│  │                   │  │ • 卡片生成              │   │
│  └──────────────────┘  └────────────────────────┘   │
│                                                      │
│  ┌──────────────────┐  ┌────────────────────────┐   │
│  │TalkingPointsTracker│ │ ProviderProtocols       │   │
│  │ (actor)           │  │ (抽象介面)               │   │
│  │ • MUST/SHOULD/NICE│  │ • KnowledgeRetrieval    │   │
│  │ • 時間壓力提醒    │  │ • GenerativeResponse    │   │
│  │ • 話題相關提示    │  │ • TranscriptProvider    │   │
│  └──────────────────┘  └────────────────────────┘   │
└─────────────────────────────────────────────────────┘
```

### v4.1 → v4.2 關鍵變更

| 變更 | 說明 |
|------|------|
| **God Object 拆分** | MeetingAICoordinator: 650 行 → 280 行（-57%） |
| **TranscriptPipeline** | 音訊引擎 + 轉錄 + 問題偵測獨立為 actor |
| **ResponseOrchestrator** | 三層管線 + 策略分析 + 卡片管理獨立為 actor |
| **ProviderProtocols** | 抽象介面，未來可替換 Claude/NotebookLM/Speech |
| **DemoDataProvider** | Demo 資料從 UsageExample 隔離 |
| **事件驅動** | Orchestrator 透過 AsyncStream<Event> 通知 UI |

### 三層即時管線

```
問題偵測 → ① 本地 Q&A (< 200ms) → 🔵 命中即返回
         → ② NotebookLM RAG (1-3s) → 找到相關段落
         → ③ Claude + context (2-4s) → 🟣 有文件佐證的 AI 回答
背景: 每 3 分鐘 → 🟠 策略分析（含 TP 狀態）
持續: TP 追蹤 → ⚠️ MUST 未講提醒
```

## 檔案結構

```
MeetingCoPilotAIApp1/
│
├── MeetingCopilot.xcodeproj/           # Xcode 專案（macOS 14.0+）
├── MeetingCopilot/                     # App 目錄
│   ├── MeetingCopilotApp.swift         # @main 入口
│   ├── Info.plist                      # 隱私權描述
│   ├── MeetingCopilot.entitlements     # 權限
│   └── Assets.xcassets/                # App Icon
│
├── Sources/                            # Swift 原始碼
│   ├── AudioCaptureEngine.swift        # Protocol + 共用型別
│   ├── SystemAudioCaptureEngine.swift  # 主引擎（ScreenCaptureKit）
│   ├── MicrophoneCaptureEngine.swift   # 降級引擎（Microphone）
│   ├── KeywordMatcherAndClaude.swift   # 第一層 Q&A + Claude API
│   ├── NotebookLMService.swift         # 第二層 NotebookLM 查詢
│   ├── TalkingPointsTracker.swift      # TP 即時追蹤
│   ├── ProviderProtocols.swift         # ★ v4.2 抽象 Provider 介面
│   ├── TranscriptPipeline.swift        # ★ v4.2 逐字稿管線
│   ├── ResponseOrchestrator.swift      # ★ v4.2 回應編排器
│   ├── DemoDataProvider.swift          # ★ v4.2 Demo 資料隔離
│   ├── MeetingAICoordinator.swift      # ★ v4.2 瘦身版 Coordinator
│   └── UsageExample.swift              # SwiftUI Demo
│
├── bridge/                             # NotebookLM Node.js Bridge
│   ├── bridge-server.js                # Mock + Puppeteer 雙模式
│   ├── test-bridge.js                  # 整合測試
│   └── README.md                       # API 文件
│
├── .gitignore
└── README.md
```

## Quick Start

```bash
# 1. Clone + 開啟 Xcode
git clone https://github.com/chchlin1018/MeetingCoPilotAIApp1.git
open MeetingCoPilotAIApp1/MeetingCopilot.xcodeproj

# 2. 啟動 NotebookLM Bridge（可選）
cd bridge && npm install && npm run dev

# 3. Xcode 中 ⌘+R 即可 build
```

## Provider 抽象（v4.2）

三個核心 Protocol 讓底層實作可替換：

```swift
protocol KnowledgeRetrievalProvider   // NotebookLM → Pinecone / Qdrant
protocol GenerativeResponseProvider    // Claude → OpenAI / Gemini / local
protocol TranscriptProviderProtocol    // Apple Speech → Whisper / Deepgram
```

## 延遲預算

| 端到端路徑 | 延遲 | 說明 |
|-----------|------|------|
| ① 本地匹配命中 | **< 1s** ✅ | 預載答案直接顯示 |
| ② + ③ NotebookLM + Claude | **3-7s** ⚠️ | Streaming 緩解等待感 |
| ③ Claude only（無 NLM） | **< 5s** | NotebookLM 不可用時 |

## 開發路線圖

### ✅ v4.0 — 雙引擎即時管線
- [x] ScreenCaptureKit 系統音訊 + Apple Speech 即時轉錄
- [x] 本地 Q&A 匹配 + Claude Streaming

### ✅ v4.1 — 三層管線 + TP 追蹤
- [x] NotebookLM 即時查詢（第二層）
- [x] Talking Points 追蹤（MUST/SHOULD/NICE）
- [x] NotebookLM Bridge（Mock + Puppeteer）
- [x] SwiftUI 完整 Demo + Xcode Project

### ✅ v4.2 — 工程化重構（目前版本）
- [x] God Object 拆分（Coordinator -57%）
- [x] TranscriptPipeline + ResponseOrchestrator 獨立 actor
- [x] Provider Protocol 抽象介面
- [x] Demo 資料隔離（DemoDataProvider）

### 🔜 v4.3 — 品質基礎設施
- [ ] XCTest 單元測試（KeywordMatcher / TP / QuestionDetector）
- [ ] SwiftData 最小 persistence（MeetingSession / Transcript）
- [ ] Bridge 安全加固（CORS + token + log redact）
- [ ] API key → macOS Keychain

### 🔮 v5.0 — 產品化
- [ ] Evidence-based card model（來源標註 + 事實/推測區分）
- [ ] 多人發言辨識（Speaker Diarization）
- [ ] 會後 session summary + replay
- [ ] WhisperKit 離線引擎
- [ ] Enterprise 安全治理

## 授權

MacroVision Systems — com.macrovision.MeetingCopilot
