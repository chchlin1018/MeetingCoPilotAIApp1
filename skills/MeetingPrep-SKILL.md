MeetingCopilot 會議準備 Skill
概述
Michael Lin（林志錜）的會議準備工作流 Skill。
核心原則：Notion 是唯一的資料來源（Single Source of Truth）。TXT 只是 App 的載入格式，由 Claude 從 Notion 自動擷取產生。

★ App 開發現況（v4.3.1 — 2026-03-11）

分支策略：
│ 分支                        │ 用途                              │ Xcode 專案                  │
│ main                        │ 完整版（18 Swift + AI 全管線）    │ MeetingCopilot.xcodeproj    │
│ feature/transcript-only     │ 精簡版（6 Swift，純語音辨識）    │ TranscriptOnly.xcodeproj    │

main 分支架構：18 個 Swift 檔案 + 4 測試
Sources/
├── AudioCaptureEngine.swift         # Protocol + 共用型別
├── SystemAudioCaptureEngine.swift   # ScreenCaptureKit → remote（對方）
├── MicrophoneCaptureEngine.swift    # AVAudioEngine → local（我方）
├── KeywordMatcherAndClaude.swift    # 第一層 Q&A + Claude API
├── NotebookLMService.swift          # 第二層 NotebookLM RAG
├── NotionRetrievalService.swift     # 第二層 Notion RAG
├── TalkingPointsTracker.swift       # TP 追蹤 + detectedSpeech
├── ProviderProtocols.swift          # 3 個抽象介面
├── TranscriptPipeline.swift         # 雙串流 + Live Partial + Audio Health
├── ResponseOrchestrator.swift       # 雙來源並行 RAG + Claude
├── MeetingAICoordinator.swift       # 瘦身 Coordinator + SwiftData
├── KeychainManager.swift            # Keychain + APIKeys.swift fallback
├── MeetingSessionStore.swift        # SwiftData persistence
├── SystemMonitor.swift              # CPU / Memory / Network
├── SystemCheckView.swift            # ★ 會前 8 項系統診斷
├── PostMeetingReportService.swift   # AI 摘要 + Action Items + Notion 匯出
├── MeetingPrepView.swift            # 會前準備 UI + TXT + 語言選擇
├── DemoDataProvider.swift           # Demo 資料
└── UsageExample.swift               # 主畫面 + 分色逐字稿 + 會後儲存

feature/transcript-only 分支架構：6 個 Swift 檔案
TranscriptOnly/
├── TranscriptOnlyApp.swift          # @main（無 API Key）
└── TranscriptOnlyView.swift         # UI + ViewModel（直接接 Pipeline）
Sources/（共用）
├── AudioCaptureEngine.swift         # Protocol + 型別
├── SystemAudioCaptureEngine.swift   # ScreenCaptureKit → 對方
├── MicrophoneCaptureEngine.swift    # AVAudioEngine → 我方
└── TranscriptPipeline.swift         # 雙串流 + Audio Health

已完成功能

✅ 雙串流說話者分離（ScreenCaptureKit=對方 / Mic=我方）
✅ 三層即時管線（本地Q&A < 200ms → 雙來源RAG 1-3s → Claude 2-4s）
✅ 雙來源並行 RAG（NotebookLM + Notion async let 同時查詢）
✅ Talking Points 追蹤（MUST/SHOULD/NICE + detectedSpeech）
✅ 會前系統檢查（SystemCheckView：8項自動檢測）
✅ Live Partial Results（即時顯示未 final 的語音辨識文字）
✅ 說話者分色：對方=青色(cyan) / 我方=黃色(yellow)
✅ 音訊健康監控 badge（active/idle/disconnected + segment count）
✅ APIKeys.swift hardcoded fallback（優先讀本地 key，Keychain 為備援）
✅ AI Teleprompter 開場顯示第一個 MUST TP（22pt 大字）
✅ 字體放大：逐字稿 16pt / AI 卡片 16pt / Partial 15pt
✅ 會後報告：AI 摘要 + Action Items + Markdown/TXT/Notion 匯出
✅ SwiftData 持久化 + macOS Keychain 安全儲存
✅ TranscriptOnly 精簡分支（Build & Run 成功，待實測）
✅ MeetingPrep Skill 文件（本檔案）

已知問題 / 待修

