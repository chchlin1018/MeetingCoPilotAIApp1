# MeetingCopilot v4.3 — 雙串流即時 AI 會議助手

> 會前準備 × 會中即時 × 會後回看 — 專為高壓商務場景設計的 AI 提詞板

## 產品定位

MeetingCopilot 是一款 macOS 原生 AI 會議助手，透過即時擷取線上會議音訊（Teams / Zoom / Meet），自動偵測**對方提問**，並在秒級延遲內提供 AI 建議回答。

### 三大使用場景

| 場景 | AI 角色 | 即時性 |
|------|---------|--------|
| **多人線上會議** | 秘書 — TP 追蹤 + 偏離提醒 | 中等 |
| **高壓會議**（Board / 提案） | 隱形顧問 — 2 秒給數字和反駁論點 | 最高 |
| **面試 / Review** | 提詞板 + 教練 — 預載答案 + AI 即時補位 | 高 |

## 軟體架構（v4.3）

```
┌─────────────────────────────────────────────────────────┐
│  MeetingAICoordinator + SwiftData Persistence        │
│  @Observable @MainActor — UI 狀態代理                │
│                                                         │
│  ┌─────────────────────┐  ┌───────────────────────┐  │
│  │ TranscriptPipeline  │  │ ResponseOrchestrator    │  │
│  │ ★ 雙串流 (v4.3)    │  │                         │  │
│  │                     │  │ • 三層管線路由          │  │
│  │ SystemAudio → remote│→→│ • 背景策略分析          │  │
│  │ Microphone  → local │  │ • 卡片生成              │  │
│  └─────────────────────┘  └───────────────────────┘  │
│                                                         │
│  ┌─────────────────────┐  ┌───────────────────────┐  │
│  │ TalkingPointsTracker│  │ MeetingSessionStore     │  │
│  │ • MUST/SHOULD/NICE  │  │ (SwiftData)             │  │
│  │ • 僅追蹤 .local    │  │ • MeetingSessionRecord  │  │
│  └─────────────────────┘  │ • TranscriptRecord    │  │
│                              │ • CardRecord           │  │
│  ┌─────────────────────┐  └───────────────────────┘  │
│  │ KeychainManager    │  ┌───────────────────────┐  │
│  │ • Claude API Key  │  │ ProviderProtocols       │  │
│  │ • NLM Notebook ID │  │ • KnowledgeRetrieval    │  │
│  │ • Bridge Secret   │  │ • GenerativeResponse    │  │
│  └─────────────────────┘  │ • TranscriptProvider   │  │
│                              └───────────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

### 雙串流說話者分離（v4.3 核心）

```
SystemAudioEngine (ScreenCaptureKit) → 「對方的聲音」 → .remote
  → 觸發問題偵測 → 進入三層 AI 管線

MicrophoneEngine (AVAudioEngine) → 「我的聲音」 → .local
  → 僅用於 TP 追蹤（偵測「我講了什麼」）
  → 永遠不觸發問題偵測
```

硬體層級天然分離，零延遲、零成本，遠端會議場景準確率 ~95%+。

### 三層即時管線

```
問題偵測(.remote) → ① 本地 Q&A (< 200ms) → 🔵 命中即返回
                    → ② NotebookLM RAG (1-3s) → 找到相關段落
                    → ③ Claude + context (2-4s) → 🟣 有文件佐證的 AI 回答
背景: 每 3 分鐘 → 🟠 策略分析（含 TP 狀態）
持續: TP 追蹤(.local) → ⚠️ MUST 未講提醒
```

## 安全設計

| 層面 | 措施 |
|------|------|
| **API Key** | macOS Keychain 安全儲存，首次啟動設定流程 |
| **Bridge 認證** | x-bridge-secret header（shared secret） |
| **CORS** | 僅允許 localhost / 127.0.0.1 |
| **Log 脫敏** | 問題內容僅留前 20 字 |
| **資料持久化** | SwiftData 本地存儲（不上雲） |

## 檔案結構

```
MeetingCoPilotAIApp1/
│
├── MeetingCopilot.xcodeproj/        # Xcode 專案（v4.3.0 build 4）
├── MeetingCopilot/                  # App 入口
│   ├── MeetingCopilotApp.swift       # @main + API Key 設定 UI
│   ├── Info.plist / .entitlements
│   └── Assets.xcassets/
│
├── Sources/ (14 個 Swift 檔案)
│   ├── 音訊層：AudioCaptureEngine / SystemAudio / Microphone
│   ├── AI 服務：KeywordMatcher+Claude / NotebookLM / TPTracker
│   ├── 架構層：ProviderProtocols / TranscriptPipeline(雙串流) / ResponseOrchestrator / Coordinator
│   └── 基礎設施：KeychainManager / MeetingSessionStore(SwiftData) / DemoDataProvider / UsageExample
│
├── Tests/ (4 個測試)
│   ├── KeywordMatcherTests.swift
│   ├── QuestionDetectorTests.swift
│   ├── TalkingPointsTrackerTests.swift
│   └── ResponseOrchestratorTests.swift
│
├── bridge/                          # NotebookLM Bridge (v1.1 🔒)
│   ├── bridge-server.js              # CORS + auth + redact
│   ├── test-bridge.js / package.json
│   └── .env.example
│
├── TODO.md                          # 開發待辦與演進路線圖
├── .gitignore
└── README.md
```

## Quick Start

```bash
# 1. Clone + 開啟 Xcode
git clone https://github.com/chchlin1018/MeetingCoPilotAIApp1.git
open MeetingCoPilotAIApp1/MeetingCopilot.xcodeproj

# 2. 首次啟動設定 API Key（Keychain 安全儲存）
# App 會自動彈出設定視窗，或 ⌘, 開啟

# 3. 啟動 Bridge（可選）
cd bridge && npm install && npm run dev
# 複製啟動時顯示的 Bridge Secret 到 App 設定

# 4. Xcode ⌘+R build & run
```

## 版本演進

| 版本 | 主題 | 狀態 |
|------|------|:----:|
| v4.0 | 雙引擎即時管線 | ✅ |
| v4.1 | 三層管線 + TP 追蹤 + NotebookLM Bridge | ✅ |
| v4.2 | 工程化重構（Coordinator -57% + Keychain + Provider Protocol） | ✅ |
| **v4.3** | **雙串流說話者分離 + SwiftData + Bridge 安全** | **✅ 目前** |
| v4.4 | Evidence-based Card + Bridge Optional + 雙串流 UI | 🔜 |
| v5.0 | Speaker Diarization + WhisperKit + Enterprise | 🔮 |

詳細開發待辦請參考 [TODO.md](TODO.md)

## 技術規格

| 項目 | 值 |
|------|-----|
| 平台 | macOS 14.0+ (Sonoma) |
| 語言 | Swift 5.0, Strict Concurrency |
| UI | SwiftUI + @Observable |
| 持久化 | SwiftData |
| 安全 | macOS Keychain + Bridge Auth |
| Bundle ID | com.macrovision.MeetingCopilot |
| 版本 | 4.3.0 (build 4) |
| Swift 檔案 | 14 個 + 4 測試 |
| 架構 | Actor-based, Dual-stream, Event-driven |

## 授權

MacroVision Systems — com.macrovision.MeetingCopilot
