// MeetingCopilotApp.swift
// MeetingCopilot v4.1
//
// App Entry Point
// macOS 14.0+ (Sonoma)
// Copyright © 2025 MacroVision Systems

import SwiftUI

@main
struct MeetingCopilotApp: App {

    var body: some Scene {
        WindowGroup {
            MeetingTeleprompterView()
                .frame(minWidth: 1200, minHeight: 700)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1400, height: 800)
        .commands {
            // 自定義選單
            CommandGroup(after: .appInfo) {
                Button("Check NotebookLM Bridge...") {
                    checkBridgeHealth()
                }
                .keyboardShortcut("B", modifiers: [.command, .shift])
            }
        }
    }

    /// 檢查 NotebookLM Bridge 是否運行中
    private func checkBridgeHealth() {
        Task {
            guard let url = URL(string: "http://localhost:3210/health") else { return }
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let status = json["status"] as? String,
                   let mode = json["mode"] as? String {
                    print("✅ NotebookLM Bridge: \(status) (mode: \(mode))")
                }
            } catch {
                print("❌ NotebookLM Bridge not running: \(error.localizedDescription)")
                print("💡 Start with: cd bridge && npm run dev")
            }
        }
    }
}
