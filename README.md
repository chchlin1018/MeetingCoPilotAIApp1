# MeetingCopilot AI

> 你的 AI 會議即時戰情室 — 讓每場會議都有備而來，每個回答都胸有成竹

MeetingCopilot 是一款 macOS 原生 AI 會議助手。它在你開會的同時，即時聽懂對方說的每一句話，自動比對你的會前準備資料，並在螢幕上即時顯示「你應該怎麼回答」。就像有一個經驗豐富的顧問坐在你旁邊，隨時遞小抄給你。

---

## 為什麼需要 MeetingCopilot？

開會時最常見的困境：對方突然問了一個你沒準備到的問題，你需要在 3 秒內給出專業的回答。或者會議結束後才想起：「唉，我忘記提那個重要的點了。」

MeetingCopilot 解決的就是這些問題：

- **對方問問題，AI 即時給你答案** — 不用再翻筆記、查資料，小抄直接出現在螢幕上
- **重要的話忘記說？AI 會提醒你** — Talking Points 追蹤器確保你不漏掉任何 MUST 重點
- **會議完自動產生報告** — AI 摘要 + Action Items + Notion 匯出，一鍵完成

---

## 產品特色

### 🎙️ 雙串流即時轉錄
同時擷取對方說的話和你說的話，分色顯示。對方是 cyan，你是 yellow。不會混在一起。

### 🧠 AI Teleprompter（即時提詞器）
對方問問題的瞬間，AI 就會在螢幕上顯示建議回答。它會參考你的會前準備 Q&A、Notion 筆記、以及 Claude AI 的即時分析。

### 🎯 Talking Points 追蹤
會前設定「MUST / SHOULD / NICE」三級重點。會議中自動偵測你是否已講過，確保不漏掉任何關鍵議題。

### 📊 會後自動診斷報告
每次會議結束自動產生完整的診斷 Log：系統狀態、發言時間比例、AI 使用量、連接狀態、錯誤記錄。讓你知道每場會議的完整效果。

### 🔒 完全本地運行
音訊不上傳雲端。語音辨識用 Apple Speech（支援 On-Device 離線模式），會議內容留在你的 Mac 上。

---

## 使用場景

### 💼 客戶簡報會議
客戶突然問到「你們跟競爭對手的差異在哪？」AI 立刻顯示你會前準備的競品分析資料，你可以從容回答。

### 🌏 跨國英文會議
和澳洲合作夥伴開 Zoom，對方說英文、你也用英文。雙方語音都即時轉錄，AI 用英文即時提供建議回答。

### 🧑‍💻 技術展示與 PoC 推進
跟半導體客戶討論 Digital Twin PoC，對方問技術細節、問預算、問時程，AI 都能即時提供對應的數據和建議回答。

### 🧑‍🤝 定期 Bi-Weekly 回顧
設定好 Talking Points，確保每個重點都講到。會後自動產生摘要和 Action Items，直接匯出到 Notion。

---

## 核心功能

| 功能 | 說明 |
|------|------|
| 雙串流語音辨識 | 對方（ScreenCaptureKit）+ 我方（麥克風 On-Device）同時運行 |
| AI 即時提詞 | 三層管線：本地關鍵字比對 → Notion/NotebookLM RAG → Claude AI |
| 會前準備 | Q&A 連結、Talking Points、語言選擇、App 自動偵測 |
| 會後報告 | AI 摘要 + Action Items + Notion 匯出 + 診斷 Log |
| 智慧 App 偵測 | 自動識別 Zoom/Teams/Meet 等 11 個 App |
| 藍牙麥克風防護 | 偵測到 AirPods 自動切換到內建麥克風 |
| 多語言支援 | 中文、英文、日文等（On-Device 離線可用） |

---

## 已驗證的會議 App

| App | 對方音訊 | 我方麥克風 | 狀態 |
|-----|:---:|:---:|------|
| **Zoom** | ✅ | ✅ | **已驗證**（英文會議） |
| **Google Meet** | ✅ | ✅ | **已驗證** |
| YouTube (Chrome) | ✅ | ✅ | 已驗證 |
| Teams | 🔲 | 🔲 | 待測試 |
| LINE Desktop | ❌ | ❌ | 規劃中 |

---

## 技術架構

```
對方說話 → ScreenCaptureKit → Apple Speech [Server] → cyan 文字
                                                      ↓
我方說話 → AVAudioEngine → Apple Speech [On-Device] → yellow 文字
                                                      ↓
                                          TranscriptPipeline 合併
                                                      ↓
                            ★ 本地 Q&A 比對 → Notion RAG → Claude AI
                                                      ↓
                                          AI Teleprompter 即時顯示
```

---

## 快速開始

### 系統需求
- macOS 14.0+
- Xcode 15.4+
- Claude API Key（Anthropic）

### 安裝步驟

1. **Clone 專案**
   ```bash
   git clone https://github.com/chchlin1018/MeetingCoPilotAIApp1.git
   cd MeetingCoPilotAIApp1
   open MeetingCopilot.xcodeproj
   ```

2. **設定 API Key**
   在 `Sources/APIKeys.swift` 填入你的 Claude API Key

3. **授權螢幕錄製（必要）**
   系統設定 → 隱私與安全性 → 螢幕與系統錄音 → 打開 **MeetingCopilot**

4. **確認麥克風**
   系統設定 → 聲音 → 輸入 → 選擇 MacBook 內建麥克風（程式會自動處理）

5. **Build & Run**
   `⌘R` → 19 個 Swift 檔案自動編譯

### 使用流程

```
準備會議 → 填寫 Q&A + Talking Points → 選擇語言
     ↓
系統檢查 → 確認麥克風、權限、API 連接
     ↓
開始會議 → 自動偵測 Zoom/Meet/Teams → 選擇音源
     ↓
會議中 → 即時轉錄 + AI 提詞 + TP 追蹤
     ↓
會議結束 → AI 摘要 + Action Items + Notion 匯出 + 診斷 Log
```

---

## 麥克風相容性

| 裝置 | 支援 | 說明 |
|------|:---:|------|
| MacBook 內建麥克風 | ✅ | 推薦（程式自動偵測切換） |
| AirPods Pro 藍牙 | ❌ | 程式自動切換到內建麥克風，AirPods 耳機不受影響 |
| 外接 USB 麥克風 | ✅ | 應該正常 |

---

## 會後診斷 Log

每次會議結束自動產生到 `MeetingTEXT/` 資料夾：

```
[STATUS]   ✅ ALL OK / ⚠️ WARNINGS / ❌ ISSUES
[MEETING]  標題、時長、語言、音源 App
[SYSTEM]   螢幕權限、麥克風裝置、藍牙偵測
[CONNECTIONS]  Claude / Notion / NotebookLM 連接狀態
[SPEAKING_TIME]  對方/我方發言比例
[AI_USAGE]  API 次數、cards、成本
```

---

## 版本路線圖

```
v4.3.1 (當前) → Zoom/Meet 已驗證
    → v4.4: Claude 動態關鍵字 + Notion 即時同步
    → v4.5: BlackHole 整合（LINE/WhatsApp 支援）
    → v5.0: WhisperKit + Speaker Diarization
```

---

## 已知限制

- AirPods Pro 藍牙麥克風與 ScreenCaptureKit 衝突（程式已自動處理）
- LINE Desktop 音訊走 HAL 虛擬裝置，規劃 v4.5 透過 BlackHole 解決
- 首次使用需授權螢幕錄製權限

---

© 2026 Reality Matrix Inc. All rights reserved.
