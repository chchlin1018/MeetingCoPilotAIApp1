# MeetingCopilot 開發待辦與演進路線圖

> 最後更新: 2026-03-12 | 版本: v4.3.1 (build 8) | Bundle: com.RealityMatrix.MeetingCopilot

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
- [x] TranscriptOnly.xcodeproj（獨立 Xcode 專案，7 Swift 檔案）
- [x] TranscriptOnlyView.swift（UI + ViewModel 直接接 Pipeline）
- [x] SystemCheckSheet.swift（7 項系統檢查：權限 + 功能診斷）
- [x] Build & Run 成功，推送到 GitHub

### 支援的 App（5 → 11 個）
- [x] 原有 5 個：Teams, Zoom, Google Meet, Webex, Slack
- [x] 新增 6 個：LINE, WhatsApp, WhatsApp (Native), Telegram, Discord, FaceTime
- [x] MeetingApp enum 更新（AudioCaptureEngine.swift）
- [x] 偵測到的 App 名稱顯示在 UI 狀態列（cyan badge）
- [x] 啟動訊息含 App 名稱（如「✅ 雙串流啟動成功：LINE（對方）+ 麥克風（我方）」）

### 動態音訊格式修復
- [x] 移除預設 48kHz 固定格式 audio converter（修復 -10877 錯誤）
- [x] 新增 Direct Append 策略（讓 Apple Speech 自行處理 resampling）
- [x] 動態格式偵測 + 三層容錯（direct → dynamic converter → raw append）
- [x] Debug logging（🔊 格式資訊 / ⚠️ 轉換錯誤 / 🔄 重啟）

### Smart App 偵測 + 手動選擇
- [x] 全掃描所有支援 App（不再第一個匹配就返回）
- [x] 活躍視窗檢查（>200x200 且 on screen）
- [x] 優先級排序：Tier 0 (Zoom/Teams) → Tier 1 (Meet) → Tier 2 (Slack) → Tier 3 (LINE/FaceTime)
- [x] 多 App 時彈出選擇面板（App Picker Sheet）
- [x] 單 App 自動啟動 / 0 App 顯示錯誤
- [x] AppScanner 靜態工具 + DetectedAppInfo 結構

### 麥克風引擎修復
- [x] 修復 restartRecognition() 致命 bug（restart 呼叫 start() → guard !isActive → return → 死亡）
- [x] 新增 restartSpeechOnly()，僅重啟 Speech Recognition，不動 audioEngine
- [x] Smart speech error handling（"No speech detected" 等 5 秒 / 60s timeout 0.3 秒 / 其他 1 秒）
- [x] 解決 0.3 秒快速重啟循環問題

### ★ On-Device 雙管道辨識（解決對方/我方互相取消）
- [x] **根因：** macOS Apple Speech 同時只允許一個 Server-based SFSpeechRecognitionTask
- [x] **現象：** 說話時對方辨識中斷（error [301]: Recognition request was canceled）
- [x] **修復：** 麥克風用 On-Device 離線辨識，遠端用 Server 線上辨識
- [x] 兩個不同的辨識管道（on-device vs server）可以共存
- [x] zh-TW / en-US / ja-JP 等 5 種語言皆支援 On-Device
- [x] restartSpeechOnly() 保持 on-device 模式
- [x] hasEverReceivedSpeech 標記 + 🎉 first speech log
- [x] 停止摘要含 onDevice flag（`Mic: stopped (buffers: 501, gotSpeech: true, onDevice: true)`）

---

## 🔬 TranscriptOnly 實測結果（2026-03-12）

### App 相容性測試

