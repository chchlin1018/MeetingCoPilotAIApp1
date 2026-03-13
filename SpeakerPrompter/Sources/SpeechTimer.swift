// SpeechTimer.swift
// SpeakerPrompter v1.0 — 演講計時器

import Foundation
import Combine

@Observable
class SpeechTimer {
    
    private(set) var state: TimerState = .idle
    private(set) var totalElapsedSeconds: Int = 0
    private(set) var sectionElapsedSeconds: Int = 0
    private(set) var currentSectionIndex: Int = 0
    
    var totalMinutes: Int = 30
    var sections: [AgendaItem] = []
    
    private var timer: Timer?
    private var startTime: Date?
    private var sectionStartTime: Date?
    private var pausedElapsed: TimeInterval = 0
    private var pausedSectionElapsed: TimeInterval = 0
    
    // MARK: - Computed
    
    var totalRemainingSeconds: Int {
        max(0, totalMinutes * 60 - totalElapsedSeconds)
    }
    
    var sectionRemainingSeconds: Int {
        guard currentSectionIndex < sections.count else { return 0 }
        let sectionMinutes = sections[currentSectionIndex].minutes
        return max(0, sectionMinutes * 60 - sectionElapsedSeconds)
    }
    
    var isOvertime: Bool { totalElapsedSeconds > totalMinutes * 60 }
    var isSectionOvertime: Bool {
        guard currentSectionIndex < sections.count else { return false }
        return sectionElapsedSeconds > sections[currentSectionIndex].minutes * 60
    }
    
    var progress: Double {
        guard totalMinutes > 0 else { return 0 }
        return min(1.0, Double(totalElapsedSeconds) / Double(totalMinutes * 60))
    }
    
    var sectionProgress: Double {
        guard currentSectionIndex < sections.count else { return 0 }
        let sectionTotal = sections[currentSectionIndex].minutes * 60
        guard sectionTotal > 0 else { return 0 }
        return min(1.0, Double(sectionElapsedSeconds) / Double(sectionTotal))
    }
    
    var currentSection: AgendaItem? {
        guard currentSectionIndex < sections.count else { return nil }
        return sections[currentSectionIndex]
    }
    
    // MARK: - Actions
    
    func start() {
        guard state == .idle || state == .paused else { return }
        if state == .idle {
            startTime = Date()
            sectionStartTime = Date()
            if !sections.isEmpty { sections[0].isActive = true }
        } else {
            // Resume from pause
            startTime = Date().addingTimeInterval(-pausedElapsed)
            sectionStartTime = Date().addingTimeInterval(-pausedSectionElapsed)
        }
        state = .running
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }
    
    func pause() {
        guard state == .running else { return }
        pausedElapsed = TimeInterval(totalElapsedSeconds)
        pausedSectionElapsed = TimeInterval(sectionElapsedSeconds)
        timer?.invalidate()
        timer = nil
        state = .paused
    }
    
    func nextSection() {
        guard currentSectionIndex < sections.count else { return }
        // 記錄當前段落實際時間
        sections[currentSectionIndex].actualSeconds = sectionElapsedSeconds
        sections[currentSectionIndex].isCompleted = true
        sections[currentSectionIndex].isActive = false
        
        currentSectionIndex += 1
        sectionElapsedSeconds = 0
        sectionStartTime = Date()
        pausedSectionElapsed = 0
        
        if currentSectionIndex < sections.count {
            sections[currentSectionIndex].isActive = true
        } else {
            finish()
        }
    }
    
    func previousSection() {
        guard currentSectionIndex > 0 else { return }
        sections[currentSectionIndex].isActive = false
        sections[currentSectionIndex].isCompleted = false
        currentSectionIndex -= 1
        sections[currentSectionIndex].isActive = true
        sections[currentSectionIndex].isCompleted = false
        sectionElapsedSeconds = 0
        sectionStartTime = Date()
        pausedSectionElapsed = 0
    }
    
    func reset() {
        timer?.invalidate()
        timer = nil
        state = .idle
        totalElapsedSeconds = 0
        sectionElapsedSeconds = 0
        currentSectionIndex = 0
        pausedElapsed = 0
        pausedSectionElapsed = 0
        for i in sections.indices {
            sections[i].isActive = false
            sections[i].isCompleted = false
            sections[i].actualSeconds = 0
        }
    }
    
    func finish() {
        timer?.invalidate()
        timer = nil
        state = .finished
        // 記錄最後一個段落
        if currentSectionIndex < sections.count {
            sections[currentSectionIndex].actualSeconds = sectionElapsedSeconds
            sections[currentSectionIndex].isCompleted = true
            sections[currentSectionIndex].isActive = false
        }
    }
    
    private func tick() {
        guard let start = startTime else { return }
        totalElapsedSeconds = Int(Date().timeIntervalSince(start))
        if let secStart = sectionStartTime {
            sectionElapsedSeconds = Int(Date().timeIntervalSince(secStart))
        }
    }
    
    // MARK: - Formatting
    
    static func formatTime(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
    
    static func formatTimeMMSS(_ seconds: Int) -> String {
        let m = abs(seconds) / 60
        let s = abs(seconds) % 60
        let sign = seconds < 0 ? "-" : ""
        return String(format: "%@%02d:%02d", sign, m, s)
    }
}
