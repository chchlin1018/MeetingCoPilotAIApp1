// ═══════════════════════════════════════════════════════════════════════════
// SystemMonitor.swift
// MeetingCopilot v4.3 — 系統負載監控（CPU / Memory / Network）
// ═══════════════════════════════════════════════════════════════════════════
//
//  提供會議中系統狀態監控，確保使用者知道設備負載：
//  - CPU 使用率（過高可能影響音訊擷取和 AI 回應速度）
//  - 記憶體使用量（App 占用 + 系統剩餘）
//  - 網路品質（API 延遲追蹤）
//
//  Platform: macOS 14.0+
// ═══════════════════════════════════════════════════════════════════════════

import Foundation
import Darwin

// MARK: - System Snapshot

struct SystemSnapshot: Sendable {
    let cpuUsage: Double           // 0.0 ~ 1.0
    let memoryUsedMB: Int          // App 占用 MB
    let memoryTotalMB: Int         // 系統總記憶體 MB
    let memoryPressure: MemoryPressure
    let networkLatencyMs: Double   // 最近 API 延遲
    let networkQuality: NetworkQuality
    let timestamp: Date

    enum MemoryPressure: String, Sendable {
        case normal = "Normal"
        case warning = "Warning"
        case critical = "Critical"
    }

    enum NetworkQuality: String, Sendable {
        case excellent = "Excellent"   // < 500ms
        case good = "Good"             // 500-1500ms
        case fair = "Fair"             // 1500-3000ms
        case poor = "Poor"             // > 3000ms
        case unknown = "--"
    }

    // UI 輔助
    var cpuPercent: Int { Int(cpuUsage * 100) }
    var memoryUsedPercent: Int { memoryTotalMB > 0 ? Int(Double(memoryUsedMB) / Double(memoryTotalMB) * 100) : 0 }
    var memoryAvailableMB: Int { max(0, memoryTotalMB - memoryUsedMB) }
}

// MARK: - System Monitor

@Observable
@MainActor
final class SystemMonitor {

    private(set) var snapshot = SystemSnapshot(
        cpuUsage: 0, memoryUsedMB: 0, memoryTotalMB: 0,
        memoryPressure: .normal, networkLatencyMs: 0,
        networkQuality: .unknown, timestamp: Date()
    )

    private var timer: Task<Void, Never>?
    private var recentLatencies: [Double] = []   // 最近 5 次 API 延遲
    private let maxLatencyHistory = 5

    // MARK: Start / Stop

    func start(intervalSeconds: Double = 3.0) {
        stop()
        timer = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { break }
                self.snapshot = self.collectSnapshot()
                try? await Task.sleep(nanoseconds: UInt64(intervalSeconds * 1_000_000_000))
            }
        }
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    /// 外部報告 API 延遲（從 ResponseOrchestrator 呼叫）
    func reportLatency(_ ms: Double) {
        recentLatencies.append(ms)
        if recentLatencies.count > maxLatencyHistory {
            recentLatencies.removeFirst()
        }
    }

    // MARK: Collect

    private func collectSnapshot() -> SystemSnapshot {
        let cpu = Self.getCPUUsage()
        let (usedMB, totalMB) = Self.getMemoryInfo()
        let pressure = Self.getMemoryPressure(usedPercent: Double(usedMB) / max(1, Double(totalMB)))
        let avgLatency = recentLatencies.isEmpty ? 0 : recentLatencies.reduce(0, +) / Double(recentLatencies.count)
        let quality = Self.classifyNetworkQuality(latencyMs: avgLatency, hasData: !recentLatencies.isEmpty)

        return SystemSnapshot(
            cpuUsage: cpu,
            memoryUsedMB: usedMB,
            memoryTotalMB: totalMB,
            memoryPressure: pressure,
            networkLatencyMs: avgLatency,
            networkQuality: quality,
            timestamp: Date()
        )
    }

    // ═════════════════════════════════════════════════
    // MARK: CPU Usage (Mach API)
    // ═════════════════════════════════════════════════

    private static func getCPUUsage() -> Double {
        var cpuInfo: processor_info_array_t?
        var numCPUInfo: mach_msg_type_number_t = 0
        var numCPUs: natural_t = 0

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &numCPUs,
            &cpuInfo,
            &numCPUInfo
        )

        guard result == KERN_SUCCESS, let info = cpuInfo else { return 0 }

        var totalUser: Int32 = 0
        var totalSystem: Int32 = 0
        var totalIdle: Int32 = 0

        for i in 0..<Int(numCPUs) {
            let offset = Int(CPU_STATE_MAX) * i
            totalUser += info[offset + Int(CPU_STATE_USER)]
            totalSystem += info[offset + Int(CPU_STATE_SYSTEM)]
            totalIdle += info[offset + Int(CPU_STATE_IDLE)]
        }

        let total = Double(totalUser + totalSystem + totalIdle)
        let used = Double(totalUser + totalSystem)

        // Deallocate
        let size = vm_size_t(numCPUInfo) * vm_size_t(MemoryLayout<integer_t>.stride)
        vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), size)

        return total > 0 ? min(1.0, used / total) : 0
    }

    // ═════════════════════════════════════════════════
    // MARK: Memory Info
    // ═════════════════════════════════════════════════

    private static func getMemoryInfo() -> (usedMB: Int, totalMB: Int) {
        // 系統總記憶體
        let totalBytes = ProcessInfo.processInfo.physicalMemory
        let totalMB = Int(totalBytes / 1024 / 1024)

        // App 占用記憶體
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), intPtr, &count)
            }
        }

        let appUsedMB: Int
        if result == KERN_SUCCESS {
            appUsedMB = Int(info.resident_size / 1024 / 1024)
        } else {
            appUsedMB = 0
        }

        // 系統級使用量（vm_statistics64）
        var vmInfo = vm_statistics64()
        var vmCount = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<natural_t>.size)
        let vmResult = withUnsafeMutablePointer(to: &vmInfo) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(vmCount)) { intPtr in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, intPtr, &vmCount)
            }
        }

        if vmResult == KERN_SUCCESS {
            let pageSize = UInt64(vm_kernel_page_size)
            let activeMB = Int(UInt64(vmInfo.active_count) * pageSize / 1024 / 1024)
            let wiredMB = Int(UInt64(vmInfo.wire_count) * pageSize / 1024 / 1024)
            let compressedMB = Int(UInt64(vmInfo.compressor_page_count) * pageSize / 1024 / 1024)
            let systemUsedMB = activeMB + wiredMB + compressedMB
            return (usedMB: systemUsedMB, totalMB: totalMB)
        }

        return (usedMB: appUsedMB, totalMB: totalMB)
    }

    private static func getMemoryPressure(usedPercent: Double) -> SystemSnapshot.MemoryPressure {
        if usedPercent > 0.9 { return .critical }
        if usedPercent > 0.75 { return .warning }
        return .normal
    }

    // ═════════════════════════════════════════════════
    // MARK: Network Quality
    // ═════════════════════════════════════════════════

    private static func classifyNetworkQuality(latencyMs: Double, hasData: Bool) -> SystemSnapshot.NetworkQuality {
        guard hasData else { return .unknown }
        if latencyMs < 500 { return .excellent }
        if latencyMs < 1500 { return .good }
        if latencyMs < 3000 { return .fair }
        return .poor
    }
}
