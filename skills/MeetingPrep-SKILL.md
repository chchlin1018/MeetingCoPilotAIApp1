# MeetingCopilot 會議準備 Skill

## 概述

Michael Lin（林志錚）的會議準備工作流 Skill。

**核心原則：Notion 是唯一的資料來源（Single Source of Truth）。TXT 只是 App 的載入格式，由 Claude 從 Notion 自動擷取產生。**

---

## 資料流架構

```
準備階段（Notion 為主戰場）：
  Michael 在 Notion 準備會議 → Goals / Q&A / TP / Email Draft / Pre-Analysis
  Claude 協助搜尋 Gmail、Google Doc、上傳文件 → 整合到 Notion
  使用者在 NotebookLM 上傳 PDF/PPTX → 取得 Notebook ID → 填入 Notion

開會前（Claude 自動產生 TXT）：
  Claude 讀取 Notion page 內容 → 轉換為 TXT 格式 → 推送到 GitHub
  使用者 git pull → App 讀取 TXT → 開始會議

會中：
  Layer 1: 本地 Q&A 匹配（來自 TXT）
  Layer 2: 雙來源並行 RAG（Notion page + NotebookLM notebook）
  Layer 3: Claude + merged context → AI 卡片

會後：
  AI 摘要 + Action Items → 匯出到 Notion 同一 page 的子頁面
```

---

## 核心資源連結

### GitHub Repository
- **Repo**: https://github.com/chchlin1018/MeetingCoPilotAIApp1
- **本地路徑**: `~/Documents/MyProjects/MeetingCopilotApp1/`
- **MeetingTEXT 資料夾**: `~/Documents/MyProjects/MeetingCopilotApp1/MeetingTEXT/`
- **Pull 指令**: `cd ~/Documents/MyProjects/MeetingCopilotApp1 && git pull`

### Notion
- **Workspace**: Michael's Notion
- **MeetingCopilot Parent Page ID**: `320f154a-6472-804f-a226-c3694c1bb319`
- **Integration 名稱**: MeetingCopilot
- **權限**: 讀取內容 ✅ / 插入內容 ✅ / 更新內容 ✅

### NotebookLM
- **Bridge URL**: `http://localhost:3210`（預設）
- **每場會議獨立 Notebook**，從 URL 取得 ID：`https://notebooklm.google.com/notebook/{NOTEBOOK_ID}`

### Gmail
- **Michael 的 Email**: chchlin1018@gmail.com

---

## 會議準備完整工作流

### Phase 1：收集資訊 → 建立 Notion 頁面

#### Step 1：收集會議資訊
詢問使用者：
- 會議名稱和日期
- 參與者（姓名、職位、公司、關係）
- 會議類型和語言
- 相關文件（PDF / PPTX / Google Doc 連結）
- 相關郵件往來（搜尋 Gmail）
- 上次會議的進展摘要

#### Step 2：建立 Notion 子頁面（所有資料都在這裡）
在 MeetingCopilot parent page 下建立子頁面，標題格式：`PreMeeting: 會議名稱 日期`

**Notion 頁面標準結構：**

```
PreMeeting: BiWeekly Stanley 11 Mar 2026
│
├── 🍯 Callout: 會議概述
│
├── Goals
│   • 目標 1
│   • 目標 2
│
├── 👥 Attendees
│   • 人名 - 職位, 公司
│
├── 🙋 我方想問的問題 (My Questions)
│   ☐ 問題 1（提問目的）
│   ☐ 問題 2（提問目的）
│
├── ❓ 對方可能問的問題 (Their Questions)
│   ### 問題標題
│   → 建議回答
│
├── 📋 Talking Points
│   ☐ [MUST] 重點 — 支撐數據
│   ☐ [SHOULD] 重點 — 支撐數據
│   ☐ [NICE] 重點 — 支撐數據
│
├── 📊 Pre-Analysis
│   策略分析文字
│
├── ─────────── (如有額外議題)
├── ★ 額外議題（如 Email 回覆討論）
│   📧 Callout: 郵件摘要
│   需確認的重點 (to_do)
│   Email Draft（quote block）
│
└── 附件
    • PDF/PPTX 清單
```

#### Step 3：搜尋 Gmail 並建立 Draft（如需要）
1. 搜尋相關郵件 thread
2. 建立 Gmail Draft（含 CC）
3. 將 Draft 內容加入 Notion 頁面（quote block + 確認 checkbox）
4. 加入 Talking Points

#### Step 4：使用者建立 NotebookLM Notebook（手動）
1. 到 https://notebooklm.google.com 建立新 Notebook
2. 上傳 PDF/PPTX 文件
3. 從 URL 取得 Notebook ID
4. 告訴 Claude ID，Claude 更新到 Notion 頁面

---

### Phase 2：開會前 → Claude 從 Notion 產生 TXT

**使用者說「幫我產生 TXT」或「我要開會了」時：**

#### Step 5：Claude 讀取 Notion 頁面
使用 Notion MCP 或 API 讀取頁面所有 blocks，擷取：
- [MEETING] 資訊
- [SOURCES] notion_page_id + notebooklm_notebook_id
- [GOALS] 從 bulleted_list_item
- [ATTENDEES] 從 Attendees 區塊
- [QA_MY_QUESTIONS] 從「我方想問」的 to_do blocks
- [QA_THEIR_QUESTIONS] 從「對方可能問」的 heading_3 + paragraph
- [TP] 從 Talking Points 的 to_do blocks（解析 [MUST]/[SHOULD]/[NICE] tag）
- [PREANALYSIS] 從 Pre-Analysis 的 paragraph

