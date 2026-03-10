# MeetingCopilot 開發待辦與演進路線圖

> 最後更新: 2026-03-10 | 版本: v4.3.0 (build 6)

## ✅ 已完成

### v4.0 — 雙引擎即時管線
- [x] ScreenCaptureKit 系統音訊擷取
- [x] MicrophoneCaptureEngine 降級方案
- [x] Apple Speech 即時轉錄（Partial Results）
- [x] 本地 Q&A 關鍵字匹配（< 200ms）
- [x] Claude API Streaming 回應

### v4.1 — 三層管線 + TP 追蹤
- [x] NotebookLM 即時查詢（第二層 RAG）
- [x] NotebookLM Node.js Bridge（Mock + Puppeteer）
- [x] Talking Points 追蹤（MUST/SHOULD/NICE）
- [x] 時間壓力提醒（會議過半 MUST 未講）
- [x] SwiftUI 完整 Demo UI
- [x] Xcode Project 建立

### v4.2 — 工程化重構
- [x] God Object 拆分：Coordinator 650→280 行（-57%）
- [x] TranscriptPipeline actor（音訊 + 轉錄 + 問題偵測）
- [x] ResponseOrchestrator actor（三層管線 + 策略 + 卡片）
- [x] Provider Protocol 抽象介面（3 個）
- [x] DemoDataProvider 獨立化
- [x] API Key → macOS Keychain（KeychainManager）
- [x] 首次啟動 API Key 設定 UI

### v4.3 — 雙串流 + 個人測試可用
- [x] **雙串流說話者分離**（SystemAudio=對方 / Mic=我方）
- [x] .remote → 問題偵測 + 三層管線
- [x] .local → TP 追蹤（偵測「我講了什麼」）
- [x] 降級機制（雙引擎/單引擎/錯誤）
- [x] **會前準備 UI**（MeetingPrepView）
  - [x] 會議目標、參與者、Q&A、Talking Points 輸入
  - [x] 會議類型選擇
  - [x] 載入 Demo 資料
  - [x] TXT 檔案儲存/讀取（可用文字編輯器修改）
- [x] **語音辨識語言選擇**（zh-TW / en-US / en-GB / zh-CN / ja-JP）
- [x] **會後儲存**（逐字稿 + AI 卡片 + TP 狀態 + 統計 → TXT）
- [x] **Notion RAG 取代 NotebookLM**（NotionRetrievalService）
  - [x] Notion REST API 搜尋 + block content 擷取
  - [x] 多關鍵字展開（「成本」→ ["ROI", "投資", "payback"]）
  - [x] Notion 優先 → NotebookLM fallback → 跳過
  - [x] Notion API Key 存入 Keychain
  - [x] 設定 UI 加入 Notion API Key 欄位
- [x] SwiftData Persistence 模型（MeetingSessionRecord / TranscriptRecord / CardRecord）
- [x] XCTest 單元測試（4 組）
- [x] Header 顯示雙串流狀態 + 語言 badge

---

## 🔜 下一步（v4.4）

### P0 — 影響測試品質
- [ ] **Notion 多關鍵字展開：用 Claude 快速 API call**
  - 目前用靜態對照表，應改為 Claude 動態展開
  - 「AVEVA 定價策略」→ Claude 展開 → ["AVEVA", "pricing", "license", "定價", "年費"]
- [ ] **雙串流 UI 分色**
  - 逐字稿面板：[對方] 白色 / [我方] 灰色/青色 分色顯示
  - TP 追蹤標示「✅ 偵測到我方已講」

### P1 — 影響 pilot 品質
- [ ] **Evidence-based Card Model**
  - AICard 加 `evidences: [SourceCitation]`
  - `inferenceType: .localMatch / .ragPlusLLM / .llmOnly`
  - `isFactual: Bool`（原文事實 vs AI 推測）
  - UI 顯示來源依據標示
- [ ] **Notion page tags 搜尋增強**
  - 每個 Notion page 加 tags property
  - 搜尋時同時搜 title + tags + fullText
- [ ] **Structured Logging / Telemetry**
  - 三層管線命中率追蹤
  - 延遲 histogram
  - Notion vs NotebookLM 命中比較

### P2 — 品質改善
- [ ] **錯誤處理 UI**
  - ScreenCaptureKit 權限被拒 → 顯示授權提示
  - Speech Recognition 權限被拒 → 顯示授權提示
  - Notion API 失敗 → 顯示提示（不影響第一/三層）
- [ ] **會前準備 UI 改進**
  - 最近使用的 TXT 檔案列表
  - Q&A 從 Notion 自動匯入
  - TalkingPoints 從上次會議記錄延續

---

## 🔮 未來版本

### v5.0 — 產品化
- [ ] **Speaker Diarization**（面對面會議場景）
  - 雙串流解決 90%+ 遠端會議
  - 面對面需要 ML 模型（WhisperKit + speaker embedding）
- [ ] **WhisperKit 離線引擎**
  - 本地端語音辨識（不送雲端）
  - 動態降級：電量充足 → local Whisper / 低電量 → Apple Speech
- [ ] **資料流透明 UI**
  - 標示哪些資料送了 Claude、哪些留本地
  - consent / recording indicator
- [ ] **Action Item 自動擷取**
  - 從逐字稿偵測 action items
  - 會後自動整理成任務列表
- [ ] **CRM 預載整合**
  - 會前自動從 Salesforce / HubSpot 載入客戶歷史
  - 結合行事曆 API 自動預載

### v5.x — Enterprise
- [ ] 支援私有模型部署（BYOM via GenerativeResponseProvider）
- [ ] Azure OpenAI Private Endpoint 支援
- [ ] 端到端加密 / 閱後即焚
- [ ] 多租戶 / SSO / Policy
- [ ] 審計紀錄
- [ ] 資料保留政策 + 刪除機制

---

## 技術債

- [ ] `MeetingSessionStore.swift` 尚未完全整合到 Coordinator（模型存在，部分整合）
- [ ] Tests 目錄未加入 Xcode Test target（檔案存在但無法在 Xcode 跑）
- [ ] Bridge 安全加固未完成（CORS + token + log redact）
- [ ] Notion 關鍵字展開用靜態表，應改為 Claude 動態展開
- [ ] `UsageExample.swift` 過大（~800 行），應拆分為多個 View 檔案

---

## 評分追蹤（基於外部 Review）

| 維度 | 初始評分 | v4.2 後 | v4.3 後 | 目標 |
|------|:-------:|:------:|:------:|:----:|
| 產品概念 | 9/10 | 9/10 | 9/10 | 9/10 |
| 架構方向 | 8/10 | 8.5/10 | 9/10 | 9/10 |
| Demo 展示力 | 9/10 | 9/10 | **9.5/10** | 10/10 |
| 工程完整度 | 6/10 | 7/10 | **8/10** | 9/10 |
| 可維護性 | 5/10 | 7/10 | **8/10** | 9/10 |
| 生產可用性 | 4.5/10 | 5/10 | **7/10** | 8/10 |
| 企業落地潛力 | 7.5/10 | 7.5/10 | **8/10** | 9/10 |
| 安全治理 | 3/10 | 4.5/10 | **6/10** | 8/10 |
