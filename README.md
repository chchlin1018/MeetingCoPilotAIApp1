# MeetingCopilot AI

macOS 原生 AI 會議助手：ScreenCaptureKit 擷取會議音訊 + Apple Speech 即時轉錄 + Claude AI 智慧分析

## ❗ 首次使用前必讀

### 螢幕錄製權限（必要）
MeetingCopilot 需要螢幕錄製權限才能擷取 Zoom/Teams/Meet 等會議 App 的對方音訊。

**設定方式：系統設定 → 隱私與安全性 → 螢幕與系統錄音 → 打開 MeetingCopilot**

未授權時僅我方麥克風可用，對方音訊無法擷取。

## 技術架構

對方: ScreenCaptureKit → Apple Speech [SERVER] → cyan
我方: AVAudioEngine → Apple Speech [ON-DEVICE] → yellow

## 已驗證的會議 App

| App | 對方音訊 | 我方麥克風 | 狀態 |
|-----|:---:|:---:|------|
| **Zoom** | ✅ | ✅ | **已驗證**（英文會議） |
| YouTube (Chrome) | ✅ | ✅ | 已驗證 |
| Google Meet (Chrome) | ✅ | ✅ | 已驗證 |
| Teams | 🔲 | 🔲 | 待測試 |
| LINE Desktop | ❌ | ❌ | HAL 限制 |

## 麥克風相容性

| 裝置 | 支援 | 說明 |
|------|:---:|------|
| MacBook 內建麥克風 | ✅ | 推薦（程式自動偵測切換） |
| AirPods Pro 藍牙 | ❌ | 程式自動切換到內建麥克風，AirPods 耳機不受影響 |
| 外接 USB 麥克風 | ✅ | 應該正常 |

## 快速開始

1. git clone + open MeetingCopilot.xcodeproj
2. 填入 Sources/APIKeys.swift 的 Claude API Key
3. **系統設定 → 隱私與安全性 → 螢幕與系統錄音 → 打開 MeetingCopilot**
4. 系統設定 → 聲音 → 輸入 → 確認是 MacBook 內建麥克風
5. Cmd+R Build & Run
6. 按「準備會議」→ 填寫資訊 → 按「開始會議」

## 已知限制

- AirPods Pro 藍牙麥克風不相容（程式已自動處理）
- LINE Desktop 音訊走 HAL 虛擬裝置
- 首次使用需授權螢幕錄製權限

© 2026 Reality Matrix Inc.
