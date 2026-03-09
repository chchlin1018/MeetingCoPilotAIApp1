# MeetingCopilot v4.1 — 三層即時管線 AI 會議助手

> 會前準備 × 會中即時 × 會後整理 — 專為高壓商務場景設計的 AI 提詞板

## 產品定位

MeetingCopilot 是一款 macOS 原生 AI 會議助手，透過即時擷取線上會議音訊（Teams / Zoom / Meet），自動偵測對方提問，並在**秒級延遲內**提供 AI 建議回答——就像一個隱形的會議顧問坐在你旁邊。

### 三大使用場景

| 場景 | 痛點 | AI 角色 | 即時性要求 |
|------|------|---------|-----------|
| **多人線上會議** | 議題發散、忘記該講的重點 | 秘書 — TP 追蹤 + 偏離提醒 | 中等 |
| **高壓會議**（Board / 客戶提案） | 被問倒、數據記不住 | 隱形顧問 — 2 秒給數字和反駁論點 | 最高 |
| **面試 / Review Meeting** | 緊張遺漏準備內容、被追問沒準備到的角度 | 提詞板 + 教練 — 預載答案 + AI 即時補位 | 高 |

## 核心架構：三層即時管線（v4.1）

```
┌─────────────────────────────────────────────────────────────┐
│  音訊擷取 → 語音轉文字 → 問題偵測                              │
│                │                                               │
│      ┌─────────┴──────────┐                                    │
│      │                     │                                    │
│      ▼                     ▼                                    │
│   ① 本地 Q&A            ② NotebookLM                         │
│   匹配 < 200ms          RAG 查詢 1-3s                          │
│      │                     │                                    │
│      │ 命中               │ 找到相關段落                         │
│      ▼                     ▼                                    │
│   🔵 藍色卡片           ③ Claude Sonnet                       │
│   （預載答案）           + NotebookLM context                   │
│                          2-4s streaming                        │
│                            │                                    │
│                            ▼                                    │
│                         🟣 紫色卡片                             │
│                         （AI + 文件佐證）                       │
│                                                                │
│   背景：每 3 分鐘 → 🟠 橘色卡片（策略分析 + TP 狀態）         │
│   持續：TP 追蹤   → 🟢 面板指示器 + ⚠️ 黃色提醒卡片           │
└─────────────────────────────────────────────────────────────┘
```

**v4.0 → v4.1 關鍵升級：**
- 雙路徑 → **三層管線**：新增 NotebookLM 即時查詢作為第二層
- 新增 **Talking Points 即時追蹤**（MUST / SHOULD / NICE 三級優先）
- 新增 **NotebookLM Node.js Bridge**（Mock + Puppeteer 雙引擎）
- UI 升級：TP 面板、NotebookLM 連線狀態、管線即時指示器

## 延遲預算

| 階段 | 延遲目標 | 引擎 |
|------|---------|------|
| 音訊擷取 | 即時 | ScreenCaptureKit |
| 語音轉文字 | 300-500ms | Apple Speech (partial results) |
| 問題偵測 | ~100ms | QuestionDetector（規則引擎） |
| ① Q&A 匹配（命中） | < 50ms | KeywordMatcher（多關鍵字評分） |
| ② NotebookLM 查詢 | 1-3s | notebooklm-kit bridge |
| ③ Claude + context | 2-4s | Claude Sonnet Streaming |
| TP 追蹤 | < 50ms | TalkingPointsTracker |
| **端到端（命中）** | **< 1s** ✅ | |
| **端到端（② + ③）** | **3-7s** ⚠️ | Streaming 緩解等待感 |

## 檔案結構

```
MeetingCoPilotAIApp1/
│
├── Sources/                            # Swift 原始碼（macOS 14.0+）
│   ├── AudioCaptureEngine.swift        # Protocol + 共用型別
│   ├── SystemAudioCaptureEngine.swift  # 主引擎（ScreenCaptureKit 系統音訊）
│   ├── MicrophoneCaptureEngine.swift   # 降級引擎（麥克風 fallback）
│   ├── KeywordMatcherAndClaude.swift   # 第一層 Q&A + 第三層 Claude API
│   ├── NotebookLMService.swift         # ★ 第二層 NotebookLM 即時查詢
│   ├── TalkingPointsTracker.swift      # ★ Talking Points 即時追蹤（P0）
│   ├── MeetingAICoordinator.swift      # ★ 三層管線總指揮（v4.1 重寫）
│   └── UsageExample.swift              # SwiftUI 完整 Demo（UMC 場景）
│
├── bridge/                             # NotebookLM Node.js Bridge
│   ├── package.json                    # express + puppeteer + dotenv
│   ├── bridge-server.js                # 主服務（Mock / Puppeteer 雙模式）
│   ├── test-bridge.js                  # 整合測試（9 項）
│   ├── .env.example                    # 設定範本
│   └── README.md                       # Bridge API 文件
│
└── README.md                           # 本檔案
```

## 功能 × 場景對照