#### Step 6：產生 TXT 並推送到 GitHub

TXT 格式：

```
# MeetingCopilot 會前準備檔案

[MEETING]
title=會議名稱
type=Review Meeting
duration=60
language=zh-TW

[SOURCES]
notion_page_id=xxx
notion_page_url=xxx
notebooklm_notebook_id=xxx
notebooklm_bridge_url=http://localhost:3210

[GOALS]
目標 1
目標 2

[ATTENDEES]
人名 - 職位, 公司

[QA_MY_QUESTIONS]
Q: 問題
K: 關鍵字
A: 提問目的

[QA_THEIR_QUESTIONS]
Q: 問題
K: 關鍵字
A: 建議回答

[TP]
MUST|重點|支撐數據|關鍵字
SHOULD|重點|支撐數據|關鍵字
NICE|重點|支撐數據|關鍵字

[PREANALYSIS]
策略分析
```

推送到 GitHub：`MeetingTEXT/YYYY-MM-DD_會議名稱.txt`

#### Step 7：使用者載入 App
```bash
cd ~/Documents/MyProjects/MeetingCopilotApp1 && git pull
```
App → 讀取 → 選 TXT → 開始會議

---

## Notion API 參考

### 建立子頁面（POST）

```bash
curl -s -X POST 'https://api.notion.com/v1/pages' \
  -H "Authorization: Bearer {NOTION_API_KEY}" \
  -H "Notion-Version: 2022-06-28" \
  -H "Content-Type: application/json" \
  -d '{"parent":{"page_id":"320f154a-6472-804f-a226-c3694c1bb319"},...}'
```

### 追加內容（PATCH）

```bash
curl -s -X PATCH 'https://api.notion.com/v1/blocks/{PAGE_ID}/children' \
  -H "Authorization: Bearer {NOTION_API_KEY}" \
  -H "Notion-Version: 2022-06-28" \
  -H "Content-Type: application/json" \
  -d '{"children":[...]}'
```

### Block 類型對照
| 內容 | Block Type | 用途 |
|------|-----------|------|
| Goals | `bulleted_list_item` | 會議目標清單 |
| 我方提問 | `to_do` (checked: false) | 會議中可打勾 |
| 對方可能問 | `heading_3` + `paragraph` | 問題 + 回答 |
| Talking Points | `to_do` with [MUST] tag | 會議中可打勾 |
| Pre-Analysis | `paragraph` | 策略分析 |
| 分隔線 | `divider` | 區隔主題 |
| 重要提示 | `callout` with emoji | 醒目提示 |
| Email Draft | `quote` | 引用格式 |

---

## 已建立的會議

| 會議 | Notion Page ID | NotebookLM ID | TXT |
|------|----------------|---------------|-----|
| BiWeekly-Stanley-11Mar26 | `320f154a-6472-815c-8ad0-c214783dfe22` | `ccaeee5e-8971-49e1-801d-2989ded2c61b` | `2026-03-11_BiWeekly-Stanley.txt` |
| BiWeekly-Mark-JJ-12Mar26 | `320f154a-6472-813f-bc2c-d98e570ab696` | `51364658-5c30-4b55-8118-5103095ae8d0` | `2026-03-12_BiWeekly-Mark-JJ.txt` |

---

## Email Draft 策略

### Engagement / 顧問費用談判措辭
當對方未回應付費問題時，使用暗示語言：
- **"structured support"** — 暗示非隨便幫忙
- **"scope of engagement"** — 暗示有合作框架
- **"allocate time and resources"** — 暗示有成本
- **不直接提錢** — 留給中間人推動

---

## Michael 的業務背景

### 進行中的案子
1. **MBI Utitech M&A** — TECO 併購 + 股權重組（與 Stanley/iVP）
2. **John & Jill's** — 澳洲蜂蜜品牌台灣市場進入（與 Mark）
3. **Gamuda Silicon Island** — 馬來西亞半導體園區台灣連結（透過 Stanley → Lillian）
4. **YTEC** — 先進封裝設備 Penang 合作
5. **Johor DC** — 資料中心 + 水處理 + Digital Twin

### 關鍵聯絡人
| 姓名 | 公司/角色 | 關係 |
|------|----------|------|
| Stanley Chin | iVP/TCA Partner | 合作夥伴，BiWeekly |
| Mark | John & Jill's Founder | 合作夥伴，BiWeekly |
| Lillian Lung | Gamuda ED | 透過 Stanley 介紹 |
| Teresa | TECO 副董事長報告 | M&A 接洽 |
| Jason | TECO M&A Head | M&A 決策 |
| Bred | Utitech CFO 12% | 股權談判 |
| Sean | Utitech VP 6% | 股權談判 |
| William | Utitech Chairman 24% | 股權談判 |

---

## App 設定（一次性）

| 欄位 | 說明 |
|------|------|
| Claude API Key | 已存 Keychain |
| Notion API Key | MeetingCopilot Integration（ntn_...） |
| NotebookLM Notebook ID | 留空（每場會議在 TXT 設定） |
| NotebookLM Bridge URL | `http://localhost:3210` |

### 權限
- System Settings → Privacy & Security → Screen Recording → MeetingCopilot: 開啟

---

*Updated: 2026-03-11 | MeetingCopilot v4.3 | Reality Matrix Inc.*
