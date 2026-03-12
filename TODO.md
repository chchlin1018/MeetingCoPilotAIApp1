# MeetingCopilot 開發待辦與演進路線圖

> 最後更新: 2026-03-12 | v4.3.1 (build 8)

---

## ✅ 已完成

### v4.3.1 核心更新
- [x] 11 App 支援 + Smart Detection + App Picker Sheet
- [x] On-Device 雙管道辨識（Mic=On-Device / Remote=Server）
- [x] Direct Append 音訊策略 + restartSpeechOnly() 修復
- [x] MeetingPrepView App Selection + MeetingAICoordinator 整合
- [x] [MIC-DEBUG] RMS 音量偵測 + 藍牙麥克風自動切換
- [x] AirPods Pro 衝突確認 + 自動切換內建麥克風

### ★ Zoom 會議實測結果（2026-03-12 ✅ 驗證通過）
- [x] Zoom App 偵測：Tier 0 最高優先級，App Picker 正確顯示
- [x] 對方英文語音辨識（en-US）✅ 正常辨識
- [x] 我方麥克風 On-Device 英文辨識 ✅ yellow 顯示
- [x] MacBook 內建麥克風自動偵測 OK
- [x] 10 Talking Points + 12 Q&A 載入成功
- [x] Notion RAG 可用
- [x] ❗ 需要授權螢幕錄製權限給 MeetingCopilot（否則 ScreenCaptureKit 無法擷取對方音訊）

### App 相容性

| App | 對方音訊 | 我方麥克風 | 狀態 |
|-----|:---:|:---:|------|
| **Zoom** | ✅ | ✅ On-Device | **已驗證** — 需授權螢幕錄製 |
| YouTube (Chrome) | ✅ | ✅ On-Device | 已驗證 |
| Google Meet (Chrome) | ✅ | ✅ On-Device | 已驗證 |
| Microsoft Teams | 🔲 | 🔲 | 待測試 |
| LINE Desktop | ❌ | ❌ | HAL 限制 |

### 麥克風相容性
| 裝置 | 支援 | 備註 |
|------|:---:|------|
| MacBook 內建麥克風 | ✅ | 推薦（程式自動偵測切換） |
| AirPods Pro 藍牙 | ❌ | 程式自動切換到內建麥克風 |
| 外接 USB 麥克風 | ✅ | 待測試 |

---

## ❗ 重要前置設定

### 螢幕錄製權限（必要）
ScreenCaptureKit 需要螢幕錄製權限才能擷取 Zoom/Teams/Meet 等會議 App 的對方音訊。

**設定方式：**
系統設定 → 隱私與安全性 → 螢幕與系統錄音 → 打開 **MeetingCopilot**

如果未授權，Console 會顯示：
```
⚠️ DualStream: SystemAudio failed — 使用者拒絕應用程式、視窗、顯示器擷取的TCC
```

---

## 🔜 下一步

- [ ] Teams 會議實測
- [ ] 30 分鐘穩定性測試
- [ ] v4.4: Claude 動態關鍵字 + Notion 同步
- [ ] v4.5: BlackHole 整合 (LINE/WhatsApp)

## ⚠️ 已知問題
- [ ] APIKeys.swift 需 `git rm --cached`
- [ ] AirPods Pro 藍牙麥克風不相容（已自動切換）
- [ ] LINE Desktop HAL 虛擬裝置限制

## 已建立的會議
| 會議 | Notion Page ID | NotebookLM ID |
|------|---------------|---------------|
| BiWeekly-Stanley-11Mar26 | 320f154a-6472-815c-8ad0-c214783dfe22 | ccaeee5e-8971-49e1-801d-2989ded2c61b |
| BiWeekly-Mark-JJ-12Mar26 | 320f154a-6472-813f-bc2c-d98e570ab696 | 51364658-5c30-4b55-8118-5103095ae8d0 |

Updated: 2026-03-12 | Reality Matrix Inc.
