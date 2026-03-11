// ═══════════════════════════════════════════════════════════════════════════
// APIKeys.swift
// MeetingCopilot — 本地 API Keys（此檔案在 .gitignore，不會推到 GitHub）
//
// ⚠️ 使用方式：
// 1. 在 Xcode 中直接編輯此檔案，填入你的真實 Key
// 2. 此檔案已加入 .gitignore，不會被 git 追蹤
// 3. 首次 push 後，執行以下指令停止追蹤：
//    git rm --cached Sources/APIKeys.swift && git commit -m "stop tracking APIKeys" && git push
// ═══════════════════════════════════════════════════════════════════════════

import Foundation

enum APIKeys {
    // ★ 在 Xcode 中填入你的真實 Key
    static let claudeAPIKey = "PASTE_YOUR_CLAUDE_API_KEY_HERE"
    static let notionAPIKey = "PASTE_YOUR_NOTION_API_KEY_HERE"
    static let notebookLMBridgeURL = "http://localhost:3210"
}
