// TranscriptOnlyApp.swift
// TranscriptOnly — feature/transcript-only
// 精簡版：只測試雙串流即時語音辨識，無 AI 層

import SwiftUI

@main
struct TranscriptOnlyApp: App {
    var body: some Scene {
        WindowGroup {
            TranscriptOnlyView()
                .frame(minWidth: 700, minHeight: 500)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 900, height: 650)
    }
}