⚠️ APIKeys.swift 已 push 到 GitHub（需執行 git rm --cached Sources/APIKeys.swift）
⚠️ Claude API Key 和 Notion Key 已在聊天中曝光 → 需 rotate
⚠️ 會議中 transcript 未顯示：已修復（recentTranscript + partial），但 Michael 開會時用的是舊 code，需重新 git pull + build
⚠️ UsageExample.swift 過大（~950 行），應拆分
⚠️ Tests 目錄未加入 Xcode Test target

下一步開發

即時：TranscriptOnly 實測驗證
☐ Zoom 會議實測：雙串流辨識正常
☐ Teams 會議實測：雙串流辨識正常
☐ 30 分鐘穩定性測試（不 crash）
☐ 中英文混合辨識測試

後續（v4.4）
☐ Claude 動態關鍵字展開（取代靜態對照表）
☐ Evidence-based Card（AICard 加 evidences + inferenceType）
☐ 會前準備 Notion 自動同步（Claude 讀 Notion → 產生 TXT → push GitHub）
☐ Structured Logging / Telemetry
☐ UsageExample.swift 拆分


資料流架構
準備階段（Notion 為主戰場）：
  Michael 在 Notion 準備會議 → Goals / Q&A / TP / Email Draft / Pre-Analysis
  Claude 協助搜尋 Gmail、Google Doc、上傳文件 → 整合到 Notion
  使用者在 NotebookLM 上傳 PDF/PPTX → 取得 Notebook ID → 填入 Notion

開會前（Claude 自動產生 TXT）：
  Claude 讀取 Notion page 內容 → 轉換為 TXT 格式 → 推送到 GitHub
  使用者 git pull → App 讀取 TXT → System Check → 開始會議

會中：
  Layer 1: 本地 Q&A 匹配（來自 TXT）
  Layer 2: 雙來源並行 RAG（Notion page + NotebookLM notebook）
  Layer 3: Claude + merged context → AI 卡片
  ★ Live Partial: 即時顯示辨識中文字（紫色波形）
  ★ Teleprompter: 開場顯示第一個 MUST TP + 待講清單

會後：
  AI 摘要 + Action Items → Markdown/TXT/Notion 匯出

核心資源連結
GitHub Repository

Repo: https://github.com/chchlin1018/MeetingCoPilotAIApp1
分支：main（完整版）| feature/transcript-only（精簡版）
本地路徑: ~/Documents/MyProjects/MeetingCopilotApp1/
MeetingTEXT 資料夾: ~/Documents/MyProjects/MeetingCopilotApp1/MeetingTEXT/
Pull 指令: cd ~/Documents/MyProjects/MeetingCopilotApp1 && git pull

Xcode 專案

完整版：open MeetingCopilot.xcodeproj（main 分支）
精簡版：open TranscriptOnly.xcodeproj（feature/transcript-only 分支）

API Keys 管理

APIKeys.swift: Sources/APIKeys.swift（在 .gitignore，本地編輯不推上去）
讀取優先順序: APIKeys.swift → Keychain（APIKeys 有值就不查 Keychain）
Claude Console: https://console.anthropic.com/settings/keys
Notion Integrations: https://www.notion.so/profile/integrations

Notion

Workspace: Michael's Notion
MeetingCopilot Parent Page ID: 320f154a-6472-804f-a226-c3694c1bb319
Integration 名稱: MeetingCopilot
權限: 讀取內容 ✅ / 插入內容 ✅ / 更新內容 ✅

NotebookLM

Bridge URL: http://localhost:3210（預設）
每場會議獨立 Notebook，從 URL 取得 ID

Gmail

Michael 的 Email: chchlin1018@gmail.com


會議準備完整工作流
Phase 1：收集資訊 → 建立 Notion 頁面
Step 1：收集會議資訊
詢問使用者：

會議名稱和日期
參與者（姓名、職位、公司、關係）
會議類型和語言
相關文件（PDF / PPTX / Google Doc 連結）
相關郵件往來（搜尋 Gmail）
上次會議的進展摘要

Step 2：建立 Notion 子頁面（所有資料都在這裡）
在 MeetingCopilot parent page 下建立子頁面，標題格式：PreMeeting: 會議名稱 日期
Notion 頁面標準結構：
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
Step 3：搜尋 Gmail 並建立 Draft（如需要）

搜尋相關郵件 thread
建立 Gmail Draft（含 CC）
將 Draft 內容加入 Notion 頁面（quote block + 確認 checkbox）
加入 Talking Points