| App | 對方音訊 (ScreenCaptureKit) | 我方音訊 (Mic) | 備註 |
|-----|:-------------------------:|:-------------:|------|
| YouTube (Chrome) | ✅ 正常辨識 | ✅ On-Device 辨識 | 雙串流同時運作，不互相干擾 |
| Zoom | 🔲 待測試 | 🔲 待測試 | 主要使用場景 |
| Microsoft Teams | 🔲 待測試 | 🔲 待測試 | 主要使用場景 |
| Google Meet (Chrome) | ✅ 偵測+擷取成功 | ✅ On-Device 辨識 | Smart Detection 正確選擇 priority=1 |
| LINE Desktop | ❌ 不支援 | ❌ 受干擾 | HAL_ShellPlugIn 錯誤，音訊走虛擬裝置 |
| WhatsApp Desktop | 🔲 待測試 | 🔲 待測試 | 可能與 LINE 相同限制 |
| FaceTime | ✅ 偵測成功 | 🔲 待確認 | priority=3 正確排序 |
| Telegram | 🔲 待測試 | 🔲 待測試 | |
| Discord | 🔲 待測試 | 🔲 待測試 | |

### 雙管道辨識驗證結果

```
🎙️ Mic: on-device recognition = ✅ YES
🎙️ Mic: using ON-DEVICE recognition (避免與遠端 server 辨識衝突)
✅ Mic: audioEngine started, listening... (mode: on-device)
🎉 Remote: first speech recognized!
🎉 Mic: first speech recognized! (mode: on-device)
⏹️ Mic: stopped (buffers: 501, restarts: 5, gotSpeech: true, onDevice: true)
⏹️ Remote: stopped (buffers: 0, restarts: 5, gotSpeech: true)
```

### LINE Desktop 已知問題

**根因：** LINE 桌面版通話音訊走 macOS 虛擬音訊裝置（HAL plug-in），ScreenCaptureKit 無法擷取。
**解法：** 見下方 v4.5 BlackHole 整合方案。

### 系統檢查結果（7/7 通過）

| # | 檢查項目 | 結果 | 延遲 |
|---|---------|------|------|
| 1 | 麥克風權限 | ✅ 已授權 | 1,800ms |
| 2 | 語音辨識權限 | ✅ 已授權 | 1,349ms |
| 3 | 螢幕錄製權限 | ✅ 已授權 | 39ms |
| 4 | 麥克風音訊擷取 | ✅ 48000Hz/1ch | 194ms |
| 5 | 語音辨識引擎 (zh-TW) | ✅ 可用（支援離線）| 84ms |
| 6 | 會議/通話 App 偵測 | ✅ FaceTime, LINE | 8ms |
| 7 | ScreenCaptureKit 音訊 | ✅ 可擷取 | 8ms |

---

## 🔜 下一步

### 即時 — TranscriptOnly 驗證（優先）
- [ ] **Zoom 會議實測**（最重要場景）
- [ ] **Teams 會議實測**
- [ ] FaceTime 通話實測（對方音訊確認）
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

### v4.5 — BlackHole 虛擬音訊整合（支援 LINE/WhatsApp 桌面版）

> **複雜度：低（~2 小時）** | **優先級：可選進階功能**

#### Fallback 策略
```
1. 嘗試 ScreenCaptureKit 擷取目標 App
2. 成功 → 使用 ScreenCaptureKit（最佳品質）
3. 失敗 → 偵測 BlackHole 裝置
4. BlackHole 存在 → 自動切換 loopback 擷取
5. 不存在 → 提示使用者安裝或改用 Chrome 版
```

---

## ⚠️ 已知問題 / 技術債

### 安全（優先）
- [ ] APIKeys.swift 已 push 到 GitHub → 需 `git rm --cached`
- [ ] Claude/Notion Key 已曝光 → 需 rotate

### 音訊相容性
- [ ] LINE Desktop 音訊走 HAL 虛擬裝置 → ScreenCaptureKit 無法擷取
- [ ] WhatsApp Desktop 可能有相同限制（待測試確認）
- [ ] v4.5 BlackHole 整合可解決此問題

### 工程
- [ ] UsageExample.swift 過大（~950 行）
- [ ] Tests 未加入 Xcode Test target

---

## 🔮 未來版本

### v5.0 — 產品化
- [ ] Speaker Diarization（面對面會議）
- [ ] WhisperKit 離線語音辨識
- [ ] Action Item 自動擷取 → Notion/Calendar
- [ ] 進階音訊處理（噪音過濾、回音消除）

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

Updated: 2026-03-12 | MeetingCopilot v4.3.1 + TranscriptOnly v1.0 | 11 Supported Apps | Reality Matrix Inc.
