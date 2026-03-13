# SpeakerPrompter — 個人演講提示版

> MeetingCopilot 精簡版 — 專為個人演講、簡報、Pitch 設計的即時提詞器

不需要音訊擷取、不需要 AI、不需要網路。只需要你的演講大綱和重點，它就會在螢幕上提示你。

## 功能

- 📋 **Agenda 議程提示** — 顯示演講大綱，自動高亮目前進行中的段落
- 🎯 **Talking Points** — MUST / SHOULD / NICE 三級重點，手動打勾完成
- ⏱️ **時間控制** — 總時間倒數 + 每段落建議時間 + 超時警告
- 📄 **TXT 檔讀取** — 用簡單的 TXT 格式定義演講內容
- 🖥️ **全螢幕模式** — 大字顯示，演講時一眼就能看到

## TXT 檔格式

```
[SPEECH]
title=IDTF 開源工業數位雙胞胎架構
type=Pitch
total_minutes=20

[AGENDA]
1|開場白 + 自我介紹|2
2|工業數位雙胞胎市場痛點|3
3|IDTF 架構介紹|5
4|技術 Demo|5
5|商業模式 + Roadmap|3
6|Q&A|2

[TP]
MUST|強調 IDTF 與 AVEVA/Siemens 的差異化：開源 + 跨平台
MUST|展示 TSMC 相關經驗和關係
MUST|Seed Round 目標 $2M 和用途說明
SHOULD|提到 2000+ GitHub Stars 社群認可
SHOULD|NVIDIA Omniverse / OpenUSD 整合優勢
NICE|半導體客戶案例（久元電子）
NICE|未來 v5.0 WhisperKit 路線圖

[NOTES]
開場要強而有力，不要先說「大家好」
用故事開始：「我在 AVEVA 做了 20 年...」
Demo 時放慢速度，讓觀眾看清楚
```

## 系統需求
- macOS 14.0+
- 不需要 API Key
- 不需要網路
- 不需要任何權限

© 2026 Reality Matrix Inc.
