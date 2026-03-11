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
- [x] **雙來源並行 RAG**（NotebookLM + Notion 同時查詢）
- [x] **雙串流 UI 分色顯示**（TranscriptEntry + ScrollViewReader）
- [x] **TP 偵測標示**（✅ 偵測到我方已講 / 🔊 偵測中）
- [x] **系統健康監控**（SystemMonitor: CPU/Memory/Network）
- [x] **Bundle ID 更新** com.RealityMatrix.MeetingCopilot
- [x] SwiftData Persistence
- [x] XCTest 單元測試（4 組）

### v4.3.1 — SystemCheck + 即時體驗改善
- [x] **會前系統檢查**（SystemCheckView: 8 項自動檢測）
- [x] **KeychainManager API 修正**（enum 靜態方法，修 3 build errors）
- [x] **TranscriptPipeline 錯誤訊息分類**（describeError per AudioCaptureError type）
- [x] **即時 Partial Results 顯示**（紫色波形 + 正在聆聽）
- [x] **說話者配色統一**（對方=cyan / 我方=yellow）
- [x] **音訊健康監控 badge**（active/idle/disconnected + segment count）
- [x] **APIKeys.swift hardcoded fallback**（優先讀本地 key，Keychain 備援）
- [x] **AI Teleprompter 開場顯示第一個 MUST TP**（22pt 大字）
- [x] **字體放大**（逐字稿 16pt / AI 卡片 16pt / Partial 15pt）
- [x] **會後報告**（AI 摘要 + Action Items + Markdown/TXT/Notion 匯出）
- [x] **MeetingPrep Skill 文件**（skills/MeetingPrep-SKILL.md）
  - Notion SSOT 工作流 + TXT 格式定義 + Phase 1-2 完整流程
  - Notion parent page ID: 320f154a-6472-804f-a226-c3694c1bb319

### feature/transcript-only — 精簡語音辨識測試分支
- [x] **新建 TranscriptOnly.xcodeproj**（獨立 Xcode 專案）
- [x] **TranscriptOnlyApp.swift**（精簡 @main，無 API Key）
- [x] **TranscriptOnlyView.swift**（完整 UI + ViewModel）
  - 語言選擇（5 種）+ 開始/停止按鈕
  - 分色逐字稿（對方=cyan / 我方=yellow）
  - Live Partial Results（紫色即時文字）
  - Audio Health 監控（active/idle/disconnected + segment count）
  - 匯出逐字稿 TXT + 自動捲動
- [x] **直接接入現有 TranscriptPipeline**（不是 stub）
- [x] **Bundle ID**: com.RealityMatrix.TranscriptOnly
- [x] **只編譯 6 個 Swift 檔案**（vs main 的 18 個）
- [x] **推送到 GitHub** feature/transcript-only 分支

---

## 🔜 下一步

### 即時 — TranscriptOnly 測試驗證
- [ ] Zoom 會議實測：雙串流辨識正常
- [ ] Teams 會議實測：雙串流辨識正常
- [ ] 30 分鐘穩定性測試（不 crash）
- [ ] 中英文混合辨識測試
- [ ] 匯出 TXT 內容驗證

### v4.4 — AI 功能增強

#### P0 — 影響測試品質
- [ ] **Claude 動態關鍵字展開**（取代靜態對照表）
  - 問題送 Claude 快速 API call → 回傳 3-5 個展開搜尋詞
- [ ] **會前準備 Notion 自動同步**
  - Claude 讀取 Notion page → 自動產生 TXT → push GitHub
  - 參考 MeetingPrep-SKILL.md 工作流

#### P1 — 影響 pilot 品質
- [ ] **Evidence-based Card Model**
  - AICard 加 `evidences: [SourceCitation]`
  - `inferenceType`: localMatch / ragPlusLLM / llmOnly
  - UI 顯示來源依據標示
- [ ] **Notion page tags 搜尋增強**
- [ ] **Structured Logging / Telemetry**
  - 三層命中率 + 延遲 histogram
  - Notion vs NotebookLM 命中比較

#### P2 — 品質改善
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

## ⚠️ 已知問題 / 技術債