Step 4：使用者建立 NotebookLM Notebook（手動）

到 https://notebooklm.google.com 建立新 Notebook
上傳 PDF/PPTX 文件
從 URL 取得 Notebook ID
告訴 Claude ID，Claude 更新到 Notion 頁面


Phase 2：開會前 → Claude 從 Notion 產生 TXT
使用者說「幫我產生 TXT」或「我要開會了」時：
Step 5：Claude 讀取 Notion 頁面
使用 Notion MCP 或 API 讀取頁面所有 blocks，擷取：

[MEETING] 資訊
[SOURCES] notion_page_id + notebooklm_notebook_id
[GOALS] 從 bulleted_list_item
[ATTENDEES] 從 Attendees 區塊
[QA_MY_QUESTIONS] 從「我方想問」的 to_do blocks
[QA_THEIR_QUESTIONS] 從「對方可能問」的 heading_3 + paragraph
[TP] 從 Talking Points 的 to_do blocks（解析 [MUST]/[SHOULD]/[NICE] tag）
[PREANALYSIS] 從 Pre-Analysis 的 paragraph

Step 6：產生 TXT 並推送到 GitHub
TXT 格式：
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
推送到 GitHub：MeetingTEXT/YYYY-MM-DD_會議名稱.txt
Step 7：使用者載入 App
cd ~/Documents/MyProjects/MeetingCopilotApp1 && git pull
App → System Check → 全部通過 → 讀取 TXT → 開始會議

已建立的會議
│ 會議                      │ Notion Page ID                            │ NotebookLM ID                              │ TXT                                 │
│ BiWeekly-Stanley-11Mar26  │ 320f154a-6472-815c-8ad0-c214783dfe22      │ ccaeee5e-8971-49e1-801d-2989ded2c61b       │ 2026-03-11_BiWeekly-Stanley.txt    │
│ BiWeekly-Mark-JJ-12Mar26  │ 320f154a-6472-813f-bc2c-d98e570ab696      │ 51364658-5c30-4b55-8118-5103095ae8d0       │ 2026-03-12_BiWeekly-Mark-JJ.txt    │

Michael 的業務背景
進行中的案子

MBI Utitech M&A — TECO 併購 + 股權重組（與 Stanley/iVP）

  TECO engaged：Michael 與副董事長 + 子公司 GM 談條件中
  交易結構：Abico 先買 20-22% → 轉手 TECO → Abico 留 10-15%
  20% treasury shares → TECO 取得
  個人股東 30-31%：TECO 拿到 20% 後可簽 LOI
  達 51% 後置換經營權 + 預期額外 20%
  預計 4 月中下旬明朗

John & Jill's — 澳洲蜂蜜品牌台灣市場進入（與 Mark）
Gamuda Silicon Island — 馬來西亞半導體園區台灣連結（透過 Stanley → Lillian）

  Lillian 3/6 回信：想加入 HTFA + 訪台
  建議 mid/late APR 或 5月中（搭配 Computex）會面
  合作模式：consultancy or 讓 Gamuda 自行接洽

YTEC — 先進封裝設備 Penang 合作
Johor DC — 資料中心 + 水處理 + Digital Twin

  分兩期：第一期 ~400MW，第二期 ~300MW
  Stanley 跟進電力 + 光纖落地時間
  Michael 對接 power cable + fiber 台灣 license 持有者

John 再生水設備 — Vendor ready to go

  需 John advice 如何推進
  提議 APR/May 新加坡碰面 + 見 SG DC operators

關鍵聯絡人
│ 姓名     │ 公司/角色              │ 關係           │
│ Stanley  │ iVP/TCA Partner         │ 合作夥伴，BiWeekly │
│ Mark     │ John & Jill's Founder   │ 合作夥伴，BiWeekly │
│ Lillian  │ Gamuda ED               │ 透過 Stanley 介紹 │
│ Teresa   │ TECO 副董事長           │ 報告 M&A 接洽  │
│ Jason    │ TECO M&A Head           │ M&A 決策      │
│ Bred     │ Utitech CFO 12%         │ 股權談判      │
│ Sean     │ Utitech VP 6%           │ 股權談判      │
│ William  │ Utitech Chairman 24%    │ 股權談判      │
│ John     │ 新加坡 DC / 水處理      │ 合作夥伴      │

