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
│                                                      │
│  ┌──────────────────┐  ┌────────────────────────┐   │
│  │ KeychainManager   │  │ DemoDataProvider        │   │
│  │ (安全儲存)        │  │ (Demo 資料隔離)         │   │
│  │ • Claude API Key  │  │ • UMC 場景 Q&A          │   │
│  │ • NLM Notebook ID │  │ • Talking Points        │   │
│  │ • Bridge URL      │  │ • Meeting Context       │   │
│  └──────────────────┘  └────────────────────────┘   │
└─────────────────────────────────────────────────────┘
```

### v4.2 工程化重構總結

| 變更 | 說明 |
|------|------|
| **God Object 拆分** | MeetingAICoordinator: 650 行 → 280 行（-57%） |
| **TranscriptPipeline** | 音訊引擎 + 轉錄 + 問題偵測獨立為 actor |
| **ResponseOrchestrator** | 三層管線 + 策略分析 + 卡片管理獨立為 actor |
| **ProviderProtocols** | 3 個抽象介面，未來可替換 Claude/NotebookLM/Speech |
| **DemoDataProvider** | Demo 資料從 UsageExample 完全隔離 |
| **KeychainManager** | API Key 安全儲存到 macOS Keychain（不再硬編碼） |
| **APIKeySettingsView** | 首次啟動設定流程（SecureField + 驗證） |
| **事件驅動** | Orchestrator 透過 AsyncStream&lt;Event&gt; 通知 UI |

### 三層即時管線

```
問題偵測 → ① 本地 Q&A (< 200ms) → 🔵 命中即返回
         → ② NotebookLM RAG (1-3s) → 找到相關段落
         → ③ Claude + context (2-4s) → 🟣 有文件佐證的 AI 回答
