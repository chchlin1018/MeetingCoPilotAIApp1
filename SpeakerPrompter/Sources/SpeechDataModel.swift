// SpeechDataModel.swift
// SpeakerPrompter v1.0 — 演講資料模型

import Foundation

// MARK: - Agenda Item

struct AgendaItem: Identifiable {
    let id = UUID()
    let order: Int
    let title: String
    let minutes: Int          // 建議時間（分鐘）
    var isActive: Bool = false
    var isCompleted: Bool = false
    var actualSeconds: Int = 0 // 實際花費秒數
}

// MARK: - Talking Point

enum TPPriority: String, CaseIterable {
    case must = "MUST"
    case should = "SHOULD"
    case nice = "NICE"
}

struct SpeakerTP: Identifiable {
    let id = UUID()
    let priority: TPPriority
    let content: String
    var isCompleted: Bool = false
}

// MARK: - Speech Config

struct SpeechConfig {
    var title: String = ""
    var type: String = "Presentation"
    var totalMinutes: Int = 30
    var agenda: [AgendaItem] = []
    var talkingPoints: [SpeakerTP] = []
    var notes: [String] = []
}

// MARK: - Timer State

enum TimerState {
    case idle
    case running
    case paused
    case finished
}

// MARK: - TXT Parser

enum SpeechFileParser {
    
    static func parse(_ content: String) -> SpeechConfig {
        var config = SpeechConfig()
        var currentSection = ""
        
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            
            // Section headers
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                currentSection = String(trimmed.dropFirst().dropLast()).uppercased()
                continue
            }
            
            switch currentSection {
            case "SPEECH":
                let parts = trimmed.split(separator: "=", maxSplits: 1)
                guard parts.count == 2 else { continue }
                let key = String(parts[0]).trimmingCharacters(in: .whitespaces).lowercased()
                let value = String(parts[1]).trimmingCharacters(in: .whitespaces)
                switch key {
                case "title": config.title = value
                case "type": config.type = value
                case "total_minutes": config.totalMinutes = Int(value) ?? 30
                default: break
                }
                
            case "AGENDA":
                // Format: order|title|minutes
                let parts = trimmed.split(separator: "|", maxSplits: 2)
                guard parts.count >= 2 else { continue }
                let order = Int(String(parts[0]).trimmingCharacters(in: .whitespaces)) ?? 0
                let title = String(parts[1]).trimmingCharacters(in: .whitespaces)
                let minutes = parts.count >= 3 ? Int(String(parts[2]).trimmingCharacters(in: .whitespaces)) ?? 0 : 0
                config.agenda.append(AgendaItem(order: order, title: title, minutes: minutes))
                
            case "TP":
                // Format: MUST|content
                let parts = trimmed.split(separator: "|", maxSplits: 1)
                guard parts.count == 2 else { continue }
                let priorityStr = String(parts[0]).trimmingCharacters(in: .whitespaces).uppercased()
                let content = String(parts[1]).trimmingCharacters(in: .whitespaces)
                let priority = TPPriority(rawValue: priorityStr) ?? .nice
                config.talkingPoints.append(SpeakerTP(priority: priority, content: content))
                
            case "NOTES":
                config.notes.append(trimmed)
                
            default: break
            }
        }
        
        return config
    }
}
