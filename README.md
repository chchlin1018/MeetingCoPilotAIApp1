# MeetingCopilot AI

macOS 原生 AI 會議助手：ScreenCaptureKit 擷取會議音訊 + Apple Speech 即時轉錄 + Claude AI 智慧分析

## 技術架構

對方: ScreenCaptureKit → Apple Speech [SERVER] → cyan
我方: AVAudioEngine → Apple Speech [ON-DEVICE] → yellow

## App Selection

按「開始會議」→ 掃描 11 個 App → 自動或手動選擇音訊來源

支援: Teams, Zoom, Webex, Google Meet, Slack, Discord, LINE, WhatsApp, Telegram, FaceTime

## 麥克風相容性

| 裝置 | 支援 | 說明 |
|------|:---:|------|
| MacBook 內建麥克風 | ✅ | 推薦用於開會 |
| AirPods Pro 藍牙 | ❌ | ScreenCaptureKit 衝突（SCO 模式） |
| 外接 USB 麥克風 | ✅ | 應該正常 |

建議: AirPods 聽對方 + MacBook 內建麥克風收我方

## 快速開始

git clone + open MeetingCopilot.xcodeproj + 填 APIKeys.swift + Cmd+R

## 已知限制

- AirPods Pro 藍牙麥克風不相容
- LINE Desktop 音訊走 HAL 虛擬裝置

© 2026 Reality Matrix Inc.
