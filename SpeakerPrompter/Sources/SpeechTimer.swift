// SpeechTimer.swift
// SpeakerPrompter v1.0 — 演講計時器
// Fixed: @Sendable Timer closure

import Foundation
import Combine

@Observable
final class SpeechTimer: @unchecked Sendable {
    
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
    
    var totalRemainingSeconds: Int { max(0, totalMinutes * 60 - totalElapsedSeconds) }
    var sectionRemainingSeconds: Int {
        guard currentSectionIndex < sections.count else { return 0 }
        return max(0, sections[currentSectionIndex].minutes * 60 - sectionElapsedSeconds)
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
        let total = sections[currentSectionIndex].minutes * 60
        guard total > 0 else { return 0 }
        return min(1.0, Double(sectionElapsedSeconds) / Double(total))
    }
    var currentSection: AgendaItem? {
        guard currentSectionIndex < sections.count else { return nil }
        return sections[currentSectionIndex]
    }
    
    func start() {
        guard state == .idle || state == .paused else { return }
        if state == .idle {
            startTime = Date()
            sectionStartTime = Date()
            if !sections.isEmpty { sections[0].isActive = true }
        } else {
            startTime = Date().addingTimeInterval(-pausedElapsed)
            sectionStartTime = Date().addingTimeInterval(-pausedSectionElapsed)
        }
        state = .running
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.tick()
        }
    }
    
    func pause() {
        guard state == .running else { return }
        pausedElapsed = TimeInterval(totalElapsedSeconds)
        pausedSectionElapsed = TimeInterval(sectionElapsedSeconds)
        timer?.invalidate(); timer = nil
        state = .paused
    }
    
    func nextSection() {
        guard currentSectionIndex < sections.count else { return }
        sections[currentSectionIndex].actualSeconds = sectionElapsedSeconds
        sections[currentSectionIndex].isCompleted = true
        sections[currentSectionIndex].isActive = false
        currentSectionIndex += 1
        sectionElapsedSeconds = 0; sectionStartTime = Date(); pausedSectionElapsed = 0
        if currentSectionIndex < sections.count {
            sections[currentSectionIndex].isActive = true
        } else { finish() }
    }
    
    func previousSection() {
        guard currentSectionIndex > 0 else { return }
        sections[currentSectionIndex].isActive = false
        sections[currentSectionIndex].isCompleted = false
        currentSectionIndex -= 1
        sections[currentSectionIndex].isActive = true
        sections[currentSectionIndex].isCompleted = false
        sectionElapsedSeconds = 0; sectionStartTime = Date(); pausedSectionElapsed = 0
    }
    
    func reset() {
        timer?.invalidate(); timer = nil
        state = .idle; totalElapsedSeconds = 0; sectionElapsedSeconds = 0
        currentSectionIndex = 0; pausedElapsed = 0; pausedSectionElapsed = 0
        for i in sections.indices {
            sections[i].isActive = false; sections[i].isCompleted = false; sections[i].actualSeconds = 0
        }
    }
    
    func finish() {
        timer?.invalidate(); timer = nil; state = .finished
        if currentSectionIndex < sections.count {
            sections[currentSectionIndex].actualSeconds = sectionElapsedSeconds
            sections[currentSectionIndex].isCompleted = true
            sections[currentSectionIndex].isActive = false
        }
    }
    
    private func tick() {
        guard let start = startTime else { return }
        totalElapsedSeconds = Int(Date().timeIntervalSince(start))
        if let secStart = sectionStartTime { sectionElapsedSeconds = Int(Date().timeIntervalSince(secStart)) }
    }
    
    static func formatTime(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
