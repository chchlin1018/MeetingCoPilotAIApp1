// ═══════════════════════════════════════════════════════════════════════════
// KeychainManager.swift
// MeetingCopilot v4.3.1 — APIKeys.swift 優先 + Keychain Fallback
// ═══════════════════════════════════════════════════════════════════════════

import Foundation
import Security

enum KeychainManager {

    enum Key: String, CaseIterable {
        case claudeAPIKey = "claude_api_key"
        case notionAPIKey = "notion_api_key"
        case notebookLMNotebookId = "notebooklm_notebook_id"
        case notebookLMBridgeURL = "notebooklm_bridge_url"

        var displayName: String {
            switch self {
            case .claudeAPIKey:          return "Claude API Key"
            case .notionAPIKey:          return "Notion API Key"
            case .notebookLMNotebookId:  return "NotebookLM Notebook ID"
            case .notebookLMBridgeURL:   return "NotebookLM Bridge URL"
            }
        }

        var placeholder: String {
            switch self {
            case .claudeAPIKey:          return "sk-ant-api03-..."
            case .notionAPIKey:          return "ntn_... or secret_..."
            case .notebookLMNotebookId:  return "notebook_abc123"
            case .notebookLMBridgeURL:   return "http://localhost:3210"
            }
        }

        var isRequired: Bool {
            switch self {
            case .claudeAPIKey: return true
            default: return false
            }
        }
    }

    // ★ Bundle ID
    private static let service = "com.RealityMatrix.MeetingCopilot"

    @discardableResult
    static func save(key: Key, value: String) -> Bool {
        guard !value.isEmpty else { return delete(key: key) }
        let data = Data(value.utf8)
        delete(key: key)
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecValueData as String:   data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    static func load(key: Key) -> String? {
        // ★ 1. 優先從 APIKeys.swift 讀取（本地 hardcoded）
        if let hardcoded = hardcodedValue(for: key) {
            return hardcoded
        }

        // ★ 2. Fallback: 從 Keychain 讀取
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data,
           let value = String(data: data, encoding: .utf8), !value.isEmpty {
            return value
        }

        return nil
    }

    /// 從 APIKeys.swift 讀取值（有效值才回傳，placeholder 回傳 nil）
    private static func hardcodedValue(for key: Key) -> String? {
        let value: String
        switch key {
        case .claudeAPIKey:         value = APIKeys.claudeAPIKey
        case .notionAPIKey:         value = APIKeys.notionAPIKey
        case .notebookLMBridgeURL:  value = APIKeys.notebookLMBridgeURL
        case .notebookLMNotebookId: return nil
        }
        // placeholder 或空值 → 跳過，走 Keychain
        if value.contains("PASTE_YOUR") || value.isEmpty { return nil }
        return value
    }

    @discardableResult
    static func delete(key: Key) -> Bool {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    // MARK: - 便利方法

    static var hasClaudeAPIKey: Bool {
        guard let key = load(key: .claudeAPIKey) else { return false }
        return !key.isEmpty && key != "YOUR_API_KEY_HERE"
    }

    static var claudeAPIKey: String? {
        let key = load(key: .claudeAPIKey)
        if key == "YOUR_API_KEY_HERE" { return nil }
        return key
    }

    static var notionAPIKey: String? {
        let key = load(key: .notionAPIKey)
        guard let k = key, !k.isEmpty else { return nil }
        return k
    }

    static var hasNotionAPIKey: Bool {
        notionAPIKey != nil
    }

    static var notebookLMConfig: NotebookLMConfig {
        guard let notebookId = load(key: .notebookLMNotebookId),
              !notebookId.isEmpty else { return .default }
        let bridgeURL = load(key: .notebookLMBridgeURL) ?? "http://localhost:3210"
        return .enabled(notebookId: notebookId, bridgeURL: bridgeURL)
    }

    static func clearAll() {
        Key.allCases.forEach { delete(key: $0) }
    }
}
