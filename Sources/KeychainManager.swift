// ═══════════════════════════════════════════════════════════════════════════
// KeychainManager.swift
// MeetingCopilot v4.2 — macOS Keychain 安全儲存
// ═══════════════════════════════════════════════════════════════════════════
//
//  負責安全儲存 API Key 和機密資料到 macOS Keychain。
//  不再將 API key 硬編碼在程式碼中。
//
//  儲存的 key：
//  - Claude API Key ("claude_api_key")
//  - NotebookLM Notebook ID ("notebooklm_notebook_id")
//  - NotebookLM Bridge URL ("notebooklm_bridge_url")
//
//  Platform: macOS 14.0+
// ═══════════════════════════════════════════════════════════════════════════

import Foundation
import Security

enum KeychainManager {

    // MARK: - Key 定義

    enum Key: String, CaseIterable {
        case claudeAPIKey = "claude_api_key"
        case notebookLMNotebookId = "notebooklm_notebook_id"
        case notebookLMBridgeURL = "notebooklm_bridge_url"

        var displayName: String {
            switch self {
            case .claudeAPIKey:          return "Claude API Key"
            case .notebookLMNotebookId:  return "NotebookLM Notebook ID"
            case .notebookLMBridgeURL:   return "NotebookLM Bridge URL"
            }
        }

        var placeholder: String {
            switch self {
            case .claudeAPIKey:          return "sk-ant-api03-..."
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

    private static let service = "com.macrovision.MeetingCopilot"

    // MARK: - Save

    @discardableResult
    static func save(key: Key, value: String) -> Bool {
        guard !value.isEmpty else { return delete(key: key) }

        let data = Data(value.utf8)

        // 先刪除舊的
        delete(key: key)

        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecValueData as String:   data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    // MARK: - Load

    static func load(key: Key) -> String? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Delete

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

    /// Claude API Key 是否已設定
    static var hasClaudeAPIKey: Bool {
        guard let key = load(key: .claudeAPIKey) else { return false }
        return !key.isEmpty && key != "YOUR_API_KEY_HERE"
    }

    /// 取得 Claude API Key（如果沒設定則回傳 nil）
    static var claudeAPIKey: String? {
        let key = load(key: .claudeAPIKey)
        if key == "YOUR_API_KEY_HERE" { return nil }
        return key
    }

    /// 取得 NotebookLM 設定
    static var notebookLMConfig: NotebookLMConfig {
        guard let notebookId = load(key: .notebookLMNotebookId),
              !notebookId.isEmpty else {
            return .default
        }
        let bridgeURL = load(key: .notebookLMBridgeURL) ?? "http://localhost:3210"
        return .enabled(notebookId: notebookId, bridgeURL: bridgeURL)
    }

    /// 清除所有儲存的 key
    static func clearAll() {
        Key.allCases.forEach { delete(key: $0) }
    }
}