0311 Stanley 會議 Action Items
│ #  │ Action                                       │ 負責人   │ 時間         │
│ 1  │ UTT 20% 股權收購進度跟進                   │ Michael  │ 4月中下旬     │
│ 2  │ Lillian/Gamuda HTFA 入會 + 5月中會面安排    │ Michael  │ 5月中         │
│ 3  │ Johor DC 電力 + 光纖落地時間                │ Stanley  │ 年內         │
│ 4  │ Computex 日期確認 + 5月中會面協調           │ Michael  │ 查日期       │
│ 5  │ Stanley 4月下旬或5月中訪台                 │ Stanley  │ 4-5月        │
│ 6  │ MY energy 公司 × 槟城/柔佛 DC power/fiber  │ Michael  │ 持續         │

Email Draft 策略
Engagement / 顧問費用談判措辭
當對方未回應付費問題時，使用暗示語言：

"structured support" — 暗示非隨便幫忙
"scope of engagement" — 暗示有合作框架
"allocate time and resources" — 暗示有成本
不直接提錢 — 留給中間人推動


App 設定（一次性）
│ 欄位                    │ 說明                                    │
│ Claude API Key         │ APIKeys.swift（優先）或 Keychain        │
│ Notion API Key         │ APIKeys.swift（優先）或 Keychain        │
│ NotebookLM Notebook ID │ 每場會議在 TXT 設定                    │
│ NotebookLM Bridge URL  │ http://localhost:3210                    │

開會前檢查清單

完整版（main 分支）：
☐ git pull 拉最新 code
☐ 確認 APIKeys.swift 有填入真實 key
☐ ⌘R Build & Run
☐ 跑 System Check → 全部綠色 ✅
☐ 開 Zoom/Teams → 再按「開始會議」

精簡版（feature/transcript-only 分支）：
☐ git checkout feature/transcript-only && git pull
☐ open TranscriptOnly.xcodeproj
☐ ⌘R Build & Run
☐ 開 Zoom/Teams → 按「開始會議」（不需要 API Key）

權限

System Settings → Privacy & Security → 螢幕與系統錄音 → MeetingCopilot / TranscriptOnly: 開啟
每次 Xcode 重新 build 後可能需要重新授權 TCC

重要 Git 指令
# 停止追蹤 APIKeys.swift（保護 key 不推上 GitHub）
git rm --cached Sources/APIKeys.swift
git commit -m "stop tracking APIKeys.swift"
git push

# 重置 ScreenCaptureKit TCC 權限（build 後權限失效時）
tccutil reset ScreenCapture com.RealityMatrix.MeetingCopilot
# 或精簡版
tccutil reset ScreenCapture com.RealityMatrix.TranscriptOnly

# 切換分支
git checkout main                      # 完整版
git checkout feature/transcript-only   # 精簡版

開發歷史摘要

2026-03-11 晚間 — feature/transcript-only 分支
│ 項目     │ 內容                                                          │
│ 新分支   │ feature/transcript-only（從 main 建立）                       │
│ 新專案   │ TranscriptOnly.xcodeproj（獨立 Xcode 專案）                 │
│ 新檔案   │ TranscriptOnlyApp.swift, TranscriptOnlyView.swift             │
│ 設定檔   │ Info.plist, TranscriptOnly.entitlements, Assets.xcassets       │
│ 結果     │ ✅ Build & Run 成功，UI 正常顯示                               │

v4.3.1（2026-03-11）— 6 commits
│ Commit    │ 內容                                                         │
│ d92e8db   │ fix: KeychainManager.shared → .load（修 3 build errors）     │
│ 9e4dcbb   │ fix: SystemCheckView 加入 Xcode project target              │
│ 6a886fd   │ improve: TranscriptPipeline 錯誤訊息分類                    │
│ 6877c9f   │ feat: Live Partial Results + 正在聆聽                        │
│ 1243672   │ fix: recentTranscript 雙串流空白 bug                        │
│ c5eb66b   │ style: 對方=cyan 我方=yellow                                │

後續 commits：
APIKeys.swift + .gitignore + Keychain fallback
字體放大 + Teleprompter 開場 TP
BiWeekly-Stanley TXT + BiWeekly-Mark-JJ TXT
README.md + TODO.md 更新至 v4.3.1
MeetingPrep-SKILL.md 更新


Updated: 2026-03-11 | MeetingCopilot v4.3.1 + TranscriptOnly v1.0 | Reality Matrix Inc.
