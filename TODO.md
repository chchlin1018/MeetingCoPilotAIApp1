# MeetingCopilot 開發待辦與演進路線圖

> 最後更新: 2026-03-11 | 版本: v4.3.1 (build 8) | Bundle: com.RealityMatrix.MeetingCopilot

---

## ✅ 已完成

### v4.0 — 雙引擎即時管線
- [x] ScreenCaptureKit 系統音訊擷取
- [x] MicrophoneCaptureEngine 降級方案
- [x] Apple Speech 即時轉錄（Partial Results）
- [x] 本地 Q&A 關鍵字匹配（< 200ms）
- [x] Claude API Streaming 回應

### v4.1 — 三層管線 + TP 追蹤
- [x] NotebookLM 即時查詢（第二層 RAG）
- [x] NotebookLM Node.js Bridge
- [x] Talking Points 追蹤（MUST/SHOULD/NICE）
- [x] 時間壓力提醒
- [x] SwiftUI 完整 Demo UI

### v4.2 — 工程化重構
- [x] God Object 拆分：Coordinator 650→280 行（-57%）
- [x] TranscriptPipeline / ResponseOrchestrator actor
- [x] Provider Protocol 抽象介面（3 個）
- [x] API Key → macOS Keychain

### v4.3 — 雙串流 + 個人測試可用
- [x] **雙串流說話者分離**（SystemAudio=對方 / Mic=我方）
- [x] **會前準備 UI**（目標、Q&A、TP、TXT 儲存/讀取）
- [x] **語音辨識語言選擇**（zh-TW / en-US / en-GB / zh-CN / ja-JP）
- [x] **會後儲存**（逐字稿 + AI 卡片 + TP 狀態 + 統計 → TXT）
- [x] **Notion RAG**（NotionRetrievalService）
  - [x] Notion REST API 搜尋 + block content 擷取
  - [x] 多關鍵字展開
  - [x] Keychain + 設定 UI
- [x] **雙來源並行 RAG**（NotebookLM + Notion 同時查詢，合併 context）
- [x] **雙串流 UI 分色顯示**
  - [x] TranscriptEntry structured 陣列
  - [x] [對方] 白色 + 白色左邊條 / [我方] 青色 + 青色左邊條
  - [x] ScrollViewReader 自動捲動
- [x] **TP 偵測標示**（✅ 偵測到我方已講 / 🔊 偵測中 + detectedSpeech）
- [x] **系統健康監控**（SystemMonitor）
  - [x] CPU 使用率（Mach API）
  - [x] 記憶體使用量 + 壓力指示（vm_statistics64）
  - [x] 網路品質（API 延遲滿動平均）
  - [x] 右側 SYSTEM HEALTH 面板 + 進度條 + 色碼
- [x] **Bundle ID 更新** com.RealityMatrix.MeetingCopilot
- [x] SwiftData Persistence
- [x] XCTest 單元測試（4 組）

### v4.3.1 — SystemCheck + 即時體驗改善
- [x] **會前系統檢查**（SystemCheckView）
  - [x] 8 項自動檢測：麥克風、語音辨識、螢幕錄製、音訊擷取、語音辨識、Claude AI、Notion API、NotebookLM Bridge
  - [x] 即時狀態顯示（pending/testing/passed/failed/skipped）
  - [x] 延遲時間顯示（ms）
  - [x] 加入 Xcode project target（project.pbxproj）
- [x] **KeychainManager API 修正**
  - [x] `KeychainManager.shared.retrieve()` → `KeychainManager.load(key:)`（enum 靜態方法，非 class singleton）
  - [x] 修復 SystemCheckView 3 個 build error
- [x] **TranscriptPipeline 錯誤訊息分類**
  - [x] `describeError()` 根據 AudioCaptureError 類型顯示不同訊息
  - [x] noAudioSourceFound → 「找不到會議 App」（而非「權限未授權」）
  - [x] permissionDenied → 「權限未授權（需在系統設定開啟）」
- [x] **即時 Partial Results 顯示**
  - [x] Transcript panel 底部紫色波形 + monospaced 即時文字
  - [x] 「正在聆聽...」（取代空白的「等待會議音訊...」）
  - [x] recentTranscript 直接取 segment text（修復雙串流空白 bug）
  - [x] buildMergedTranscript() 加入 partial text
- [x] **說話者配色統一**
  - [x] 對方 = 青色（cyan）/ 我方 = 黃色（yellow）
  - [x] 適用於：已確認 entries、partial indicator、header legend
- [x] **音訊健康監控 badge**
  - [x] Header bar 顯示對方/我方串流狀態（active/idle/disconnected）
  - [x] segment count 即時更新
  - [x] 啟動通知橫幅（成功/警告/錯誤）

---

## 🔜 下一步（v4.4）

### P0 — 影響測試品質
- [ ] **Claude 動態關鍵字展開**（取代靜態對照表）
  - 問題送 Claude 快速 API call → 回傳 3-5 個展開搜尋詞
- [ ] **會前準備 Notion 自動同步**
  - Claude 讀取 Notion page → 自動產生 TXT → push GitHub
  - 參考 MeetingPrep-SKILL.md 工作流