背景: 每 3 分鐘 → 🟠 策略分析（含 TP 狀態）
持續: TP 追蹤 → ⚠️ MUST 未講提醒
```

## 安全設計（v4.2）

### API Key 管理

API Key 透過 macOS Keychain 安全儲存，不再出現在程式碼中：

- **KeychainManager** — 封裝 macOS Security.framework
  - `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` 安全等級
  - 儲存 Claude API Key、NotebookLM ID、Bridge URL
  - `save` / `load` / `delete` CRUD 操作
- **首次啟動流程** — App 偵測到無 API Key 時自動彈出設定視窗
  - SecureField 輸入（驗證 `sk-ant-` 前綴）
  - 儲存到 Keychain 後自動關閉
  - ⌘, 可隨時重新開啟設定
- **UI 狀態指示** — Header 和 Stats 面板顯示 API Key 設定狀態

## 檔案結構

```
MeetingCoPilotAIApp1/
│
├── MeetingCopilot.xcodeproj/           # Xcode 專案（macOS 14.0+, v4.2.0 build 3）
│
├── MeetingCopilot/                     # App 目錄
│   ├── MeetingCopilotApp.swift         # @main 入口 + API Key 設定流程
│   ├── Info.plist                      # 隱私權描述（麥克風、語音辨識）
│   ├── MeetingCopilot.entitlements     # 非沙盒 + 音訊 + 網路
│   └── Assets.xcassets/                # App Icon + Accent Color
│
├── Sources/                            # Swift 原始碼（13 個檔案）
│   │
│   │  ── 音訊層 ──
│   ├── AudioCaptureEngine.swift        # Protocol + 共用型別
│   ├── SystemAudioCaptureEngine.swift  # 主引擎（ScreenCaptureKit）
│   ├── MicrophoneCaptureEngine.swift   # 降級引擎（Microphone fallback）
│   │
│   │  ── AI 服務層 ──
│   ├── KeywordMatcherAndClaude.swift   # 第一層 Q&A 匹配 + 第三層 Claude API
│   ├── NotebookLMService.swift         # 第二層 NotebookLM 即時查詢
│   ├── TalkingPointsTracker.swift      # TP 追蹤（MUST/SHOULD/NICE）
│   │
│   │  ── v4.2 架構層 ──
│   ├── ProviderProtocols.swift         # 抽象 Provider 介面（3 個 Protocol）
│   ├── TranscriptPipeline.swift        # 逐字稿管線（actor）
│   ├── ResponseOrchestrator.swift      # 回應編排器（actor）
│   ├── MeetingAICoordinator.swift      # 瘦身版 Coordinator（-57%）
│   │
│   │  ── 基礎設施 ──
│   ├── KeychainManager.swift           # macOS Keychain 安全儲存
│   ├── DemoDataProvider.swift          # Demo 資料隔離
│   └── UsageExample.swift              # SwiftUI 完整 Demo UI
│
├── bridge/                             # NotebookLM Node.js Bridge
│   ├── package.json                    # express + puppeteer + dotenv
│   ├── bridge-server.js                # Mock + Puppeteer 雙模式
│   ├── test-bridge.js                  # 整合測試（9 項）
│   ├── .env.example                    # 設定範本
│   └── README.md                       # Bridge API 文件
│
├── .gitignore
└── README.md
```

## Quick Start

### 1. Clone + 開啟 Xcode

```bash
git clone https://github.com/chchlin1018/MeetingCoPilotAIApp1.git
open MeetingCoPilotAIApp1/MeetingCopilot.xcodeproj
```

### 2. 設定 API Key

首次啟動 App 會自動彈出設定視窗：
- 輸入 Claude API Key（必填，`sk-ant-` 開頭）
- 輸入 NotebookLM Notebook ID（選填）
- 所有 key 安全儲存在 macOS Keychain

也可隨時透過選單 ⌘, 開啟設定。

### 3. 啟動 NotebookLM Bridge（可選）

```bash
cd bridge && npm install && npm run dev
```

### 4. Build & Run

Xcode ⌘+R 即可 build。首次需在 Signing & Capabilities 填入 Development Team。

## Provider 抽象

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

## 版本演進

### ✅ v4.0 — 雙引擎即時管線
- [x] ScreenCaptureKit 系統音訊 + Apple Speech 即時轉錄
- [x] 本地 Q&A 匹配 + Claude Streaming
- [x] 雙引擎自動降級（System → Microphone）

### ✅ v4.1 — 三層管線 + TP 追蹤
- [x] NotebookLM 即時查詢（第二層）
- [x] Talking Points 追蹤（MUST/SHOULD/NICE）
- [x] NotebookLM Node.js Bridge（Mock + Puppeteer）
- [x] SwiftUI 完整 Demo UI + Xcode Project

### ✅ v4.2 — 工程化重構（Week 1 完成）
- [x] God Object 拆分：Coordinator 650→280 行（-57%）
- [x] TranscriptPipeline actor：音訊引擎 + 轉錄 + 問題偵測
- [x] ResponseOrchestrator actor：三層管線 + 策略分析 + 卡片
- [x] Provider Protocol 抽象介面（3 個）
- [x] Demo 資料隔離（DemoDataProvider）
- [x] API Key → macOS Keychain（KeychainManager + 設定 UI）
- [x] Xcode Build Succeeded（13 Swift files, 0 errors）

### 🔜 v4.2 Week 2 — 基礎設施
- [ ] Bridge 安全加固（CORS localhost + shared secret + log redact）
- [ ] SwiftData 最小 persistence（MeetingSession / Transcript / CardHistory）
- [ ] XCTest 單元測試（KeywordMatcher / TP / QuestionDetector / Orchestrator）

### 🔜 v4.2 Week 3 — 卡片模型升級
- [ ] Evidence-based AICard（SourceCitation + 事實/推測區分）
- [ ] UI 顯示「來源依據」標示
- [ ] 會後 session summary 頁面

### 🔮 v5.0 — 產品化
- [ ] 多人發言辨識（Speaker Diarization）
- [ ] Action Item 自動擷取
- [ ] WhisperKit 離線引擎
- [ ] Enterprise 安全治理（CORS + auth + data retention）

## 技術規格

| 項目 | 值 |
|------|-----|
| 平台 | macOS 14.0+ (Sonoma) |
| 語言 | Swift 5.0, Strict Concurrency |
| UI | SwiftUI + @Observable |
| Bundle ID | com.macrovision.MeetingCopilot |
| 版本 | 4.2.0 (build 3) |
| Swift 檔案 | 13 個 |
| 架構 | Actor-based, Event-driven |
| 安全 | macOS Keychain, 非沙盒 |

## 授權

MacroVision Systems — com.macrovision.MeetingCopilot
