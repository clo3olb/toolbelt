import AppKit

/// 연결된 디스크(볼륨) 하나
struct StorageVolume: Identifiable, Equatable {
    let url: URL
    let name: String
    let total: Int64
    let available: Int64
    let isInternal: Bool
    let isEjectable: Bool
    let isRoot: Bool
    let format: String

    var id: String { url.path }
    var used: Int64 { max(total - available, 0) }
    var ratio: Double { total > 0 ? Double(used) / Double(total) : 0 }
    var symbol: String { isInternal ? "internaldrive" : "externaldrive" }
}

/// 내장·외장 디스크 목록과 꺼내기.
enum StorageDevices {
    private static let keys: [URLResourceKey] = [
        .volumeNameKey, .volumeLocalizedNameKey, .volumeTotalCapacityKey,
        .volumeAvailableCapacityKey, .volumeAvailableCapacityForImportantUsageKey,
        .volumeIsInternalKey, .volumeIsEjectableKey, .volumeIsRemovableKey,
        .volumeIsRootFileSystemKey, .volumeIsLocalKey, .volumeIsBrowsableKey,
        .volumeLocalizedFormatDescriptionKey,
    ]

    /// Finder에 보이는 로컬 볼륨. 시동 디스크가 맨 앞, 나머지는 이름순.
    static func volumes() -> [StorageVolume] {
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys,
                                                         options: [.skipHiddenVolumes]) ?? []
        return urls.compactMap { url -> StorageVolume? in
            guard let v = try? url.resourceValues(forKeys: Set(keys)),
                  v.volumeIsBrowsable ?? true, v.volumeIsLocal ?? true,
                  let total = v.volumeTotalCapacity, total > 0 else { return nil }
            let isRoot = v.volumeIsRootFileSystem ?? false
            // 시동 디스크는 Finder와 같은 "중요한 용도" 기준(정리 가능한 공간 포함), 외장은 일반 남은 용량
            let available = isRoot
                ? (v.volumeAvailableCapacityForImportantUsage ?? Int64(v.volumeAvailableCapacity ?? 0))
                : Int64(v.volumeAvailableCapacity ?? 0)
            return StorageVolume(url: url,
                                 name: v.volumeLocalizedName ?? v.volumeName ?? url.lastPathComponent,
                                 total: Int64(total),
                                 available: available,
                                 isInternal: v.volumeIsInternal ?? false,
                                 isEjectable: (v.volumeIsEjectable ?? false) || (v.volumeIsRemovable ?? false) || !(v.volumeIsInternal ?? true),
                                 isRoot: isRoot,
                                 format: v.volumeLocalizedFormatDescription ?? "")
        }
        .sorted { a, b in
            if a.isRoot != b.isRoot { return a.isRoot }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    /// 꺼내기. 사용 중이면 실패 메시지를 돌려준다.
    static func eject(_ volume: StorageVolume) -> String? {
        do {
            try NSWorkspace.shared.unmountAndEjectDevice(at: volume.url)
            return nil
        } catch {
            return "\(volume.name)을(를) 꺼내지 못했습니다. 사용 중인 앱이나 열린 파일이 있는지 확인하세요.\n(\(error.localizedDescription))"
        }
    }

    static func reveal(_ volume: StorageVolume) {
        NSWorkspace.shared.open(volume.url)
    }

    /// 1000 기준 (Finder와 같음). 100 GB 이상은 소수점 없이, 1 TB 이상은 TB.
    static func format(_ bytes: Int64) -> String {
        let value = Double(bytes)
        if value >= 1e12 { return String(format: value >= 1e14 ? "%.0f TB" : "%.2f TB", value / 1e12) }
        let gb = value / 1e9
        return gb >= 100 ? String(format: "%.0f GB", gb) : String(format: "%.1f GB", gb)
    }
}