### P1 — 影響 pilot 品質
- [ ] **Evidence-based Card Model**
  - AICard 加 `evidences: [SourceCitation]`
  - `inferenceType`: localMatch / ragPlusLLM / llmOnly
  - UI 顯示來源依據標示
- [ ] **Notion page tags 搜尋增強**
- [ ] **Structured Logging / Telemetry**
  - 三層命中率 + 延遲 histogram
  - Notion vs NotebookLM 命中比較

### P2 — 品質改善
- [ ] **會前準備 UI 改進**
  - 最近 TXT 檔案列表 + Q&A 從 Notion 自動匯入
- [ ] **Tests 整合到 Xcode Test Target**
- [ ] **SystemMonitor.reportLatency 整合到 ResponseOrchestrator**
- [ ] **UsageExample.swift 拆分**（目前 ~950 行）

---

## 🔮 未來版本

### v5.0 — 產品化
- [ ] Speaker Diarization（面對面會議）
- [ ] WhisperKit 離線語音辨識
- [ ] Action Item 自動擷取 → Notion/Calendar
- [ ] CRM 預載整合（Salesforce / HubSpot）

### v5.x — Enterprise
- [ ] 私有模型部署（BYOM）
- [ ] Azure OpenAI Private Endpoint
- [ ] 端到端加密 / SSO / 審計紀錄
- [ ] 資料保留政策

---

## 技術債

- [ ] `MeetingSessionStore.swift` 尚未完全整合到 Coordinator
- [ ] Tests 目錄未加入 Xcode Test target
- [ ] Notion 關鍵字展開用靜態表，應改 Claude 動態展開
- [ ] `UsageExample.swift` 過大（~950 行），應拆分為多個 View 檔案
- [ ] SystemMonitor.reportLatency 未接線到 ResponseOrchestrator
- [x] ~~SystemCheckView.swift 未加入 Xcode project target~~ (fixed 2026-03-11)
- [x] ~~KeychainManager.shared 不存在（enum 無 singleton）~~ (fixed 2026-03-11)
- [x] ~~TranscriptPipeline 所有錯誤顯示相同訊息~~ (fixed 2026-03-11)
- [x] ~~recentTranscript 雙串流模式永遠為空~~ (fixed 2026-03-11)

---

## Session 完成項目摘要

### 2026-03-11（v4.3.1）

| Commit | 內容 |
|--------|------|
| `d92e8db` | fix: KeychainManager.shared.retrieve → KeychainManager.load（修 3 build errors） |
| `9e4dcbb` | fix: SystemCheckView.swift 加入 Xcode project target（PBXBuildFile + PBXFileReference） |
| `6a886fd` | improve: TranscriptPipeline 錯誤訊息分類（describeError per AudioCaptureError type） |
| `6877c9f` | feat: transcript panel 即時 partial results 顯示（紫色波形 + 「正在聆聽...」） |
| `1243672` | fix: recentTranscript 雙串流空白 bug（直接用 segment text + partial in buildMerged） |
| `c5eb66b` | style: 說話者配色統一（對方=cyan 我方=yellow） |

### 2026-03-10（v4.3）

| Commit | 內容 |
|--------|------|
| `85aea06` | 會後儲存逐字稿 + AI 卡片 TXT |
| `b81f123` | 會前準備 語言選擇 Picker |
| `5152282` | 語言設定傳到 AudioCaptureConfiguration |
| `7c2083e` | NotionRetrievalService + KeychainManager + Orchestrator |
| `1df1408` | 設定 UI 加 Notion API Key |
| `2b4bfe7` | NotionRetrievalService 加入 Xcode build target |
| `06cb464` | 雙來源並行 RAG (async let) |
| `4d3b1b6` | Structured TranscriptEntry + TP detectedSpeech |
| `bbb19c8` | 雙串流分色 UI + TP 偵測標示 |
| `ba0162e` | SystemMonitor (CPU/Memory/Network) |
| `8bf50c4` | SYSTEM HEALTH 面板 UI |
| `891330f` | SystemMonitor 加入 Xcode build target (build 7) |
| `fd1da57` | Bundle ID → com.RealityMatrix.MeetingCopilot |

---

## 評分追蹤

| 維度 | v4.2 | v4.3 | v4.3.1 | 目標 |
|------|:----:|:----:|:------:|:----:|
| 產品概念 | 9/10 | 9/10 | 9/10 | 9/10 |
| 架構方向 | 8.5/10 | 9/10 | 9/10 | 9/10 |
| Demo 展示力 | 9/10 | 9.5/10 | **9.5/10** | 10/10 |
| 工程完整度 | 7/10 | 8.5/10 | **9/10** | 9/10 |
| 可維護性 | 7/10 | 8/10 | **8.5/10** | 9/10 |
| 生產可用性 | 5/10 | 7.5/10 | **8/10** | 8/10 |
| 企業落地潛力 | 7.5/10 | 8.5/10 | **8.5/10** | 9/10 |
| 安全治理 | 4.5/10 | 6/10 | **6.5/10** | 8/10 |
