# MeetingCopilot 開發待辦與演進路線圖

> 最後更新: 2026-03-11 | 版本: v4.3.1 (build 8) | Bundle: com.RealityMatrix.MeetingCopilot

---

## ✅ 已完成

### v4.0–v4.2 — 基礎架構
- [x] ScreenCaptureKit + MicrophoneCaptureEngine 雙引擎
- [x] Apple Speech 即時轉錄 + Claude API Streaming
- [x] 三層管線 + NotebookLM Bridge + TP 追蹤
- [x] 工程化重構（Coordinator -57% + Keychain + Provider Protocol）

### v4.3 — 雙串流 + 個人測試可用
- [x] 雙串流說話者分離（SystemAudio=對方 / Mic=我方）
- [x] 雙來源並行 RAG（NotebookLM + Notion async let）
- [x] 會前準備 UI + 語言選擇 + 會後儲存
- [x] 雙串流 UI 分色 + TP 偵測標示
- [x] SystemMonitor + SwiftData + XCTest

### v4.3.1 — SystemCheck + 即時體驗改善
- [x] 會前系統檢查（SystemCheckView: 8 項）
- [x] Live Partial Results + 說話者配色（cyan/yellow）
- [x] 音訊健康監控 badge + AI Teleprompter
- [x] APIKeys.swift fallback + 字體放大
- [x] 會後報告（AI 摘要 + Action Items + Notion 匯出）
- [x] MeetingPrep Skill 文件

### feature/transcript-only — 精簡語音辨識測試分支
- [x] TranscriptOnly.xcodeproj（獨立 Xcode 專案，6 Swift 檔案）
- [x] TranscriptOnlyView.swift（UI + ViewModel 直接接 Pipeline）
- [x] Build & Run 成功，推送到 GitHub

### 支援的 App（5 → 11 個）
- [x] 原有 5 個：Teams, Zoom, Google Meet, Webex, Slack
- [x] **新增 6 個**：LINE, WhatsApp, WhatsApp (Native), Telegram, Discord, FaceTime
- [x] MeetingApp enum 更新（AudioCaptureEngine.swift）
- [x] 錯誤訊息更新：含 LINE/WhatsApp 提示

---

## 🔜 下一步

### 即時 — TranscriptOnly 實測驗證
- [ ] LINE 通話實測：雙串流辨識正常
- [ ] WhatsApp 通話實測：雙串流辨識正常
- [ ] Zoom 會議實測
- [ ] Teams 會議實測
- [ ] FaceTime 通話實測
- [ ] 30 分鐘穩定性測試（不 crash）
- [ ] 中英文混合辨識測試
- [ ] 匯出 TXT 內容驗證

### v4.4 — AI 功能增強

#### P0
- [ ] Claude 動態關鍵字展開（取代靜態對照表）
- [ ] 會前準備 Notion 自動同步（Claude 讀 Notion → TXT → push GitHub）

#### P1
- [ ] Evidence-based Card Model（evidences + inferenceType）
- [ ] Structured Logging / Telemetry

#### P2
- [ ] UsageExample.swift 拆分（~950 行）
- [ ] Tests 整合到 Xcode Test Target

---

## ⚠️ 已知問題 / 技術債

### 安全（優先）
- [ ] APIKeys.swift 已 push 到 GitHub → 需 `git rm --cached`
- [ ] Claude/Notion Key 已曝光 → 需 rotate

### 工程
- [ ] UsageExample.swift 過大（~950 行）
- [ ] Tests 未加入 Xcode Test target
- [ ] Notion 關鍵字需改 Claude 動態展開

---

## 🔮 未來版本

### v5.0 — 產品化
- [ ] Speaker Diarization（面對面會議）
- [ ] WhisperKit 離線語音辨識
- [ ] Action Item 自動擷取 → Notion/Calendar

### v5.x — Enterprise
- [ ] 私有模型部署 / Azure OpenAI
- [ ] 端到端加密 / SSO / 審計紀錄

---

## 已建立的會議

| 會議 | Notion Page ID | NotebookLM ID | TXT |
|------|---------------|---------------|-----|
| BiWeekly-Stanley-11Mar26 | 320f154a-6472-815c-8ad0-c214783dfe22 | ccaeee5e-8971-49e1-801d-2989ded2c61b | 2026-03-11_BiWeekly-Stanley.txt |
| BiWeekly-Mark-JJ-12Mar26 | 320f154a-6472-813f-bc2c-d98e570ab696 | 51364658-5c30-4b55-8118-5103095ae8d0 | 2026-03-12_BiWeekly-Mark-JJ.txt |

---

Updated: 2026-03-11 | MeetingCopilot v4.3.1 + TranscriptOnly v1.0 | Reality Matrix Inc.
