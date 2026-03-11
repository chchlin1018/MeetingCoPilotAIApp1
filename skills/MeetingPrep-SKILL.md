MeetingCopilot 會議準備 Skill
概述
Michael Lin（林志錜）的會議準備工作流 Skill。
核心原則：Notion 是唯一的資料來源（Single Source of Truth）。TXT 只是 App 的載入格式，由 Claude 從 Notion 自動擷取產生。

★ App 開發現況（v4.3.1 — 2026-03-11）

支援的應用程式（11 個）

會議軟體：
  Microsoft Teams (com.microsoft.teams2)
  Zoom (us.zoom.xos)
  Google Meet (com.google.Chrome)
  Webex (com.cisco.webexmeetingsapp)
  Slack (com.tinyspeck.slackmacgap)

通訊軟體：
  LINE (jp.naver.line.mac)
  WhatsApp (net.whatsapp.WhatsApp)
  WhatsApp Native (WhatsApp)
  Telegram (ru.keepcoder.Telegram)
  Discord (com.hnc.Discord)
  FaceTime (com.apple.FaceTime)

分支策略：
  main — 完整版（18 Swift + AI 全管線）→ MeetingCopilot.xcodeproj
  feature/transcript-only — 精簡版（6 Swift，純語音辨識）→ TranscriptOnly.xcodeproj

main 分支架構：18 個 Swift 檔案 + 4 測試
Sources/
├── AudioCaptureEngine.swift         # Protocol + MeetingApp (11 個 App)
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
├── SystemCheckView.swift            # 會前 8 項系統診斷
├── PostMeetingReportService.swift   # AI 摘要 + Action Items + Notion 匯出
├── MeetingPrepView.swift            # 會前準備 UI + TXT + 語言選擇
├── DemoDataProvider.swift           # Demo 資料
└── UsageExample.swift               # 主畫面 + 分色逐字稿 + 會後儲存

feature/transcript-only 分支架構：6 個 Swift 檔案
TranscriptOnly/
├── TranscriptOnlyApp.swift          # @main（無 API Key）
└── TranscriptOnlyView.swift         # UI + ViewModel（直接接 Pipeline）
Sources/（共用）
├── AudioCaptureEngine.swift         # Protocol + MeetingApp (11 個 App)
├── SystemAudioCaptureEngine.swift   # ScreenCaptureKit → 對方
├── MicrophoneCaptureEngine.swift    # AVAudioEngine → 我方
└── TranscriptPipeline.swift         # 雙串流 + Audio Health

已完成功能

✅ 雙串流說話者分離（ScreenCaptureKit=對方 / Mic=我方）
✅ 支援 11 個 App（Teams/Zoom/Meet/Webex/Slack/LINE/WhatsApp/Telegram/Discord/FaceTime）
✅ 三層即時管線（本地Q&A < 200ms → 雙來源RAG 1-3s → Claude 2-4s）
✅ 雙來源並行 RAG（NotebookLM + Notion async let 同時查詢）
✅ Talking Points 追蹤（MUST/SHOULD/NICE + detectedSpeech）
✅ 會前系統檢查（SystemCheckView：8項自動檢測）
✅ Live Partial Results + 說話者分色（cyan/yellow）
✅ 音訊健康監控 badge + AI Teleprompter
✅ 會後報告（AI 摘要 + Action Items + Markdown/TXT/Notion 匯出）
✅ TranscriptOnly 精簡分支（Build & Run 成功）

已知問題 / 待修

⚠️ APIKeys.swift 已 push 到 GitHub（需 git rm --cached Sources/APIKeys.swift）
⚠️ Claude/Notion Key 已曝光 → 需 rotate
⚠️ UsageExample.swift 過大（~950 行）應拆分
⚠️ Tests 未加入 Xcode Test target

下一步

即時：TranscriptOnly 實測驗證
☐ LINE 通話實測
☐ WhatsApp 通話實測
☐ Zoom/Teams 會議實測
☐ FaceTime 通話實測
☐ 30 分鐘穩定性測試

