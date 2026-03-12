# MeetingCopilot 開發待辦與演進路線圖

> 最後更新: 2026-03-12 | v4.3.1 (build 8) | 19 Swift files

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
- [x] Zoom App 偵測：Tier 0 最高優先級
- [x] 對方英文語音辨識（en-US）✅ 正常辨識
- [x] 我方麥克風 On-Device 英文辨識 ✅ yellow 顯示
- [x] MacBook 內建麥克風自動偵測 OK
- [x] 10 Talking Points + 12 Q&A 載入成功
- [x] ❗ 需要授權螢幕錄製權限給 MeetingCopilot

### ★ Post-Meeting Diagnostic Logger
- [x] PostMeetingLogger.swift 新增（第 19 個 Swift 檔案）
- [x] 已加入 Xcode project.pbxproj Build Target（不需手動加入）
- [x] UsageExample.swift 加入 coordinator.setMeetingInfo()
- [x] 會議結束時自動產生 _LOG.txt 到 MeetingTEXT 資料夾

### ★ Logger Bug 修復（2026-03-12）
- [x] **Bug fix: start_time=N/A** — `stats = await orchestrator.stats` 覆蓋了 sessionStartTime → 用 `_sessionStartTime` 私有變數保存，stopMeeting 時還原
- [x] **Bug fix: speaking_time 全部為 0** — 只計算 isFinal entries，但 partial-only 時為 0 → Fallback 用 engine diagnosticInfo.segmentCount 估算（每 segment ≈ 20 字中文 / 30 字英文）

### Log 內容區段
| 區段 | 記錄內容 |
|------|----------|
| [STATUS] | ✅ ALL OK / ⚠️ WARNINGS / ❌ ISSUES |
| [MEETING] | 標題、時間、時長、語言、音源 App、雙串流、轉錄條數 |
| [SYSTEM] | 螢幕錄製 TCC、麥克風裝置、藍牙偵測 |
| [CONNECTIONS] | Claude API / Notion / NotebookLM 連接狀態 |
| [REMOTE_ENGINE] | 對方：segments、buffers、restarts、errors |
| [LOCAL_ENGINE] | 我方：segments、RMS、靜音%、On-Device 模式 |
| [SPEAKING_TIME] | 對方/我方發言分鐘、比例、靜音時間 |
| [AI_USAGE] | API 次數、cards、延遲、tokens、成本 USD |
| [TALKING_POINTS] | 完成率、MUST 完成率 |
| [ERROR_LOG] | 錯誤記錄 |
| [SUMMARY] | 人類可讀摘要 |

### App 相容性

| App | 對方音訊 | 我方麥克風 | 狀態 |
|-----|:---:|:---:|------|
| **Zoom** | ✅ | ✅ On-Device | **已驗證**（英文會議） |
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
系統設定 → 隱私與安全性 → 螢幕與系統錄音 → 打開 MeetingCopilot

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
