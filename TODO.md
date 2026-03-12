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
- [x] MeetingApp.detectionPriority 屬性
- [x] 多 App 時彈出選擇面板（App Picker Sheet）
- [x] 單 App 自動啟動 / 0 App 顯示錯誤
- [x] AppScanner 靜態工具 + DetectedAppInfo 結構
- [x] AudioCaptureConfiguration.withTarget() 指定 App 啟動

### 麥克風引擎修復
- [x] 修復 MicrophoneCaptureEngine restartRecognition() 致命 bug
  - 舊 bug：restart 呼叫 start()，但 start() 有 guard !isActive → 直接 return → 語音辨識死亡
  - 修復：新增 restartSpeechOnly()，僅重啟 Speech Recognition，不動 audioEngine
- [x] Smart speech error handling（三種錯誤不同延遲）
  - "No speech detected"：等 5 秒再重啟（舊行為 0.3 秒造成快速循環）
  - 60 秒 timeout (code 216)：0.3 秒後快速重啟
  - 其他錯誤：1 秒後重啟 + 記錄錯誤碼
- [x] 同步修復 SystemAudioCaptureEngine 的 speech error handling
- [x] hasEverReceivedSpeech 標記 + 🎉 first speech log
- [x] 減少 log 噪音（前 5 次重啟記錄，之後每 10 次）

---

## 🔬 TranscriptOnly 實測結果（2026-03-11/12）

### App 相容性測試

| App | 對方音訊 (ScreenCaptureKit) | 我方音訊 (Mic) | 備註 |
|-----|:-------------------------:|:-------------:|------|
| YouTube (Chrome) | ✅ 正常辨識 | ✅ 引擎正常 | 中文新聞辨識成功，對方 105+ segments |
| Zoom | 🔲 待測試 | 🔲 待測試 | 主要使用場景 |
| Microsoft Teams | 🔲 待測試 | 🔲 待測試 | 主要使用場景 |
| Google Meet (Chrome) | ✅ 偵測+擷取成功 | ✅ 引擎正常 | Smart Detection 正確選擇 priority=1 |
| LINE Desktop | ❌ 不支援 | ❌ 受干擾 | HAL_ShellPlugIn 錯誤，音訊走虛擬裝置 |
| WhatsApp Desktop | 🔲 待測試 | 🔲 待測試 | 可能與 LINE 相同限制 |
| FaceTime | ✅ 偵測成功 | 🔲 待確認 | App 偵測 OK，priority=3 正確排序 |
| Telegram | 🔲 待測試 | 🔲 待測試 | |
| Discord | 🔲 待測試 | 🔲 待測試 | |

### LINE Desktop 已知問題

```
HALC_ShellPlugIn.cpp:915 — HAL_HardwarePlugIn_ObjectHasProperty: no object
HALPlugIn.cpp:458 — DeviceCreateIOProcID: Error 560947818 (!obj)
throwing -10877 (kAudioConverterErr_RequiresPacketDescriptionsError)
```

**根因：** LINE 桌面版的通話音訊走 macOS 虛擬音訊裝置（HAL plug-in），不是標準的視窗音訊輸出。ScreenCaptureKit 無法擷取此類音訊。這是 macOS Core Audio HAL 層級限制，非程式碼問題。

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

#### P2
- [ ] UsageExample.swift 拆分（~950 行）
- [ ] Tests 整合到 Xcode Test Target

### v4.5 — BlackHole 虛擬音訊整合（支援 LINE/WhatsApp 桌面版）

> **目的：** 解決 ScreenCaptureKit 無法擷取 LINE/WhatsApp 等走 HAL 虛擬音訊裝置的 App 問題
> **複雜度：低（~2 小時）** | **優先級：可選進階功能**

#### 使用者端一次性設定
1. 安裝 BlackHole：`brew install blackhole-2ch`
2. 開啟 macOS Audio MIDI Setup
3. 建立「Multi-Output Device」— 綁定 BlackHole + 喇叭/耳機
4. 系統音訊輸出設為 Multi-Output Device

#### 程式端改動

| 任務 | 檔案 | 難度 | 時間 |
|------|------|------|------|
| BlackHole 裝置偵測 | Sources/BlackHoleAudioEngine.swift（新增） | 低 | 30 min |
| AVAudioEngine 從 BlackHole 讀取音訊 | Sources/BlackHoleAudioEngine.swift | 低 | 30 min |
| Pipeline fallback 邏輯 | Sources/TranscriptPipeline.swift | 低 | 30 min |
| UI 音訊來源選項 | TranscriptOnly/TranscriptOnlyView.swift | 低 | 30 min |
| 使用者引導 + SystemCheck 偵測 | docs + SystemCheckSheet.swift | 低 | 30 min |

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
- [ ] Notion 關鍵字需改 Claude 動態展開

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
