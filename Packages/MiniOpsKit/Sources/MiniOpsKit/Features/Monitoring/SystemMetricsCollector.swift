import Foundation
import Darwin

public final class SystemMetricsCollector: MetricsCollecting, @unchecked Sendable {
    private var previousCPUInfo: host_cpu_load_info?
    private let lock = NSLock()

    public init() {}

    public func collect() async -> SystemMetrics {
        SystemMetrics(
            cpuUsagePercent: cpuUsage(),
            memoryUsagePercent: memoryUsage(),
            diskUsagePercent: diskUsage(),
            collectedAt: Date()
        )
    }

    private func cpuUsage() -> Double {
        lock.lock()
        defer { lock.unlock() }

        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        var cpuInfo = host_cpu_load_info_data_t()

        let result = withUnsafeMutablePointer(to: &cpuInfo) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPointer in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, intPointer, &count)
            }
        }

        guard result == KERN_SUCCESS else { return 0 }

        let user = Double(cpuInfo.cpu_ticks.0)
        let system = Double(cpuInfo.cpu_ticks.1)
        let idle = Double(cpuInfo.cpu_ticks.2)
        let nice = Double(cpuInfo.cpu_ticks.3)
        let total = user + system + idle + nice

        guard total > 0 else { return 0 }

        if let previous = previousCPUInfo {
            let prevUser = Double(previous.cpu_ticks.0)
            let prevSystem = Double(previous.cpu_ticks.1)
            let prevIdle = Double(previous.cpu_ticks.2)
            let prevNice = Double(previous.cpu_ticks.3)
            let prevTotal = prevUser + prevSystem + prevIdle + prevNice

            let totalDelta = total - prevTotal
            let idleDelta = idle - prevIdle
            guard totalDelta > 0 else {
                previousCPUInfo = cpuInfo
                return 0
            }
            let usage = (1.0 - (idleDelta / totalDelta)) * 100.0
            previousCPUInfo = cpuInfo
            return min(max(usage, 0), 100)
        }

        previousCPUInfo = cpuInfo
        return ((user + system + nice) / total) * 100.0
    }

    private func memoryUsage() -> Double {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )

        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPointer in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, intPointer, &count)
            }
        }

        guard result == KERN_SUCCESS else { return 0 }

        let pageSize = Double(vm_kernel_page_size)
        let active = Double(stats.active_count) * pageSize
        let wired = Double(stats.wire_count) * pageSize
        let compressed = Double(stats.compressor_page_count) * pageSize
        let used = active + wired + compressed

        var physicalMemory: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        sysctlbyname("hw.memsize", &physicalMemory, &size, nil, 0)
        guard physicalMemory > 0 else { return 0 }

        return min((used / Double(physicalMemory)) * 100.0, 100.0)
    }

    private func diskUsage() -> Double {
        let path = NSHomeDirectory() as NSString
        guard let attributes = try? FileManager.default.attributesOfFileSystem(forPath: path as String),
              let total = attributes[.systemSize] as? NSNumber,
              let free = attributes[.systemFreeSize] as? NSNumber,
              total.doubleValue > 0 else {
            return 0
        }

        let used = total.doubleValue - free.doubleValue
        return min((used / total.doubleValue) * 100.0, 100.0)
    }
}