### 安全（優先處理）
- [ ] ⚠️ APIKeys.swift 已 push 到 GitHub（需 `git rm --cached Sources/APIKeys.swift`）
- [ ] ⚠️ Claude API Key 和 Notion Key 已在聊天中曝光 → 需 rotate

### 工程
- [ ] `UsageExample.swift` 過大（~950 行），應拆分為多個 View
- [ ] `MeetingSessionStore.swift` 尚未完全整合到 Coordinator
- [ ] Tests 目錄未加入 Xcode Test target
- [ ] Notion 關鍵字展開用靜態表，應改 Claude 動態展開
- [ ] SystemMonitor.reportLatency 未接線到 ResponseOrchestrator
- [x] ~~SystemCheckView.swift 未加入 Xcode project target~~ (fixed 2026-03-11)
- [x] ~~KeychainManager.shared 不存在（enum 無 singleton）~~ (fixed 2026-03-11)
- [x] ~~TranscriptPipeline 所有錯誤顯示相同訊息~~ (fixed 2026-03-11)
- [x] ~~recentTranscript 雙串流模式永遠為空~~ (fixed 2026-03-11)

---

## 已建立的會議

| 會議 | Notion Page ID | NotebookLM ID | TXT |
|------|---------------|---------------|-----|
| BiWeekly-Stanley-11Mar26 | 320f154a-6472-815c-8ad0-c214783dfe22 | ccaeee5e-8971-49e1-801d-2989ded2c61b | 2026-03-11_BiWeekly-Stanley.txt |
| BiWeekly-Mark-JJ-12Mar26 | 320f154a-6472-813f-bc2c-d98e570ab696 | 51364658-5c30-4b55-8118-5103095ae8d0 | 2026-03-12_BiWeekly-Mark-JJ.txt |

---

## Session 完成項目摘要

### 2026-03-11 晚間 — feature/transcript-only 分支

| 項目 | 內容 |
|------|------|
| 新分支 | `feature/transcript-only`（從 main 建立） |
| 新專案 | `TranscriptOnly.xcodeproj`（獨立 Xcode 專案） |
| 新檔案 | TranscriptOnlyApp.swift, TranscriptOnlyView.swift |
| 設定檔 | Info.plist, TranscriptOnly.entitlements, Assets.xcassets |
| 文件 | TranscriptOnly-README.md |
| 編譯 | 6 Swift 檔案（vs main 18 個） |
| 結果 | ✅ Build & Run 成功，UI 正常顯示 |

### 2026-03-11（v4.3.1）

| Commit | 內容 |
|--------|------|
| `d92e8db` | fix: KeychainManager.shared.retrieve → KeychainManager.load |
| `9e4dcbb` | fix: SystemCheckView.swift 加入 Xcode project target |
| `6a886fd` | improve: TranscriptPipeline 錯誤訊息分類 |
| `6877c9f` | feat: transcript panel 即時 partial results 顯示 |
| `1243672` | fix: recentTranscript 雙串流空白 bug |
| `c5eb66b` | style: 說話者配色統一（對方=cyan 我方=yellow） |
| 後續 | APIKeys.swift + Keychain fallback + 字體放大 + Teleprompter |
| 後續 | BiWeekly-Stanley TXT + MeetingPrep-SKILL.md |

### 2026-03-10（v4.3）

| Commit | 內容 |
|--------|------|
| 多次 | 雙串流 + 並行 RAG + 分色 UI + SystemMonitor + 會後儲存 |

---

## 評分追蹤

| 維度 | v4.2 | v4.3 | v4.3.1 | 目標 |
|------|:----:|:----:|:------:|:----:|
| 產品概念 | 9/10 | 9/10 | 9/10 | 9/10 |
| 架構方向 | 8.5/10 | 9/10 | 9/10 | 9/10 |
| Demo 展示力 | 9/10 | 9.5/10 | 9.5/10 | 10/10 |
| 工程完整度 | 7/10 | 8.5/10 | 9/10 | 9/10 |
| 可維護性 | 7/10 | 8/10 | 8.5/10 | 9/10 |
| 生產可用性 | 5/10 | 7.5/10 | 8/10 | 8/10 |
| 企業落地潛力 | 7.5/10 | 8.5/10 | 8.5/10 | 9/10 |
| 安全治理 | 4.5/10 | 6/10 | 6.5/10 | 8/10 |
