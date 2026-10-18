import AppKit
import Darwin

/// CPU·메모리·저장 공간 사용량 측정.
enum SystemStats {
    // MARK: - CPU

    private static var lastTicks: (busy: UInt64, total: UInt64)?

    /// 직전 호출 이후 전체 CPU 사용률(0~1). 첫 호출은 비교 대상이 없어 nil.
    static func cpuUsage() -> Double? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        let user = UInt64(info.cpu_ticks.0), system = UInt64(info.cpu_ticks.1)
        let idle = UInt64(info.cpu_ticks.2), nice = UInt64(info.cpu_ticks.3)
        let now = (busy: user + system + nice, total: user + system + idle + nice)
        defer { lastTicks = now }
        guard let last = lastTicks, now.total > last.total else { return nil }
        return Double(now.busy - last.busy) / Double(now.total - last.total)
    }

    // MARK: - 메모리

    /// 활성 상태 보기의 "사용된 메모리"와 같은 기준: 앱 메모리 + 와이어드 + 압축됨.
    static func memory() -> (used: UInt64, total: UInt64)? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        let page = UInt64(vm_kernel_page_size)
        let app = UInt64(stats.internal_page_count) - UInt64(stats.purgeable_count)
        let used = (app + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * page
        return (used, ProcessInfo.processInfo.physicalMemory)
    }

    // MARK: - 저장 공간

    /// 시동 디스크 기준. 사용 가능 용량은 Finder와 같은 "중요한 용도" 기준(정리 가능한 공간 포함).
    static func storage() -> (used: Int64, total: Int64)? {
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        guard let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity,
              let available = values.volumeAvailableCapacityForImportantUsage else { return nil }
        return (Int64(total) - available, Int64(total))
    }

    // MARK: - 활성 상태 보기

    static func openActivityMonitor() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.ActivityMonitor") else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}
