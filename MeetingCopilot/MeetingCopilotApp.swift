// MeetingCopilotApp.swift
// MeetingCopilot v4.3
//
// App Entry Point + API Key Setup Flow (Claude + Notion)
// macOS 14.0+ (Sonoma)
// Copyright © 2025 MacroVision Systems

import SwiftUI

@main
struct MeetingCopilotApp: App {

    @State private var showSettings = !KeychainManager.hasClaudeAPIKey

    var body: some Scene {
        WindowGroup {
            ZStack {
                MeetingTeleprompterView()
                    .frame(minWidth: 1200, minHeight: 700)

                if showSettings {
                    Color.black.opacity(0.6).ignoresSafeArea()
                    APIKeySettingsView(isPresented: $showSettings)
                        .frame(width: 520, height: 520)
                        .background(.ultraThinMaterial)
                        .cornerRadius(16)
                        .shadow(radius: 20)
                }
            }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1400, height: 800)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("API Key Settings...") {
                    showSettings = true
                }
                .keyboardShortcut(",", modifiers: .command)

                Divider()

                Button("Check NotebookLM Bridge...") {
                    checkBridgeHealth()
                }
                .keyboardShortcut("B", modifiers: [.command, .shift])
            }
        }
    }

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
            }
        }
    }
}

// MARK: - API Key 設定畫面

struct APIKeySettingsView: View {
    @Binding var isPresented: Bool

    @State private var claudeAPIKey: String = KeychainManager.load(key: .claudeAPIKey) ?? ""
    @State private var notionAPIKey: String = KeychainManager.load(key: .notionAPIKey) ?? ""    // ★
    @State private var notebookId: String = KeychainManager.load(key: .notebookLMNotebookId) ?? ""
    @State private var bridgeURL: String = KeychainManager.load(key: .notebookLMBridgeURL) ?? "http://localhost:3210"
    @State private var saveStatus: String = ""
    @State private var isValid: Bool = false

    var body: some View {
        VStack(spacing: 16) {
            // 標題
            VStack(spacing: 4) {
                Image(systemName: "key.fill")
                    .font(.system(size: 32)).foregroundColor(.purple)
                Text("MeetingCopilot 設定")
                    .font(.system(size: 18, weight: .bold))
                Text("API Key 安全儲存於 macOS Keychain")
                    .font(.system(size: 12)).foregroundColor(.secondary)
            }
            .padding(.top, 8)

            VStack(alignment: .leading, spacing: 12) {
                // Claude API Key (必填)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Claude API Key").font(.system(size: 12, weight: .semibold))
                        Text("必填").font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(Color.red).cornerRadius(3)
                    }
                    SecureField("sk-ant-api03-...", text: $claudeAPIKey)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13, design: .monospaced))
                        .onChange(of: claudeAPIKey) { _, _ in validateInput() }
                }

                // ★ Notion API Key (建議)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Notion API Key").font(.system(size: 12, weight: .semibold))
                        Text("建議").font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(Color.blue).cornerRadius(3)
                        Text("第二層 RAG 知識檢索")
                            .font(.system(size: 9)).foregroundColor(.gray)
                    }
                    SecureField("ntn_... or secret_...", text: $notionAPIKey)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13, design: .monospaced))
                    Text("到 notion.so/profile/integrations 建立 Integration 取得")
                        .font(.system(size: 9)).foregroundColor(.gray.opacity(0.6))
                }

                Divider().background(Color.gray.opacity(0.3))

                // NotebookLM Notebook ID (選填)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("NotebookLM Notebook ID").font(.system(size: 12, weight: .semibold))
                        Text("選填").font(.system(size: 9)).foregroundColor(.secondary)
                        Text("備用方案").font(.system(size: 9)).foregroundColor(.gray.opacity(0.5))
                    }
                    TextField("notebook_abc123", text: $notebookId)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13, design: .monospaced))
                }

                // Bridge URL (選填)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("NotebookLM Bridge URL").font(.system(size: 12, weight: .semibold))
                        Text("選填").font(.system(size: 9)).foregroundColor(.secondary)
                    }
                    TextField("http://localhost:3210", text: $bridgeURL)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13, design: .monospaced))
                }
            }
            .padding(.horizontal, 24)

            if !saveStatus.isEmpty {
                Text(saveStatus)
                    .font(.system(size: 12))
                    .foregroundColor(saveStatus.contains("✅") ? .green : .orange)
            }

            HStack(spacing: 12) {
                if KeychainManager.hasClaudeAPIKey {
                    Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.escape)
                }
                Button(action: saveAndClose) {
                    HStack(spacing: 6) {
                        Image(systemName: "lock.shield")
                        Text("儲存到 Keychain")
                    }
                    .frame(minWidth: 160)
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .disabled(!isValid)
                .keyboardShortcut(.return)
            }
            .padding(.bottom, 8)
        }
        .padding()
        .onAppear { validateInput() }
    }

    private func validateInput() {
        isValid = claudeAPIKey.hasPrefix("sk-ant-") && claudeAPIKey.count > 20
    }

    private func saveAndClose() {
        let ok1 = KeychainManager.save(key: .claudeAPIKey, value: claudeAPIKey)
        let ok2 = KeychainManager.save(key: .notionAPIKey, value: notionAPIKey)         // ★
        let ok3 = KeychainManager.save(key: .notebookLMNotebookId, value: notebookId)
        let ok4 = KeychainManager.save(key: .notebookLMBridgeURL, value: bridgeURL)

        if ok1 && ok2 && ok3 && ok4 {
            saveStatus = "✅ 已安全儲存到 macOS Keychain"
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                isPresented = false
            }
        } else {
            saveStatus = "⚠️ 儲存失敗，請檢查權限"
        }
    }
}
