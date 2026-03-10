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
│  MeetingAICoordinator + SwiftData Persistence           │
│  @Observable @MainActor — UI 狀態代理                    │
│                                                          │
│  ┌─────────────────────┐  ┌───────────────────────────┐ │
│  │ TranscriptPipeline  │  │ ResponseOrchestrator       │ │
│  │ ★ 雙串流 (v4.3)     │  │                            │ │
│  │                     │  │ • 三層管線路由             │ │
│  │ SystemAudio → remote│→→│ • Notion RAG (優先)        │ │
│  │ Microphone  → local │  │ • NotebookLM (fallback)    │ │
│  └─────────────────────┘  │ • Claude Streaming         │ │
│                           └───────────────────────────┘ │
│                                                          │
│  ┌─────────────────────┐  ┌───────────────────────────┐ │
│  │ TalkingPointsTracker│  │ MeetingPrepView            │ │
│  │ • MUST/SHOULD/NICE  │  │ • 會前資料輸入 UI          │ │
│  │ • 僅追蹤 .local     │  │ • TXT 儲存/讀取           │ │
│  └─────────────────────┘  │ • 語言選擇                 │ │
│                           └───────────────────────────┘ │
│                                                          │
│  ┌─────────────────────┐  ┌───────────────────────────┐ │
│  │ KeychainManager     │  │ NotionRetrievalService     │ │
│  │ • Claude API Key    │  │ • Notion REST API          │ │
│  │ • Notion API Key    │  │ • 多關鍵字展開搜尋         │ │
│  │ • NLM Notebook ID   │  │ • 取代 NotebookLM Bridge   │ │
│  └─────────────────────┘  └───────────────────────────┘ │
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
                   → ② Notion RAG (1-2s)  → 搜尋 Notion 文件段落
                   →    NotebookLM (fallback) → Bridge 備用
                   → ③ Claude + context (2-4s) → 🟣 有文件佐證的 AI 回答
背景: 每 3 分鐘 → 🟠 策略分析（含 TP 狀態）
持續: TP 追蹤(.local) → ⚠️ MUST 未講提醒
```

## 使用流程

```
App 開啟 → API Key 設定（首次）
    ↓
會前準備 UI
    ├── 輸入會議目標、參與者、Q&A、Talking Points
    ├── 選擇語音辨識語言（zh-TW / en-US / en-GB / zh-CN / ja-JP）
    ├── [儲存] 為 TXT 檔案（下次可讀取重用）
    ├── [讀取] 從 TXT 載入
    └── [開始會議]
    ↓
會議進行中
    ├── 即時逐字稿（[對方] / [我方] 雙串流）
    ├── AI 提詞卡片（🔵本地匹配 / 🟣Claude / 🟠策略）
    ├── TP 追蹤（MUST/SHOULD/NICE 完成度）
    └── 手動提問（Ask AI anything...）
    ↓
會議結束
    ├── 會後摘要（TP 完成率、MUST 完成率、AI 卡片數）
    └── [儲存逐字稿 + AI 卡片] 為 TXT 檔案
