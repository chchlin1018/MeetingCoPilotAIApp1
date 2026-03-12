# MeetingCopilot AI — 即時會議 AI 助手

> **MeetingCopilot** 是一款 macOS 原生 AI 會議助手，透過 ScreenCaptureKit 擷取會議音訊、Apple Speech 即時轉錄、Claude AI 智慧分析，提供即時提詞、關鍵字偵測與會後報告。

[![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-blue)]()
[![Swift](https://img.shields.io/badge/Swift-5.9-orange)]()
[![Version](https://img.shields.io/badge/version-v4.3.1-green)]()
[![Apps](https://img.shields.io/badge/supported%20apps-11-cyan)]()

---

## 分支策略

| 分支 | 用途 | Xcode 專案 | Swift 檔案 | 狀態 |
|------|------|-----------|-----------|------|
| `main` | 完整版（AI 管線 + UI） | MeetingCopilot.xcodeproj | 18 個 | ✅ 穩定 |
| `feature/transcript-only` | 精簡版（純語音辨識測試） | TranscriptOnly.xcodeproj | 7 個 | ✅ 測試中 |

---

## 支援的會議/通話 App（11 個）

| 類型 | App | Bundle ID | ScreenCaptureKit | 優先級 |
|------|-----|-----------|:---:|:---:|
| 會議 | Microsoft Teams | com.microsoft.teams2 | 待測試 | Tier 0 |
| 會議 | Zoom | us.zoom.xos | 待測試 | Tier 0 |
| 會議 | Google Meet (Chrome) | com.google.Chrome | ✅ 正常 | Tier 1 |
| 會議 | Webex | com.cisco.webexmeetingsapp | 待測試 | Tier 0 |
| 協作 | Slack | com.tinyspeck.slackmacgap | 待測試 | Tier 2 |
| 協作 | Discord | com.hnc.Discord | 待測試 | Tier 2 |
| 通訊 | LINE | jp.naver.line.mac | ❌ HAL 限制 | Tier 3 |
| 通訊 | WhatsApp | net.whatsapp.WhatsApp | 待測試 | Tier 3 |
| 通訊 | WhatsApp (Native) | WhatsApp | 待測試 | Tier 3 |
| 通訊 | Telegram | ru.keepcoder.Telegram | 待測試 | Tier 3 |
| 通訊 | FaceTime | com.apple.FaceTime | ✅ 偵測成功 | Tier 3 |

> **Smart Detection**：偵測到多個 App 時，依優先級排序，使用者手動選擇音訊來源。單一 App 則自動啟動。

---

## TranscriptOnly 快速開始

```bash
git clone https://github.com/chchlin1018/MeetingCoPilotAIApp1.git
cd MeetingCoPilotAIApp1
git checkout feature/transcript-only
open TranscriptOnly.xcodeproj
# ⌘R Build & Run
```

### 使用流程
1. 選擇語言（繁體中文/English/日本語等 5 種）
2. 按 🩺 按鈕執行系統檢查（7 項自動診斷）
3. 開啟 Zoom/Teams/Chrome 等會議
4. 按「開始會議」→ 偵測到多個 App 會彈出選擇面板
5. 對方語音 = cyan 文字，我方語音 = yellow 文字
6. 紫色斜體 = Live Partial Results（即時辨識中）
7. 按「停止」→ 匯出 TXT

### 檔案結構（7 個 Swift 檔案）

```
TranscriptOnly/
├── TranscriptOnlyApp.swift      # @main 進入點
├── TranscriptOnlyView.swift     # UI + ViewModel + App Picker
├── SystemCheckSheet.swift       # 7 項系統檢查
Sources/
├── AudioCaptureEngine.swift     # Protocol + MeetingApp enum + AppScanner
├── SystemAudioCaptureEngine.swift  # ScreenCaptureKit 擷取（對方）
├── MicrophoneCaptureEngine.swift   # AVAudioEngine 擷取（我方）
├── TranscriptPipeline.swift     # 雙串流合併 + Audio Health
```

### 系統檢查項目

| # | 檢查 | 說明 |
|---|------|------|
| 1 | 麥克風權限 | AVCaptureDevice |
| 2 | 語音辨識權限 | SFSpeechRecognizer |
| 3 | 螢幕錄製權限 | SCShareableContent |
| 4 | 麥克風音訊擷取 | AVAudioEngine 格式 |
| 5 | 語音辨識引擎 | 語言可用性 + 離線支援 |
| 6 | App 偵測 | 掃描 11 個支援 App |
| 7 | ScreenCaptureKit | SCStream 建立測試 |

---

## 技術架構

### 音訊管線
```
ScreenCaptureKit (48kHz) → Direct Append → Apple Speech → TranscriptSegment
                                                              ↓
AVAudioEngine (48kHz)   → installTap    → Apple Speech → TranscriptSegment
                                                              ↓
                                              TranscriptPipeline (合併)
                                                              ↓
                                              TranscriptUpdate → UI
```

### 音訊策略（三層容錯）
1. **Direct Append**：直接送 PCM buffer 給 Apple Speech（讓 Speech 處理 resampling）
2. **Dynamic Converter**：首個 buffer 動態偵測格式，建立對應的 AVAudioConverter
3. **Raw Append Fallback**：converter 失敗時直接送原始 buffer

### Speech Error Handling
| 錯誤 | 延遲 | 說明 |
|------|------|------|
| No speech detected | 5 秒 | 正常等待，不是錯誤 |
| 60s timeout (216) | 0.3 秒 | Apple Speech 正常超時 |
| 其他錯誤 | 1 秒 | 記錄錯誤碼後重啟 |

---

## 已知限制

- **LINE Desktop**：音訊走 HAL 虛擬裝置，ScreenCaptureKit 無法擷取（規劃 v4.5 BlackHole 整合）
- **WhatsApp Desktop**：可能有相同限制（待測試）
- **建議替代**：使用 Chrome 網頁版 LINE/WhatsApp 進行通話

---

## 版本路線圖

```
v4.3.1 (current) → TranscriptOnly 驗證
    → v4.4: AI 功能增強 (Claude 動態關鍵字 + Notion 同步)
    → v4.5: BlackHole 整合 (LINE/WhatsApp 支援)
    → v5.0: 產品化 (WhisperKit + Speaker Diarization)
```

---

## 開發環境

- macOS 14.0+ (Sonoma)
- Xcode 15.4+
- Swift 5.9 / Swift Strict Concurrency
- ScreenCaptureKit / AVFoundation / Speech

---

© 2026 Reality Matrix Inc. All rights reserved.
