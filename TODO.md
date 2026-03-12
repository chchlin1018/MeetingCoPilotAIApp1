# MeetingCopilot 開發待辦與演進路線圖

> 最後更新: 2026-03-12 | 版本: v4.3.1 (build 8)

---

## ✅ 已完成

### v4.3.1 — 重大更新摘要
- [x] 11 App 支援 + Smart Detection + App Picker Sheet
- [x] On-Device 雙管道辨識（Mic=On-Device / Remote=Server）
- [x] Direct Append 音訊策略（修復 -10877）
- [x] restartSpeechOnly() 修復 + Smart error handling
- [x] MeetingPrepView App Selection（scanAndStart + Picker Sheet）
- [x] MeetingAICoordinator.scanAndPrepare() + startMeetingWithApp()
- [x] UsageExample header 顯示偵測 App 名稱
- [x] [MIC-DEBUG] RMS 音量偵測 + 完整診斷 log
- [x] AirPods Pro 藍牙麥克風衝突確認 + 解法記錄

### ★ AirPods Pro 藍牙麥克風問題
- [x] 根因：ScreenCaptureKit 同時運行時 macOS 切換 AirPods 到 SCO 模式
- [x] 現象：系統檢查第 5 項失敗，Mic segment count = 0
- [x] 解法：切換到 MacBook 內建麥克風 → 全部通過
- [x] 建議：AirPods 聽對方 + 內建麥克風收我方

### 麥克風相容性
| 裝置 | 支援 | 備註 |
|------|:---:|------|
| MacBook 內建麥克風 | ✅ | 推薦 |
| AirPods Pro 藍牙 | ❌ | SCO 模式衝突 |
| 外接 USB 麥克風 | ✅ | 待測試 |

---

## 🔜 下一步

- [ ] Zoom 會議實測
- [ ] Teams 會議實測
- [ ] 30 分鐘穩定性測試
- [ ] v4.4: Claude 動態關鍵字 + Notion 同步
- [ ] v4.5: BlackHole 整合 (LINE/WhatsApp)

## ⚠️ 已知問題
- [ ] APIKeys.swift 需 `git rm --cached`
- [ ] AirPods Pro 藍牙麥克風不相容
- [ ] LINE Desktop HAL 虛擬裝置限制

## 已建立的會議
| 會議 | Notion Page ID | NotebookLM ID |
|------|---------------|---------------|
| BiWeekly-Stanley-11Mar26 | 320f154a-6472-815c-8ad0-c214783dfe22 | ccaeee5e-8971-49e1-801d-2989ded2c61b |
| BiWeekly-Mark-JJ-12Mar26 | 320f154a-6472-813f-bc2c-d98e570ab696 | 51364658-5c30-4b55-8118-5103095ae8d0 |

Updated: 2026-03-12 | Reality Matrix Inc.
