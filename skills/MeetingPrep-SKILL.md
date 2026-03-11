# MeetingCopilot 會議準備 Skill

## 概述

這是 Michael Lin（林志鋥）的會議準備工作流 Skill。用於在 Claude 新對話中快速建立會議準備資料，包括 Notion 頁面、TXT 檔案、Gmail Draft、NotebookLM 連接。

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

### Step 1：收集會議資訊

詢問使用者：
- 會議名稱和日期
- 參與者（姓名、職位、公司、關係）
- 會議類型（Review Meeting / Sales Proposal / Interview 等）
- 會議語言（zh-TW / en-US / 中英混雜）
- 相關文件（PDF / PPTX / Google Doc 連結）
- 相關郵件往來（搜尋 Gmail）
- 上次會議的進展摘要

### Step 2：建立 TXT 檔案（推送到 GitHub）

檔案路徑：`MeetingTEXT/YYYY-MM-DD_會議名稱.txt`

```
# MeetingCopilot 會前準備檔案

[MEETING]
title=會議名稱
type=Review Meeting
duration=60
language=zh-TW

[SOURCES]
notion_page_id=（建立後填入）
notion_page_url=
notebooklm_notebook_id=（建立後填入）
notebooklm_bridge_url=http://localhost:3210

[GOALS]
目標 1

[ATTENDEES]
人名 - 職位, 公司

[QA_MY_QUESTIONS]
# 我方主動提問，A 欄位填「提問目的」
Q: 問題
K: 關鍵字
A: 提問目的

[QA_THEIR_QUESTIONS]
# 對方可能提問，A 欄位填「建議回答」
Q: 問題
K: 關鍵字
A: 建議回答

[TP]
MUST|重點|支撐數據|關鍵字
SHOULD|重點|支撐數據|關鍵字
NICE|重點|支撐數據|關鍵字

[PREANALYSIS]
策略分析和進展摘要
```

### Step 3：建立 Notion 子頁面

Notion API 建立子頁面（用戶在 Terminal 執行）：

```bash
curl -s -X POST 'https://api.notion.com/v1/pages' \
  -H "Authorization: Bearer {NOTION_API_KEY}" \
  -H "Notion-Version: 2022-06-28" \
  -H "Content-Type: application/json" \
  -d '{"parent":{"page_id":"320f154a-6472-804f-a226-c3694c1bb319"},...}'
```

Notion Block 類型對照：
- Goals → `bulleted_list_item`
- 我方提問 → `to_do` (checked: false)
- 對方可能問 → `heading_3` + `paragraph`
- Talking Points → `to_do` with [MUST]/[SHOULD]/[NICE] tags
- Pre-Analysis → `paragraph`
- 分隔線 → `divider`
- 重要提示 → `callout` with emoji
- Email Draft → `quote`

追加內容到既有頁面：

```bash
curl -s -X PATCH 'https://api.notion.com/v1/blocks/{PAGE_ID}/children' \
  -H "Authorization: Bearer {NOTION_API_KEY}" \
  -H "Notion-Version: 2022-06-28" \
  -H "Content-Type: application/json" \
  -d '{"children":[...]}'
```

### Step 4：取得 Page ID 並更新 TXT

Notion API 回傳 JSON 中的 `id` 欄位就是 Page ID。
更新 TXT 的 `[SOURCES]`：`notion_page_id={PAGE_ID}`

### Step 5：建立 NotebookLM Notebook（使用者手動）

1. 到 https://notebooklm.google.com 建立新 Notebook
2. 上傳相關文件
3. 從 URL 取得 ID，更新 TXT

### Step 6：搜尋相關 Gmail 郵件

如有需要在會議中討論的郵件回覆：
1. 讀取完整 thread
2. 建立 Gmail Draft（可含 CC）
3. 將 Draft 內容加入 Notion 頁面（`quote` block）
4. 加入 Talking Points

### Step 7：同步到本地

```bash
cd ~/Documents/MyProjects/MeetingCopilotApp1 && git pull
```

---

## 已建立的會議範例

| 會議 | Notion Page ID | NotebookLM ID | TXT |
|------|----------------|---------------|-----|
| BiWeekly-Stanley-11Mar26 | `320f154a-6472-815c-8ad0-c214783dfe22` | `ccaeee5e-8971-49e1-801d-2989ded2c61b` | `2026-03-11_BiWeekly-Stanley.txt` |
| BiWeekly-Mark-JJ-12Mar26 | `320f154a-6472-813f-bc2c-d98e570ab696` | `51364658-5c30-4b55-8118-5103095ae8d0` | `2026-03-12_BiWeekly-Mark-JJ.txt` |

---

## Email Draft 策略

### Engagement / 顧問費用談判措辭
當對方未回應付費問題時，在 email 中使用暗示語言：
- **"structured support"** — 暗示非隨便幫忙
- **"scope of engagement"** — 暗示有合作框架
- **"allocate time and resources"** — 暗示有成本
- **不直接提錢** — 留給中間人推動

---

## Michael 的主要業務背景

### 主要進行中的案子
1. **MBI Utitech M&A** — TECO 併購 + 股權重組
2. **John & Jill's** — 澳洲蜂蜜品牌台灣市場進入
3. **Gamuda Silicon Island** — 馬來西亞半導體園區台灣連結
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
| Bred | Utitech CFO | 股權談判 |
| William | Utitech Chairman 24% | 股權談判 |

---

*Generated: 2026-03-11 | MeetingCopilot v4.3 | Reality Matrix Inc.*