```

## 安全設計

| 層面 | 措施 |
|------|------|
| **API Key** | macOS Keychain 安全儲存（Claude + Notion） |
| **Notion** | 官方 REST API，Bearer token 認證 |
| **Bridge** | x-bridge-secret header（shared secret）, CORS localhost |
| **Log 脫敏** | 問題內容僅留前 20 字 |
| **資料持久化** | SwiftData 本地存儲（不上雲） |

## 檔案結構

```
MeetingCoPilotAIApp1/
│
├── MeetingCopilot.xcodeproj/           # Xcode 專案（v4.3.0 build 6）
├── MeetingCopilot/                     # App 入口
│   ├── MeetingCopilotApp.swift          # @main + API Key 設定 UI (Claude + Notion)
│   ├── Info.plist / .entitlements
│   └── Assets.xcassets/
│
├── Sources/ (16 個 Swift 檔案)
│   │
│   │  ── 音訊層 ──
│   ├── AudioCaptureEngine.swift         # Protocol + 共用型別
│   ├── SystemAudioCaptureEngine.swift   # 主引擎（ScreenCaptureKit）→ remote
│   ├── MicrophoneCaptureEngine.swift    # 降級引擎（Microphone）→ local
│   │
│   │  ── AI 服務層 ──
│   ├── KeywordMatcherAndClaude.swift    # 第一層 Q&A 匹配 + Claude API
│   ├── NotionRetrievalService.swift     # ★ 第二層 Notion RAG（取代 NotebookLM）
│   ├── NotebookLMService.swift          # 第二層 NotebookLM（備用）
│   ├── TalkingPointsTracker.swift       # TP 追蹤（MUST/SHOULD/NICE）
│   │
│   │  ── 架構層 ──
│   ├── ProviderProtocols.swift          # 3 個抽象介面
│   ├── TranscriptPipeline.swift         # ★ 雙串流管線（v4.3）
│   ├── ResponseOrchestrator.swift       # Notion 優先 → NLM fallback → Claude
│   ├── MeetingAICoordinator.swift       # 瘦身版 Coordinator + SwiftData
│   │
│   │  ── 基礎設施 ──
│   ├── KeychainManager.swift            # Keychain（Claude + Notion + NLM）
│   ├── MeetingSessionStore.swift        # SwiftData persistence
│   ├── MeetingPrepView.swift            # ★ 會前準備 UI + TXT 儲存/讀取 + 語言選擇
│   ├── DemoDataProvider.swift           # Demo 資料
│   └── UsageExample.swift               # 主畫面 + 會後儲存逐字稿
│
├── Tests/ (4 個測試)
├── bridge/                             # NotebookLM Bridge（備用方案）
├── TODO.md                             # 開發待辦與演進路線圖
├── .gitignore
└── README.md
```

## Quick Start

```bash
# 1. Clone + 開啟 Xcode
git clone https://github.com/chchlin1018/MeetingCoPilotAIApp1.git
open MeetingCoPilotAIApp1/MeetingCopilot.xcodeproj

# 2. Xcode Signing: 選擇你的 Development Team

# 3. ⌘+R Build & Run
# 首次啟動會彈出 API Key 設定：
#   - Claude API Key（必填）: sk-ant-api03-...
#   - Notion API Key（建議）: ntn_...
#   - NotebookLM（選填，備用方案）

# 4. 會前準備 → 輸入資料或載入 TXT → 開始會議
```

### Notion API Key 取得方式

1. 開啟 https://www.notion.so/profile/integrations
2. 點 **New integration** → 名稱填 `MeetingCopilot`
3. 複製 API Key（`ntn_...`）
4. 在 Notion 中對要搜尋的 page 點「⋯」→「Connections」→ 加入 `MeetingCopilot`

## 版本演進

| 版本 | 主題 | 狀態 |
|------|------|:----:|
| v4.0 | 雙引擎即時管線 | ✅ |
| v4.1 | 三層管線 + TP 追蹤 + NotebookLM Bridge | ✅ |
| v4.2 | 工程化重構（Coordinator -57% + Keychain + Provider Protocol） | ✅ |
| **v4.3** | **雙串流 + 會前準備 UI + Notion RAG + 語言選擇 + 會後儲存** | **✅ 目前** |
| v4.4 | Evidence-based Card + 雙串流 UI 分色 + Telemetry | 🔜 |
| v5.0 | Speaker Diarization + WhisperKit + Enterprise | 🔮 |

詳細開發待辦請參考 [TODO.md](TODO.md)

## 技術規格

| 項目 | 值 |
|------|-----|
| 平台 | macOS 14.0+ (Sonoma) |
| 語言 | Swift 5.0, Strict Concurrency |
| UI | SwiftUI + @Observable |
| 持久化 | SwiftData |
| RAG | Notion API（主要）+ NotebookLM Bridge（備用）|
| 安全 | macOS Keychain |
| 語音辨識 | Apple Speech（zh-TW / en-US / en-GB / zh-CN / ja-JP）|
| Bundle ID | com.macrovision.MeetingCopilot |
| 版本 | 4.3.0 (build 6) |
| Swift 檔案 | 16 個 + 4 測試 |
| 架構 | Actor-based, Dual-stream, Event-driven |

## 授權

MacroVision Systems — com.macrovision.MeetingCopilot
