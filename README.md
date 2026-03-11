# MeetingCopilot v4.3.1 — 雙串流即時 AI 會議助手

> 會前準備 × 會中即時 × 會後回看 — 專為高壓商務場景設計的 AI 提詞板

## 產品定位

MeetingCopilot 是一款 macOS 原生 AI 會議助手，透過即時擷取線上會議音訊（Teams / Zoom / Meet），自動偵測**對方提問**，並在秒級延遲內提供 AI 建議回答。

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

專門測試 Zoom/Teams 會議的雙串流即時語音辨識，不含任何 AI 層：

```bash
git checkout feature/transcript-only
open TranscriptOnly.xcodeproj
# ⌘R → 開 Zoom/Teams → 按「開始會議」
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
│  Email Draft → quote block + checkbox
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
│  │ ★ 雙串流 + 分色    │  │                            │ │
│  │ TranscriptEntry[] │  │ ★ 雙來源並行 RAG          │ │
│  │ SystemAudio→remote│→→│ NotebookLM(文件數據)      │ │
│  │ Microphone →local │  │ Notion(個人策略)          │ │
│  │ ★ Live Partial    │  │ → 並行查詢 → 合併 → Claude │ │
│  └─────────────────────┘  └───────────────────────────┘ │
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
│                                                          │
│  ┌─────────────────────┐  ┌───────────────────────────┐ │
│  │ SystemCheckView     │  │ PostMeetingReportService   │ │
│  │ ★ 會前 8 項診斷    │  │ • AI 摘要 + Action Items  │ │
│  │ • Mic / Speech / TCC│  │ • Markdown / TXT 匯出     │ │
│  │ • Claude / Notion   │  │ • Notion 匯出             │ │
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

## 檔案結構

```
MeetingCoPilotAIApp1/
│
├── MeetingCopilot.xcodeproj/           # v4.3.1 build 8（完整版）
├── TranscriptOnly.xcodeproj/           # ★ v1.0 精簡版（feature/transcript-only 分支）
│
├── MeetingCopilot/                     # 完整版 App 入口
│   ├── MeetingCopilotApp.swift          # @main + API Key 設定
│   ├── Info.plist / .entitlements
│   └── Assets.xcassets/
│
├── TranscriptOnly/                     # ★ 精簡版 App 入口（feature/transcript-only）
│   ├── TranscriptOnlyApp.swift          # @main（無 API Key）
│   ├── TranscriptOnlyView.swift         # UI + ViewModel（直接接 Pipeline）
│   ├── Info.plist / .entitlements
│   └── Assets.xcassets/
│
├── Sources/ (18 個 Swift 檔案)
│   │
│   │  ── 音訊層（TranscriptOnly 共用）──
│   ├── AudioCaptureEngine.swift         # Protocol + 共用型別
│   ├── SystemAudioCaptureEngine.swift   # 主引擎 (ScreenCaptureKit) → remote
│   ├── MicrophoneCaptureEngine.swift    # 降級引擎 (Mic) → local
│   ├── TranscriptPipeline.swift         # 雙串流 + Live Partial + Audio Health
│   │
│   │  ── AI 服務層（僅完整版）──
│   ├── KeywordMatcherAndClaude.swift    # 第一層 Q&A + Claude API
│   ├── NotebookLMService.swift          # 第二層 NotebookLM RAG
│   ├── NotionRetrievalService.swift     # 第二層 Notion RAG
│   ├── TalkingPointsTracker.swift       # TP 追蹤 + detectedSpeech
│   │
│   │  ── 架構層（僅完整版）──
│   ├── ProviderProtocols.swift          # 3 個抽象介面
│   ├── ResponseOrchestrator.swift       # 雙來源並行 RAG + Claude
│   ├── MeetingAICoordinator.swift       # 瘦身 Coordinator + SwiftData
│   │
│   │  ── 基礎設施（僅完整版）──
│   ├── KeychainManager.swift            # Keychain
│   ├── MeetingSessionStore.swift        # SwiftData persistence
│   ├── SystemMonitor.swift              # CPU / Memory / Network
│   ├── SystemCheckView.swift            # 會前 8 項系統診斷
│   ├── PostMeetingReportService.swift   # AI 摘要 + Action Items + Notion 匯出
│   ├── MeetingPrepView.swift            # 會前準備 UI + TXT + 語言選擇
│   ├── DemoDataProvider.swift           # Demo 資料
│   └── UsageExample.swift               # 主畫面 + 分色逐字稿 + 會後儲存
│
├── Tests/ (4 個測試)
├── bridge/                             # NotebookLM Bridge (Node.js)
├── skills/                             # Claude MeetingPrep Skill
│   └── MeetingPrep-SKILL.md
├── scripts/                            # Notion 模板建立腳本
├── templates/                          # TXT + Notion 模板
├── MeetingTEXT/                        # 會前準備 TXT 檔案
│   ├── 2026-03-11_BiWeekly-Stanley.txt
│   ├── 2026-03-12_BiWeekly-Mark-JJ.txt
│   └── ...
├── TODO.md
├── TranscriptOnly-README.md
├── .gitignore
└── README.md
```

## Quick Start

### 完整版（main 分支）

```bash
git clone https://github.com/chchlin1018/MeetingCoPilotAIApp1.git
cd MeetingCoPilotAIApp1
open MeetingCopilot.xcodeproj
# Signing → Development Team → ⌘R
# 設定 Claude API Key + Notion API Key → 系統檢查 → 開始會議
```

### 精簡版（transcript-only 分支）

```bash
git clone https://github.com/chchlin1018/MeetingCoPilotAIApp1.git
cd MeetingCoPilotAIApp1
git checkout feature/transcript-only
open TranscriptOnly.xcodeproj
# Signing → Development Team → ⌘R
# 開 Zoom/Teams → 按「開始會議」（不需要任何 API Key）
```

### 取得 API Keys（完整版）

| 服務 | 取得方式 |
|------|--------|
| Claude | https://console.anthropic.com/settings/keys |
| Notion | https://www.notion.so/profile/integrations → New integration |

### 權限需求

- **螢幕與系統錄音**：System Settings → Privacy & Security → Screen & System Audio Recording → 開啟
- **麥克風**：首次啟動自動請求
- **語音辨識**：首次啟動自動請求

每次 Xcode rebuild 後可能需要重新授權 TCC：
```bash
tccutil reset ScreenCapture com.RealityMatrix.MeetingCopilot
# 或精簡版
tccutil reset ScreenCapture com.RealityMatrix.TranscriptOnly
```

## 版本演進

| 版本 | 主題 | 狀態 |
|------|------|:----:|
| v4.0 | 雙引擎即時管線 | ✅ |
| v4.1 | 三層管線 + TP 追蹤 + NotebookLM Bridge | ✅ |
| v4.2 | 工程化重構（Coordinator -57% + Keychain + Provider Protocol） | ✅ |
| v4.3 | 雙串流 + 雙來源並行 RAG + 分色 UI + 系統監控 + 會後儲存 | ✅ |
| v4.3.1 | SystemCheck + Live Partial + 錯誤訊息改善 + 配色統一 | ✅ |
| **TranscriptOnly** | **精簡分支 — 純雙串流語音辨識測試（6 Swift 檔案）** | **✅ 測試中** |
| v4.4 | Evidence-based Card + Claude 動態關鍵字 + Notion 自動同步 | 🔜 |
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
| 會前診斷 | SystemCheckView（8 項自動檢測） |
| 會前準備 | MeetingPrep Skill（Notion SSOT → TXT → App） |
| 主 Bundle ID | com.RealityMatrix.MeetingCopilot |
| 測試 Bundle ID | com.RealityMatrix.TranscriptOnly |
| 版本 | 4.3.1 (build 8) |
| Swift 檔案 | 18 個 + 2 個 (TranscriptOnly) + 4 測試 |
| 架構 | Actor-based, Dual-stream, Event-driven |
| 74 commits | main: 18 files, transcript-only: 6 files |

## 授權

Reality Matrix Inc. — com.RealityMatrix.MeetingCopilot
