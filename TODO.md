# MeetingCopilot 開發待辦與演進路線圖

> 最後更新: 2026-03-13 | v4.3.1 (build 8) | 19 Swift files

---

## 分支策略

| 分支 | 用途 | Xcode 專案 | Swift 檔案 | 狀態 |
|------|------|-----------|:---:|------|
| `main` | 完整版 AI 會議助手 | MeetingCopilot.xcodeproj | 19 | ✅ 穩定 |
| `feature/transcript-only` | 精簡版語音測試 | TranscriptOnly.xcodeproj | 7 | ✅ 測試 |
| `feature/speaker-prompter` | 個人演講提示版 | SpeakerPrompter.xcodeproj | 4 | 🆕 新建 |

---

## ✅ 已完成 (main)

### v4.3.1 核心更新
- [x] 13 App 支援 + Smart Detection + 瀏覽器會議偵測
- [x] On-Device 雙管道辨識 + AirPods 自動切換
- [x] PostMeetingLogger 診斷 Log（系統/連接/發言時間/AI使用量）
- [x] Teams Web on Edge/Chrome/Safari/Firefox 支援
- [x] Zoom 實測通過（英文會議）
- [x] Logger bug fixes（start_time + speaking_time）

### ★ SpeakerPrompter 新分支
- [x] `feature/speaker-prompter` 分支建立
- [x] SpeakerPrompter.xcodeproj 完整專案結構
- [x] 4 個 Swift 檔案 + Info.plist + Entitlements + Assets
- [x] Agenda 段落導航 + 計時器 + TP 追蹤
- [x] TXT 檔讀取 + Demo 範例
- [x] 鍵盤快捷鍵（→← Space R）

---

## 🔜 下一步

### main
- [ ] Teams 會議實測
- [ ] 30 分鐘穩定性測試
- [ ] v4.4: Claude 動態關鍵字 + Notion 同步

### speaker-prompter
- [ ] 全螢幕模式
- [ ] 演講結束統計報告（每段實際 vs 計畫時間）
- [ ] 音效提醒（段落切換 / 超時警告）
- [ ] App Store 提交準備

## 已建立的會議
| 會議 | Notion Page ID | NotebookLM ID |
|------|---------------|---------------|
| BiWeekly-Stanley-11Mar26 | 320f154a-6472-815c-8ad0-c214783dfe22 | ccaeee5e-8971-49e1-801d-2989ded2c61b |
| BiWeekly-Mark-JJ-12Mar26 | 320f154a-6472-813f-bc2c-d98e570ab696 | 51364658-5c30-4b55-8118-5103095ae8d0 |

Updated: 2026-03-13 | Reality Matrix Inc.
