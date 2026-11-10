import Foundation

struct ServerStatusResponse: Decodable, Sendable {
    let system: SystemStatus
    let memory: MemoryStatus
    let gpu: GpuStatus?
    let disks: [DiskStatus]
    let blockDevices: [BlockDevice]
    let btrfs: BtrfsPoolStatus?
    let btrfsTimers: [MaintenanceTimer]
    let containers: [ContainerStatus]

    enum CodingKeys: String, CodingKey {
        case system, memory, gpu, disks, btrfs, containers
        case blockDevices = "block_devices"
        case btrfsTimers = "btrfs_timers"
    }
}

struct SystemStatus: Decodable, Sendable {
    let hostname: String
    let uptimeSeconds: UInt64
    let uptimePretty: String
    let loadAvg: [Double]
    let cpuCores: Int
    let cpuUsagePercent: Double
    let cpuTempC: UInt32?

    enum CodingKeys: String, CodingKey {
        case hostname
        case uptimeSeconds = "uptime_seconds"
        case uptimePretty = "uptime_pretty"
        case loadAvg = "load_avg"
        case cpuCores = "cpu_cores"
        case cpuUsagePercent = "cpu_usage_percent"
        case cpuTempC = "cpu_temp_c"
    }
}

struct MemoryStatus: Decodable, Sendable {
    let ramTotalBytes: UInt64
    let ramUsedBytes: UInt64
    let ramAvailableBytes: UInt64
    let swapTotalBytes: UInt64
    let swapUsedBytes: UInt64

    enum CodingKeys: String, CodingKey {
        case ramTotalBytes = "ram_total_bytes"
        case ramUsedBytes = "ram_used_bytes"
        case ramAvailableBytes = "ram_available_bytes"
        case swapTotalBytes = "swap_total_bytes"
        case swapUsedBytes = "swap_used_bytes"
    }

    var ramUsageFraction: Double {
        guard ramTotalBytes > 0 else { return 0 }
        return Double(ramUsedBytes) / Double(ramTotalBytes)
    }
}

struct GpuStatus: Decodable, Sendable {
    let name: String
    let temperatureC: UInt32
    let utilizationPercent: UInt32
    let memoryUsedMb: UInt64
    let memoryTotalMb: UInt64

    enum CodingKeys: String, CodingKey {
        case name
        case temperatureC = "temperature_c"
        case utilizationPercent = "utilization_percent"
        case memoryUsedMb = "memory_used_mb"
        case memoryTotalMb = "memory_total_mb"
    }
}

struct DiskStatus: Decodable, Sendable, Identifiable {
    let mount: String
    let fsType: String
    let totalBytes: UInt64
    let usedBytes: UInt64
    let availableBytes: UInt64
    let usePercent: UInt8

    var id: String { mount }

    enum CodingKeys: String, CodingKey {
        case mount
        case fsType = "fs_type"
        case totalBytes = "total_bytes"
        case usedBytes = "used_bytes"
        case availableBytes = "available_bytes"
        case usePercent = "use_percent"
    }
}

struct BlockDevice: Decodable, Sendable, Identifiable {
    let name: String
    let model: String
    let sizeBytes: UInt64
    let isRotational: Bool
    let transport: String

    var id: String { name }
    var mediaKind: String { isRotational ? "HDD" : "SSD" }

    enum CodingKeys: String, CodingKey {
        case name, model, transport
        case sizeBytes = "size_bytes"
        case isRotational = "is_rotational"
    }
}

struct BtrfsPoolStatus: Decodable, Sendable {
    let deviceSizeBytes: UInt64
    let allocatedBytes: UInt64
    let unallocatedBytes: UInt64
    let usedBytes: UInt64
    let freeEstimatedBytes: UInt64
    let deviceMissing: UInt64
    let dataProfile: String
    let metadataProfile: String

    enum CodingKeys: String, CodingKey {
        case deviceSizeBytes = "device_size_bytes"
        case allocatedBytes = "allocated_bytes"
        case unallocatedBytes = "unallocated_bytes"
        case usedBytes = "used_bytes"
        case freeEstimatedBytes = "free_estimated_bytes"
        case deviceMissing = "device_missing"
        case dataProfile = "data_profile"
        case metadataProfile = "metadata_profile"
    }

    var allocatedFraction: Double {
        guard deviceSizeBytes > 0 else { return 0 }
        return Double(allocatedBytes) / Double(deviceSizeBytes)
    }
}

struct MaintenanceTimer: Decodable, Sendable, Identifiable {
    let name: String
    let activeState: String
    let nextRun: String
    let lastRun: String

    var id: String { name }
    var isActive: Bool { activeState == "active" }

    enum CodingKeys: String, CodingKey {
        case name
        case activeState = "active_state"
        case nextRun = "next_run"
        case lastRun = "last_run"
    }
}

struct ContainerStatus: Decodable, Sendable, Identifiable {
    let name: String
    let state: String
    let status: String
    let image: String
    let controllable: Bool

    var id: String { name }
    var isRunning: Bool { state.lowercased() == "running" }
}

enum DockerAction: String, Sendable {
    case start
    case stop
    case restart

    var label: String {
        switch self {
        case .start: "Start"
        case .stop: "Stop"
        case .restart: "Restart"
        }
    }

    var isDestructive: Bool {
        self == .stop
    }
}

struct DockerActionResponse: Decodable, Sendable {
    let container: String
    let action: String
    let ok: Bool
}

struct DockerLogsResponse: Decodable, Sendable {
    let container: String
    let logs: String
}

struct ServiceShortcut: Identifiable, Sendable {
    let id: String
    let name: String
    let port: Int
    let symbol: String
    let containerName: String

    static let all: [ServiceShortcut] = [
        ServiceShortcut(id: "kavita", name: "Kavita", port: 5000, symbol: "book.closed.fill", containerName: "kavita"),
        ServiceShortcut(id: "qbittorrent", name: "qBittorrent", port: 8080, symbol: "arrow.down.circle.fill", containerName: "qbittorrent"),
        ServiceShortcut(id: "jellyfin", name: "Jellyfin", port: 8096, symbol: "play.tv.fill", containerName: "jellyfin"),
        ServiceShortcut(id: "suwayomi", name: "Suwayomi", port: 4567, symbol: "books.vertical.fill", containerName: "suwayomi"),
        ServiceShortcut(id: "adguard", name: "AdGuard", port: 8085, symbol: "shield.lefthalf.filled", containerName: "adguard"),
        ServiceShortcut(id: "homepage", name: "Homepage", port: 3000, symbol: "square.grid.2x2.fill", containerName: "homepage"),
    ]

    func url(from baseURL: String) -> URL? {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              let scheme = components.scheme, !scheme.isEmpty,
              let host = components.host, !host.isEmpty else {
            return nil
        }
        components.port = port
        components.path = ""
        components.query = nil
        components.fragment = nil
        return components.url
    }
}

enum Formatters {
    static func bytes(_ value: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useTB, .useMB]
        formatter.countStyle = .binary
        formatter.includesUnit = true
        return formatter.string(fromByteCount: Int64(clamping: value))
    }
}