後續（v4.4）
☐ Claude 動態關鍵字展開
☐ Evidence-based Card
☐ Notion 自動同步


核心資源連結

GitHub: https://github.com/chchlin1018/MeetingCoPilotAIApp1
分支：main | feature/transcript-only
本地路徑: ~/Documents/MyProjects/MeetingCopilotApp1/
Notion Parent Page ID: 320f154a-6472-804f-a226-c3694c1bb319
Gmail: chchlin1018@gmail.com

Xcode 專案
  完整版：open MeetingCopilot.xcodeproj（main）
  精簡版：open TranscriptOnly.xcodeproj（feature/transcript-only）

會議準備完整工作流

Phase 1：收集資訊 → 建立 Notion 頁面
Step 1：收集會議資訊
  會議名稱和日期、參與者、會議類型和語言、相關文件、相關郵件

Step 2：建立 Notion 子頁面
  標題格式：PreMeeting: 會議名稱 日期
  結構：Callout + Goals + Attendees + My Questions + Their Questions + Talking Points + Pre-Analysis

Step 3：搜尋 Gmail 並建立 Draft（如需要）

Step 4：使用者建立 NotebookLM Notebook（手動）

Phase 2：開會前 → Claude 從 Notion 產生 TXT
Step 5：Claude 讀取 Notion 頁面 → 擷取各區塊
Step 6：產生 TXT 並推送到 GitHub (MeetingTEXT/YYYY-MM-DD_名稱.txt)
Step 7：使用者 git pull → App 讀取 TXT → System Check → 開始會議

TXT 格式：
[MEETING] title/type/duration/language
[SOURCES] notion_page_id/notebooklm_notebook_id
[GOALS] 目標列表
[ATTENDEES] 參與者
[QA_MY_QUESTIONS] Q/K/A
[QA_THEIR_QUESTIONS] Q/K/A
[TP] MUST|SHOULD|NICE|重點|支撐數據|關鍵字
[PREANALYSIS] 策略分析

已建立的會議
  BiWeekly-Stanley-11Mar26: Notion 320f154a-6472-815c-8ad0-c214783dfe22 / NLM ccaeee5e-8971-49e1-801d-2989ded2c61b
  BiWeekly-Mark-JJ-12Mar26: Notion 320f154a-6472-813f-bc2c-d98e570ab696 / NLM 51364658-5c30-4b55-8118-5103095ae8d0

Michael 的業務背景

進行中的案子：
  MBI Utitech M&A — TECO 併購 + 股權重組（與 Stanley/iVP）
  John & Jill's — 澳洲蜂蜜品牌台灣市場（與 Mark）
  Gamuda Silicon Island — 馬來西亞半導體園區（透過 Stanley → Lillian）
  YTEC — 先進封裝 Penang
  Johor DC — 資料中心 + 水處理 + Digital Twin
  John 再生水設備

關鍵聯絡人：Stanley(iVP), Mark(J&J's), Lillian(Gamuda), Teresa/Jason(TECO), Bred/Sean/William(Utitech), John(新加坡 DC)

Email Draft 策略：當對方未回應付費問題時使用暗示語言（structured support / scope of engagement / allocate time and resources）

開會前檢查清單

完整版（main）：
  git pull → 確認 APIKeys.swift → ⌘R → System Check → 開 Zoom/Teams/LINE/WhatsApp → 開始會議

精簡版（feature/transcript-only）：
  git checkout feature/transcript-only → open TranscriptOnly.xcodeproj → ⌘R → 開任何 App 通話 → 開始會議

重要 Git 指令
  git rm --cached Sources/APIKeys.swift  # 停止追蹤 API Key
  tccutil reset ScreenCapture com.RealityMatrix.MeetingCopilot  # TCC 重置
  tccutil reset ScreenCapture com.RealityMatrix.TranscriptOnly  # 精簡版 TCC
  git checkout main / git checkout feature/transcript-only  # 切換分支


Updated: 2026-03-11 | MeetingCopilot v4.3.1 + TranscriptOnly v1.0 | 11 Supported Apps | Reality Matrix Inc.
