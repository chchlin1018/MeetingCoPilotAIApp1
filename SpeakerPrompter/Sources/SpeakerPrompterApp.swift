// SpeakerPrompterApp.swift
// SpeakerPrompter v1.0 — 個人演講提示版

import SwiftUI

@main
struct SpeakerPrompterApp: App {
    var body: some Scene {
        WindowGroup {
            SpeakerPrompterView()
                .frame(minWidth: 800, minHeight: 500)
        }
        .windowStyle(.automatic)
        .defaultSize(width: 1000, height: 650)
    }
}
