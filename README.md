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

## 會前準備工作流

```
會前 1-2 天：NotebookLM（文件萃取）
│  上傳 PDF / PPTX / XLSX / 影片 / URL
│  Google 語意搜尋 + 向量索引 → 精確數據
│
會前半天：Claude + Notion（策略規劃）
│  Goals、Talking Points、Q&A 建議、談判策略
│
會前 5 分鐘：MeetingCopilot App
│  載入 TXT → 選語言 → 開始會議
│
會中即時：雙串流 + 雙來源並行 RAG
│  對方問「ROI 怎麼算？」
│  ├─ NotebookLM → 「財報 p.17: OEE +2.1%, $450K」
│  └─ Notion     → 「策略：強調 3.2 月回收期」
│  → Claude 合併 → 同時有數據佐證 + 策略建議
│
會後：儲存逐字稿 + AI 卡片 + TP 狀態 → TXT
```

## 軟體架構（v4.3）

```
┌─────────────────────────────────────────────────────────┐
│  MeetingAICoordinator + SwiftData Persistence           │
│  @Observable @MainActor                                 │
│                                                          │
│  ┌─────────────────────┐  ┌───────────────────────────┐ │
│  │ TranscriptPipeline  │  │ ResponseOrchestrator       │ │
│  │ ★ 雙串流 + 分色    │  │                            │ │
│  │ TranscriptEntry[] │  │ ★ 雙來源並行 RAG          │ │
│  │ SystemAudio→remote│→→│ NotebookLM(文件數據)      │ │
│  │ Microphone →local │  │ Notion(個人策略)          │ │
│  └─────────────────────┘  │ → 並行查詢 → 合併 → Claude │ │
│                           └───────────────────────────┘ │
│                                                          │
│  ┌─────────────────────┐  ┌───────────────────────────┐ │
│  │ TalkingPointsTracker│  │ MeetingPrepView            │ │
│  │ • MUST/SHOULD/NICE  │  │ • 會前資料輸入 UI          │ │
│  │ • detectedSpeech   │  │ • TXT 儲存/讀取           │ │
│  │ • 偵測到我方已講    │  │ • 語言選擇 (5 種)       │ │
│  └─────────────────────┘  └───────────────────────────┘ │
│                                                          │
│  ┌─────────────────────┐  ┌───────────────────────────┐ │
│  │ KeychainManager     │  │ SystemMonitor              │ │
│  │ • Claude API Key    │  │ • CPU / Memory / Network   │ │
│  │ • Notion API Key    │  │ • Mach API + vm_statistics │ │
│  │ • NLM Notebook ID   │  │ • 3s polling               │ │
│  └─────────────────────┘  └───────────────────────────┘ │
└─────────────────────────────────────────────────────────┘
```

### 三層即時管線（雙來源並行）

```
問題偵測(.remote) → ① 本地 Q&A (< 200ms) → 🔵 命中即返回
                   → ② 雙來源並行 RAG (1-3s)
                        ├─ 📄 NotebookLM → 文件原文數據（PDF/PPTX/XLSX）
                        └─ 📝 Notion     → 個人策略筆記（Goals/TP/Q&A）
                        → 合併 context
                   → ③ Claude + merged context (2-4s) → 🟣 有佐證的 AI 回答
背景: 每 3 分鐘 → 🟠 策略分析（含 TP 狀態）
持續: TP 追蹤(.local) → ⚠️ MUST 未講提醒 + ✅ 偵測到我方已講
```

### 雙串流說話者分離

```
SystemAudioEngine (ScreenCaptureKit) → 「對方的聲音」 → .remote
  → 觸發問題偵測 → 進入三層 AI 管線

MicrophoneEngine (AVAudioEngine) → 「我的聲音」 → .local
  → TP 追蹤 + 偵測到我方已講標示
```

硬體層級天然分離，零延遲、零成本，遠端會議場景準確率 ~95%+。

## 使用流程

```
App 開啟 → API Key 設定（Claude + Notion + NotebookLM）
    ↓
會前準備 UI
    ├── 輸入目標、參與者、Q&A、Talking Points
    ├── 選擇語音辨識語言（zh-TW / en-US / en-GB / zh-CN / ja-JP）
    ├── [儲存 TXT] / [讀取 TXT] / [載入 Demo]
    └── [開始會議]
    ↓
會議進行中
    ├── 即時逐字稿（對方 白色 / 我方 青色 分色顯示）
    ├── AI 提詞卡片（🔵本地 / 🟣Claude / 🟠策略）
    ├── TP 追蹤（✅ 偵測到我方已講 / 🔊 偵測中）
    ├── 系統健康（CPU / 記憶體 / 網路品質）
    └── 手動提問（Ask AI anything...）
    ↓
會議結束
    ├── 會後摘要（TP 完成率、AI 卡片數）
    └── [儲存逐字稿 + AI 卡片] 為 TXT
```

## 安全設計

| 層面 | 措施 |
|------|------|
| **API Key** | macOS Keychain 安全儲存（Claude + Notion） |
| **Notion** | 官方 REST API，Bearer token 認證 |
| **NotebookLM** | Bridge x-bridge-secret + CORS localhost |
| **資料持久化** | SwiftData 本地存儲（不上雲） |

