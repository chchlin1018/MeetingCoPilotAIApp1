# TranscriptOnly — 雙串流即時語音辨識測試

> `feature/transcript-only` 分支：純語音辨識，無 AI 層

## Quick Start

```bash
# 切換分支 + 拉取
git fetch origin
git checkout feature/transcript-only

# 開啟專案
open TranscriptOnly.xcodeproj

# Signing → 選 Development Team → ⌘R Build & Run
# 開 Zoom/Teams → 按「開始會議」
```

## 編譯的檔案（6 個 Swift）

| 檔案 | 來源 | 用途 |
|------|------|------|
| TranscriptOnlyApp.swift | TranscriptOnly/ | @main 入口 |
| TranscriptOnlyView.swift | TranscriptOnly/ | UI + ViewModel |
| AudioCaptureEngine.swift | Sources/ | Protocol + 型別 |
| SystemAudioCaptureEngine.swift | Sources/ | ScreenCaptureKit → 對方 |
| MicrophoneCaptureEngine.swift | Sources/ | AVAudioEngine → 我方 |
| TranscriptPipeline.swift | Sources/ | 雙串流 + Audio Health |

## 功能

- ✅ ScreenCaptureKit 擷取對方聲音 → `.remote`
- ✅ AVAudioEngine 擷取我方聲音 → `.local`
- ✅ 分色顯示（對方=cyan / 我方=yellow）
- ✅ Live Partial Results（紫色即時文字）
- ✅ Audio Health 監控（active/idle/disconnected）
- ✅ 5 種語言（zh-TW, en-US, en-GB, zh-CN, ja-JP）
- ✅ 匯出逐字稿 TXT
- ❌ 無 AI 層（Claude / NotebookLM / Notion）
- ❌ 無 API Keys 需求

## 權限

- System Settings → Privacy & Security → Screen & System Audio Recording → TranscriptOnly: 開啟
- 每次 Xcode rebuild 後可能需重新授權：`tccutil reset ScreenCapture com.RealityMatrix.TranscriptOnly`

Bundle ID: `com.RealityMatrix.TranscriptOnly`
