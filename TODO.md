# MeetingCopilot 開發待辦與演進路線圖

> 最後更新：2026-03-10 | 版本：v4.3.0 build 4

---

## 已完成 ✅

### v4.0 — 雙引擎即時管線
- [x] ScreenCaptureKit 系統音訊擷取
- [x] Apple Speech 即時轉錄（Partial Results）
- [x] 雙引擎自動降級（System → Microphone）
- [x] 本地 Q&A 匹配（第一層）
- [x] Claude Streaming 即時生成（第三層）

### v4.1 — 三層管線 + TP 追蹤
- [x] NotebookLM 即時查詢（第二層）
- [x] Talking Points 追蹤（MUST / SHOULD / NICE）
- [x] NotebookLM Node.js Bridge（Mock + Puppeteer）
- [x] SwiftUI 完整 Demo UI
- [x] Xcode Project 建立

### v4.2 Week 1 — 架構拆分
- [x] God Object 拆分：Coordinator 650→280 行（-57%）
- [x] TranscriptPipeline actor（音訊 + 轉錄 + 問題偵測）
- [x] ResponseOrchestrator actor（三層管線 + 策略 + 卡片）
- [x] Provider Protocol 抽象介面（3 個）
- [x] DemoDataProvider 資料隔離
- [x] API Key → macOS Keychain（KeychainManager + 設定 UI）

### v4.3 — 雙串流 + 持久化 + 安全
- [x] 雙串流說話者分離（System Audio = 對方 / Mic = 我方）
- [x] SwiftData 會議記錄持久化（MeetingSessionRecord / TranscriptRecord / CardRecord）
- [x] Coordinator 整合 Persistence（startMeeting 建立 / stopMeeting 存入 / 即時存轉錄+卡片）
- [x] Bridge 安全加固（CORS localhost / shared secret / log redaction）
- [x] XCTest 單元測試（4 組：KeywordMatcher / TP / QuestionDetector / Orchestrator）
- [x] MeetingSessionStore.swift 加入 Xcode build target

---

## 進行中 / 待確認 🟡

### Xcode Test Target
- [ ] 在 Xcode 中手動建立 MeetingCopilotTests target
  - File → New → Target → Unit Testing Bundle
  - 將 Tests/*.swift 加入 test target
  - 確認 Host Application 設為 MeetingCopilot
  - ⌘+U 執行測試

### AICard.type.rawValue 相容性
- [ ] 確認 AICard.AICardType 已實作 RawRepresentable (String)
  - CardRecord 儲存時使用 card.type.rawValue
  - 如果 enum 沒有 rawValue 會 build error

---

## 下一步 P0 🔴

### Evidence-based Card Model
- [ ] AICard 升級：新增 `evidences: [SourceCitation]`
- [ ] 新增 `inferenceType` enum（.localMatch / .ragPlusLLM / .llmOnly）
- [ ] 新增 `isFactual: Bool`（原文事實 vs AI 推測）
- [ ] 紫色卡片 UI 顯示「來源依據」標示
- [ ] 卡片 pin / dismiss 狀態

### Bridge 降級為 Optional Adapter
- [ ] 實作 `LocalEmbeddingProvider`（用 NaturalLanguage.framework）
- [ ] `KnowledgeRetrievalProvider` 可替換機制
  - NotebookLMAdapter（現有，optional）
  - LocalEmbeddingProvider（新，零依賴）
  - PineconeProvider（未來企業版）
- [ ] 沒有 Bridge 時系統仍可運作（跳過第二層）

### 雙串流 UI 升級
- [ ] 逐字稿面板：[對方] 白色 / [我方] 灰色 分色顯示
- [ ] Header 顯示「雙串流 ✅」或「單串流 ⚠️」
- [ ] TP 追蹤標示「✅ 偵測到我方已講」

---

## P1 — 一個版本內 🟡

### 會後回看
- [ ] Session History 頁面（列出所有歷史會議）
- [ ] Session Detail 頁面（逐字稿 + 卡片 + TP 完成率 + 統計）
- [ ] Transcript replay（時間軸播放）

### Structured Logging / Telemetry
- [ ] 三層管線命中率 histogram
- [ ] 雙串流 remote/local 分佈比例
- [ ] 每 session Claude 花費追蹤
- [ ] 延遲 P50/P90/P99

### 資料流透明 UI
- [ ] 標示哪些資料送了 Claude、哪些留本地
- [ ] 會議開始時顯示 consent / recording indicator
- [ ] Session 結束即清空暫存（可選）

### 動態降級機制
- [ ] 電量/算力充足 → Local Whisper
- [ ] 低耗電模式 → Cloud STT API
- [ ] 自動偵測並切換

---

## P2 — 產品化前 🔵

### Speaker Diarization（面對面場景）
- [ ] 雙串流已解決 90%+ 線上會議場景
- [ ] 面對面會議需要 ML 模型（WhisperKit + speaker embedding）
- [ ] 評估端側算力消耗對筆電續航/發熱的影響

### Action Item 自動擷取
- [ ] 從逐字稿中擷取待辦事項
- [ ] 與 CRM / 行事曆整合
- [ ] Follow-up draft 自動產生

### WhisperKit 離線引擎
- [ ] 替換 Apple Speech 作為 TranscriptProvider
- [ ] 支援中英夾雜（Code-switching）
- [ ] 開發動態降級機制

### Enterprise 安全治理
- [ ] 音訊是否離開本機（答：逐字稿送 Claude，音訊不送）
- [ ] 資料保留策略 + 刪除機制
- [ ] 支援私有模型部署（BYOM via GenerativeResponseProvider）
- [ ] Multi-tenant / SSO / Policy controls
- [ ] 稽核紀錄（Audit trail）

### CRM 預載整合
- [ ] 會前自動載入客戶歷史痛點
- [ ] 行事曆 API 整合
- [ ] Salesforce / HubSpot connector

---

## 技術債與知道的問題

### 架構債
- [ ] NotebookLM Puppeteer bridge 極脆弱，依賴 DOM selector
- [ ] 第三方頁面任何變動都會導致 bridge 崩潰
- [ ] 應盡速移轉至 Vector DB（Pinecone / Qdrant）

### Swift Concurrency Warnings
- [ ] 11 個黃色 warnings（Sendable / actor isolation）
- [ ] 大多是 Apple SDK 適配問題，非自己的 code
- [ ] Swift 6 準備期可逐步清理

### 測試體系
- [ ] Tests/ 目錄有 4 個測試檔，但需在 Xcode 建立 Test target 才能執行
- [ ] 缺少 integration test（完整管線端到端）
- [ ] 缺少 prompt regression test
- [ ] 缺少 UI snapshot test

---

## 專業評分追蹤

| 維度 | v4.2 初 | v4.3 現在 | 目標 |
|------|:------:|:--------:|:----:|
| 產品概念 | 9/10 | 9/10 | 9+ |
| 架構方向 | 8/10 | 8.5/10 | 9 |
| Demo 展示力 | 9/10 | 9/10 | 9.5 |
| 工程完整度 | 6/10 | **8/10** | 8.5 |
| 可維護性 | 5/10 | **8/10** | 8.5 |
| 生產可用性 | 4.5/10 | **6.5/10** | 7.5 |
| 企業落地潛力 | 7.5/10 | 8/10 | 8.5 |
| 安全治理 | 3/10 | **6/10** | 7 |

---

## 檔案統計

| 類別 | 數量 |
|------|------|
| Swift 原始碼 | 14 個 |
| 測試檔案 | 4 個 |
| Node.js Bridge | 5 個 |
| Xcode Project | 1 個 |
| 總計 | 24+ 個 |