| 功能 | 多人會議 | 高壓會議 | 面試/Review |
|------|:-------:|:-------:|:----------:|
| Talking Points 追蹤 | ✅ 核心 | ✅ 必要 | ⚠️ 次要 |
| Q&A 本地匹配（第一層） | ⚠️ 偶爾 | ✅ 高頻 | ✅ 核心 |
| NotebookLM 即時查詢（第二層） | ⚠️ 偶爾 | ✅ 關鍵 | ✅ 關鍵 |
| Claude 即時策略（第三層） | ⚠️ 低頻 | ✅ 核心 | ✅ 高頻 |
| 議題偏離提醒 | ✅ 核心 | ✅ 必要 | ❌ |
| 背景策略分析（每 3 分鐘） | ✅ | ✅ | ✅ |

## Quick Start

### 1. 啟動 NotebookLM Bridge

```bash
cd bridge
npm install
npm run dev        # Mock 模式（開發測試）
```

### 2. Swift App 初始化

```swift
// 建立 Coordinator（三層管線核心）
let coordinator = MeetingAICoordinator(
    claudeAPIKey: "sk-ant-...",
    notebookLMConfig: .enabled(notebookId: "your_notebook_id"),
    meetingContext: yourContext
)

// 載入 Q&A 知識庫（第一層）
await coordinator.loadKnowledgeBase(qaItems)

// 載入 Talking Points
await coordinator.loadTalkingPoints([
    TalkingPoint(content: "IDTF 與 AVEVA 差異", priority: .must,
                 keywords: ["AVEVA", "差異", "定位"]),
    TalkingPoint(content: "ROI 預估", priority: .must,
                 keywords: ["ROI", "投資報酬", "成本"]),
    TalkingPoint(content: "資安合規", priority: .should,
                 keywords: ["資安", "ISO", "合規"]),
], meetingDurationMinutes: 60)

// 啟動會議（自動選擇最佳音訊引擎）
await coordinator.startMeeting()

// SwiftUI 綁定
ForEach(coordinator.cards) { card in AICardView(card: card) }
ForEach(coordinator.talkingPoints) { tp in TalkingPointRow(talkingPoint: tp) }

// 結束會議
await coordinator.stopMeeting()
print(coordinator.stats.summary)
// → "45m | Cards: 12 (🔵3 📚8 🟣6 🟠3) | Latency: 2100ms | Cost: $0.20"
```

## 技術亮點

### 插件化音訊引擎
`AudioCaptureEngine` Protocol 讓主引擎（ScreenCaptureKit）和降級引擎（Microphone）可插拔，未來可新增 WhisperKit 離線引擎。

### Actor 隔離
所有音訊引擎和服務都用 Swift Actor 確保線程安全，`@Observable @MainActor` 供 SwiftUI 即時綁定。

### NotebookLM 即時查詢
會中偵測到未匹配問題時，先 query NotebookLM 找到 2-3 個最相關段落，再把段落餵給 Claude 當 context——讓 AI 回答有文件佐證，不是憑空生成。

### Talking Points 智慧追蹤
持續比對逐字稿與 TP 關鍵字，自動偵測「講到了」。會議過半 MUST 未講 → ⚠️ 提醒；話題相關 → 💡 時機提示。

### Claude 節流
5 秒最小查詢間隔 + 同一 Q&A 20 秒 cooldown，避免 API 成本失控。60 分鐘會議 AI 成本約 $1.00-1.50。

## Token 經濟學

| 項目 | 數值 |
|------|------|
| 每次 Claude 查詢 | ~5,200 input + ~500 output ≈ $0.022 |
| 60 分鐘會議 | ~20-40 查詢 + ~20 策略分析 ≈ $1.00-1.50 |
| Professional $49/月（20 場） | AI 變動成本 ≈ $30，毛利 38% |
| Executive $89/月（40 場） | AI 變動成本 ≈ $60，毛利 33% |

## 系統需求

- macOS 14.0+（Sonoma）
- Screen Recording 權限（系統設定 → 隱私權 → 螢幕錄製）
- Speech Recognition 權限
- 網路（Apple Speech 雲端 + Claude API）
- Node.js 18+（NotebookLM Bridge）

## 開發路線圖

### ✅ V1.0（已完成）
- [x] ScreenCaptureKit 系統音訊擷取 + 即時轉錄
- [x] 本地 Q&A 匹配（第一層）
- [x] Claude Streaming 即時生成（第三層）
- [x] NotebookLM 即時查詢（第二層）
- [x] Talking Points 即時追蹤
- [x] NotebookLM Node.js Bridge（Mock + Puppeteer）
- [x] SwiftUI 完整 Demo UI

### 🔜 V1.5（下一步）
- [ ] NotebookLM 雙向整合（會後逐字稿存回）
- [ ] Audio Overview（會議 Podcast）一鍵生成
- [ ] 多人發言辨識（Speaker Diarization）
- [ ] QuestionDetector 升級為 NLP 語意分類

### 🔮 V2.0（未來）
- [ ] WhisperKit 離線語音引擎
- [ ] 本地 embedding 向量比對取代關鍵字匹配
- [ ] iOS 版（iPhone 作為提詞板）
- [ ] 多語言支援（日文 / 韓文）

## 授權

Private Repository — MacroVision Systems