## 檔案結構

```
MeetingCoPilotAIApp1/
│
├── MeetingCopilot.xcodeproj/           # v4.3.0 build 7
├── MeetingCopilot/
│   ├── MeetingCopilotApp.swift          # @main + API Key 設定 (Claude + Notion + NLM)
│   ├── Info.plist / .entitlements
│   └── Assets.xcassets/
│
├── Sources/ (17 個 Swift 檔案)
│   │
│   │  ── 音訊層 ──
│   ├── AudioCaptureEngine.swift         # Protocol + 共用型別
│   ├── SystemAudioCaptureEngine.swift   # 主引擎 (ScreenCaptureKit) → remote
│   ├── MicrophoneCaptureEngine.swift    # 降級引擎 (Mic) → local
│   │
│   │  ── AI 服務層 ──
│   ├── KeywordMatcherAndClaude.swift    # 第一層 Q&A + Claude API
│   ├── NotebookLMService.swift          # 第二層 NotebookLM RAG（文件數據）
│   ├── NotionRetrievalService.swift     # 第二層 Notion RAG（個人策略）
│   ├── TalkingPointsTracker.swift       # TP 追蹤 + detectedSpeech
│   │
│   │  ── 架構層 ──
│   ├── ProviderProtocols.swift          # 3 個抽象介面
│   ├── TranscriptPipeline.swift         # 雙串流 + TranscriptEntry[]
│   ├── ResponseOrchestrator.swift       # 雙來源並行 RAG + Claude
│   ├── MeetingAICoordinator.swift       # 瘦身 Coordinator + SwiftData
│   │
│   │  ── 基礎設施 ──
│   ├── KeychainManager.swift            # Keychain (Claude + Notion + NLM)
│   ├── MeetingSessionStore.swift        # SwiftData persistence
│   ├── SystemMonitor.swift              # CPU / Memory / Network 監控
│   ├── MeetingPrepView.swift            # 會前準備 UI + TXT + 語言選擇
│   ├── DemoDataProvider.swift           # Demo 資料
│   └── UsageExample.swift               # 主畫面 + 分色逐字稿 + 會後儲存 + 系統健康
│
├── Tests/ (4 個測試)
├── bridge/                             # NotebookLM Bridge
├── TODO.md
├── .gitignore
└── README.md
```

## Quick Start

```bash
# 1. Clone + 開啟 Xcode
git clone https://github.com/chchlin1018/MeetingCoPilotAIApp1.git
open MeetingCoPilotAIApp1/MeetingCopilot.xcodeproj

# 2. Signing: 選擇你的 Development Team
#    General > Bundle ID: com.RealityMatrix.MeetingCopilot

# 3. ⌘+R Build & Run
#    首次啟動設定：
#    - Claude API Key（必填）: sk-ant-api03-...
#    - Notion API Key（建議）: ntn_...
#    - NotebookLM（選填）

# 4. 會前準備 → 輸入資料或載入 TXT → 選語言 → 開始會議
```

### 取得 API Keys

| 服務 | 取得方式 |
|------|--------|
| Claude | https://console.anthropic.com/settings/keys |
| Notion | https://www.notion.so/profile/integrations → New integration |

Notion 設定後，需在每個要搜尋的 page 點「⋯」→「Connections」→ 加入 Integration。

## 版本演進

| 版本 | 主題 | 狀態 |
|------|------|:----:|
| v4.0 | 雙引擎即時管線 | ✅ |
| v4.1 | 三層管線 + TP 追蹤 + NotebookLM Bridge | ✅ |
| v4.2 | 工程化重構（Coordinator -57% + Keychain + Provider Protocol） | ✅ |
| **v4.3** | **雙串流 + 雙來源並行 RAG + 分色 UI + 系統監控 + 會後儲存** | **✅ 目前** |
| v4.4 | Evidence-based Card + Claude 動態關鍵字 + Telemetry | 🔜 |
| v5.0 | Speaker Diarization + WhisperKit + Enterprise | 🔮 |

詳細開發待辦請參考 [TODO.md](TODO.md)

## 技術規格

| 項目 | 值 |
|------|-----|
| 平台 | macOS 14.0+ (Sonoma) |
| 語言 | Swift 5.0, Strict Concurrency |
| UI | SwiftUI + @Observable |
| 持久化 | SwiftData |
| RAG | NotebookLM(文件) + Notion(策略) 並行 |
| 安全 | macOS Keychain |
| 語音辨識 | Apple Speech（zh-TW / en-US / en-GB / zh-CN / ja-JP）|
| 系統監控 | CPU (Mach API) + Memory (vm_statistics64) + Network |
| Bundle ID | com.RealityMatrix.MeetingCopilot |
| 版本 | 4.3.0 (build 7) |
| Swift 檔案 | 17 個 + 4 測試 |
| 架構 | Actor-based, Dual-stream, Event-driven |

## 授權

Reality Matrix Inc. — com.RealityMatrix.MeetingCopilot
