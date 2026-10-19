import Foundation
import IOKit

/// Apple SMC에서 온도·팬을 읽는다 (비공개 인터페이스 — macOS 업데이트로 깨질 수 있으며, 실패하면 nil).
/// Apple Silicon에는 CPU 온도 공개 API가 없다. HID 온도 센서 경로는 macOS 26에서 값이 오지 않아 SMC를 쓴다.
final class SMC {
    static let shared = SMC()

    struct Fan {
        let current: Double
        let min: Double
        let max: Double
    }

    private var connection: io_connect_t = 0
    /// 처음 한 번 찾아 둔 CPU 코어 온도 키
    ///   M1~M3: Tp…(성능 코어) + Te0…(효율 코어)
    ///   M4: Tf0… + Te0… — M4에도 Tp… 키가 있지만 40.0 고정값·보정값이라 쓰지 않는다 (M4 Max에서 확인)
    private lazy var cpuKeys: [UInt32] = discoverCPUKeys()
    private let lock = NSLock()

    private init() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }
        if IOServiceOpen(service, mach_task_self_, 0, &connection) != KERN_SUCCESS { connection = 0 }
    }

    /// CPU 코어 센서들의 중앙값 (튀는 센서가 결과를 흔들지 않도록)
    func cpuTemperature() -> Double? {
        lock.lock(); defer { lock.unlock() }
        guard connection != 0 else { return nil }
        let values = cpuKeys.compactMap { readFloat($0) }.filter { $0 > 20 && $0 < 130 }.sorted()
        guard !values.isEmpty else { return nil }
        let mid = values.count / 2
        return values.count % 2 == 1 ? Double(values[mid]) : Double(values[mid - 1] + values[mid]) / 2
    }

    func fans() -> [Fan] {
        lock.lock(); defer { lock.unlock() }
        guard connection != 0, let count = readBytes(fourCC("FNum"))?.bytes.first, count > 0 else { return [] }
        return (0..<Int(count)).compactMap { i in
            guard let current = readFloat(fourCC("F\(i)Ac")) else { return nil }
            return Fan(current: Double(current),
                       min: Double(readFloat(fourCC("F\(i)Mn")) ?? 0),
                       max: Double(readFloat(fourCC("F\(i)Mx")) ?? 0))
        }
    }

    // MARK: - 키 찾기

    private func discoverCPUKeys() -> [UInt32] {
        guard connection != 0, let countBytes = readBytes(fourCC("#KEY"))?.bytes else { return [] }
        let count = countBytes.reduce(0) { $0 << 8 | UInt32($1) }
        var found: [String: UInt32] = [:]
        for index in 0..<count {
            guard let key = keyAt(index) else { continue }
            let name = string(key)
            // Tex…는 Te0…와 같은 값이 중복으로 나온다
            guard name.hasPrefix("Tp") || name.hasPrefix("Te0") || name.hasPrefix("Tf0") else { continue }
            if let info = keyInfo(key), info.type == fourCC("flt "), info.size == 4 { found[name] = key }
        }
        let isM4Style = found.keys.contains { $0.hasPrefix("Tf0") }
        return found.filter { name, _ in
            name.hasPrefix("Te0") || (isM4Style ? name.hasPrefix("Tf0") : name.hasPrefix("Tp"))
        }
        .sorted { $0.key < $1.key }.map(\.value)
    }

    // MARK: - SMC 프로토콜 (IOConnectCallStructMethod selector 2, 80바이트 구조체)

    private struct KeyData {
        struct Vers { var major: UInt8 = 0, minor: UInt8 = 0, build: UInt8 = 0, reserved: UInt8 = 0, release: UInt16 = 0 }
        struct LimitData { var version: UInt16 = 0, length: UInt16 = 0, cpu: UInt32 = 0, gpu: UInt32 = 0, mem: UInt32 = 0 }
        struct KeyInfo { var dataSize: UInt32 = 0, dataType: UInt32 = 0, dataAttributes: UInt8 = 0 }
        var key: UInt32 = 0
        var vers = Vers()
        var limitData = LimitData()
        var keyInfo = KeyInfo()
        var padding: UInt16 = 0
        var result: UInt8 = 0
        var status: UInt8 = 0
        var command: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) =
            (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    }

    private enum Command: UInt8 { case readBytes = 5, keyAtIndex = 8, keyInfo = 9 }

    private func call(_ input: inout KeyData) -> KeyData? {
        var output = KeyData()
        var size = MemoryLayout<KeyData>.stride
        let result = IOConnectCallStructMethod(connection, 2, &input, MemoryLayout<KeyData>.stride, &output, &size)
        return result == KERN_SUCCESS && output.result == 0 ? output : nil
    }

    private func keyInfo(_ key: UInt32) -> (size: UInt32, type: UInt32)? {
        var input = KeyData()
        input.key = key
        input.command = Command.keyInfo.rawValue
        return call(&input).map { ($0.keyInfo.dataSize, $0.keyInfo.dataType) }
    }

    private func readBytes(_ key: UInt32) -> (type: UInt32, bytes: [UInt8])? {
        guard let info = keyInfo(key) else { return nil }
        var input = KeyData()
        input.key = key
        input.keyInfo.dataSize = info.size
        input.command = Command.readBytes.rawValue
        guard let output = call(&input) else { return nil }
        let all = withUnsafeBytes(of: output.bytes) { Array($0) }
        return (info.type, Array(all.prefix(Int(min(info.size, 32)))))
    }

    private func readFloat(_ key: UInt32) -> Float? {
        guard let value = readBytes(key), value.type == fourCC("flt "), value.bytes.count == 4 else { return nil }
        return value.bytes.withUnsafeBytes { $0.load(as: Float.self) }
    }

    private func keyAt(_ index: UInt32) -> UInt32? {
        var input = KeyData()
        input.command = Command.keyAtIndex.rawValue
        input.data32 = index
        return call(&input)?.key
    }

    private func fourCC(_ s: String) -> UInt32 { s.utf8.reduce(0) { $0 << 8 | UInt32($1) } }

    private func string(_ v: UInt32) -> String {
        String(bytes: [UInt8(v >> 24), UInt8(v >> 16 & 0xff), UInt8(v >> 8 & 0xff), UInt8(v & 0xff)], encoding: .ascii) ?? ""
    }
}
