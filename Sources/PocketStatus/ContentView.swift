import SwiftUI

private enum AppTab: Hashable {
    case home
    case storage
    case containers
}

struct ContentView: View {
    private static let defaultTailscaleURL = "https://your-server.tailnet.ts.net:9095"

    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("liveRefreshEnabled") private var isLiveEnabled = false

    @State private var selectedTab: AppTab = .home
    @State private var baseURL = KeychainStore.load(.baseURL) ?? Self.defaultTailscaleURL
    @State private var token = KeychainStore.load(.token) ?? ""
    @State private var status: ServerStatusResponse?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var lastUpdated: Date?
    @State private var showingSettings = false
    @State private var pendingAction: PendingDockerAction?
    @State private var activeContainerAction: String?
    @State private var actionError: String?
    @State private var activeServiceURL: IdentifiableURL?
    @State private var inspectedContainer: IdentifiableString?

    private let gridColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    private let shortcutColumns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
    ]

    var body: some View {
        TabView(selection: $selectedTab) {
            tabPage(title: "Pocket Server") {
                if let status {
                    headerBanner(status.system)
                    healthGrid(status)
                    shortcutsSection(containers: status.containers)
                } else if isLoading {
                    loadingState
                } else {
                    shortcutsSection(containers: [])
                    emptyState
                }
            }
            .tabItem {
                Label("Home", systemImage: "house.fill")
            }
            .tag(AppTab.home)

            tabPage(title: "Storage") {
                if let status {
                    disksSection(status.disks)
                    if let btrfs = status.btrfs {
                        btrfsPoolSection(btrfs)
                    }
                    if !status.blockDevices.isEmpty {
                        physicalDrivesSection(status.blockDevices)
                    }
                    if !status.btrfsTimers.isEmpty {
                        timersSection(status.btrfsTimers)
                    }
                } else if isLoading {
                    loadingState
                } else {
                    emptyState
                }
            }
            .tabItem {
                Label("Storage", systemImage: "internaldrive.fill")
            }
            .tag(AppTab.storage)

            tabPage(title: "Containers") {
                if let status {
                    containersSummaryBanner(status.containers)
                    containersSection(status.containers)
                } else if isLoading {
                    loadingState
                } else {
                    emptyState
                }
            }
            .tabItem {
                Label("Containers", systemImage: "shippingbox.fill")
            }
            .tag(AppTab.containers)
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .sheet(isPresented: $showingSettings) {
            SettingsSheet(
                baseURL: $baseURL,
                token: $token,
                onSave: {
                    KeychainStore.save(baseURL, for: .baseURL)
                    KeychainStore.save(token, for: .token)
                    Task { await refresh() }
                }
            )
        }
        .sheet(item: $activeServiceURL) { item in
            SafariView(url: item.url)
                .ignoresSafeArea()
        }
        .sheet(item: $inspectedContainer) { item in
            DockerLogsSheet(
                container: item.value,
                baseURL: baseURL,
                token: token
            )
        }
        .task {
            if token.isEmpty {
                showingSettings = true
            } else {
                await refresh()
            }
        }
        .task(id: LiveTaskKey(isEnabled: isLiveEnabled, isActive: scenePhase == .active, hasToken: !token.isEmpty)) {
            guard isLiveEnabled, scenePhase == .active, !token.isEmpty else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                if Task.isCancelled { break }
                await refresh(silent: true)
            }
        }
        .confirmationDialog(
            pendingAction.map { "\($0.action.label) \($0.container)?" } ?? "",
            isPresented: Binding(
                get: { pendingAction != nil },
                set: { if !$0 { pendingAction = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let pending = pendingAction {
                Button(
                    pending.action.label,
                    role: pending.action.isDestructive ? .destructive : nil
                ) {
                    Task { await runDockerAction(pending) }
                }
                Button("Cancel", role: .cancel) {}
            }
        } message: {
            if let pending = pendingAction {
                Text("This will run `docker \(pending.action.rawValue) \(pending.container)` on Fedora.")
            }
        }
        .alert(
            "Docker Error",
            isPresented: Binding(
                get: { actionError != nil },
                set: { if !$0 { actionError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionError ?? "")
        }
    }

    private func tabPage<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    content()
                }
                .padding()
            }
            .background {
                ZStack(alignment: .top) {
                    Color(.systemGroupedBackground)
                    RadialGradient(
                        colors: [Color.blue.opacity(0.14), Color.teal.opacity(0.06), .clear],
                        center: .topLeading,
                        startRadius: 20,
                        endRadius: 380
                    )
                }
                .ignoresSafeArea()
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        isLiveEnabled.toggle()
                    } label: {
                        Image(systemName: isLiveEnabled ? "dot.radiowaves.left.and.right" : "pause.circle")
                    }
                    .tint(isLiveEnabled ? .green : .secondary)
                    .accessibilityLabel(isLiveEnabled ? "Pause live refresh" : "Enable live refresh")

                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .refreshable {
                await refresh()
            }
        }
    }

    private var loadingState: some View {
        ProgressView("Connecting to Fedora...")
            .padding(.top, 60)
    }

    private func headerBanner(_ system: SystemStatus) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(system.hostname)
                    .font(.headline)
                Text(system.uptimePretty)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 5) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 7, height: 7)
                    Text(isLiveEnabled ? "Live · 4s" : "Online")
                        .font(.caption.weight(.semibold))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .glassEffect(.regular.tint(.green.opacity(0.2)), in: .capsule)

                if let lastUpdated {
                    Text(lastUpdated, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
    }

    private func healthGrid(_ status: ServerStatusResponse) -> some View {
        let cpuFooter = status.system.cpuTempC.map {
            "\(status.system.cpuCores) threads · \($0)°C"
        } ?? "\(status.system.cpuCores) threads"

        return LazyVGrid(columns: gridColumns, spacing: 12) {
            MetricCard(
                title: "CPU",
                icon: "cpu",
                tint: (status.system.cpuTempC ?? 0) >= 75 ? .orange : .blue,
                primary: "\(Int(status.system.cpuUsagePercent.rounded()))%",
                secondary: "Load \(status.system.loadAvg.map { String(format: "%.2f", $0) }.joined(separator: " · "))",
                footer: cpuFooter
            )

            MetricCard(
                title: "RAM + zRAM",
                icon: "memorychip",
                tint: .purple,
                primary: "\(Int(status.memory.ramUsageFraction * 100))%",
                secondary: "\(Formatters.bytes(status.memory.ramUsedBytes)) / \(Formatters.bytes(status.memory.ramTotalBytes))",
                footer: "Swap: \(Formatters.bytes(status.memory.swapUsedBytes))"
            )

            if let gpu = status.gpu {
                MetricCard(
                    title: "GTX 1050 Ti",
                    icon: "display",
                    tint: gpu.temperatureC >= 75 ? .orange : .green,
                    primary: "\(gpu.temperatureC)°C",
                    secondary: "Usage \(gpu.utilizationPercent)%",
                    footer: "VRAM \(gpu.memoryUsedMb)/\(gpu.memoryTotalMb) MB"
                )
            } else {
                MetricCard(
                    title: "GPU",
                    icon: "display",
                    tint: .gray,
                    primary: "N/A",
                    secondary: "nvidia-smi unavailable",
                    footer: ""
                )
            }

            let runningCount = status.containers.filter(\.isRunning).count
            Button {
                selectedTab = .containers
            } label: {
                MetricCard(
                    title: "Docker",
                    icon: "shippingbox",
                    tint: .teal,
                    primary: "\(runningCount)/\(status.containers.count)",
                    secondary: "Running containers",
                    footer: "View containers ›",
                    useGlassBackground: false
                )
                .glassEffect(
                    .regular.interactive(),
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func shortcutsSection(containers: [ContainerStatus]) -> some View {
        let runningByName = Dictionary(uniqueKeysWithValues: containers.map { ($0.name, $0.isRunning) })

        return VStack(alignment: .leading, spacing: 10) {
            Text("Quick Shortcuts")
                .font(.headline)

            GlassEffectContainer(spacing: 12) {
                LazyVGrid(columns: shortcutColumns, spacing: 10) {
                    ForEach(ServiceShortcut.all) { shortcut in
                        let targetURL = shortcut.url(from: baseURL)
                        let isRunning = runningByName[shortcut.containerName]

                        Button {
                            if let targetURL {
                                activeServiceURL = IdentifiableURL(url: targetURL)
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Image(systemName: shortcut.symbol)
                                        .font(.headline)
                                        .foregroundStyle(.blue)
                                    Spacer()
                                    if let isRunning {
                                        Circle()
                                            .fill(isRunning ? Color.green : Color.gray)
                                            .frame(width: 7, height: 7)
                                    }
                                }
                                Text(shortcut.name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text(":\(shortcut.port)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .glassEffect(
                                .regular.interactive(),
                                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(targetURL == nil)
                    }
                }
            }
        }
    }

    private func disksSection(_ disks: [DiskStatus]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Mounted Volumes")
                .font(.headline)

            ForEach(disks) { disk in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label(disk.mount, systemImage: "internaldrive")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("\(disk.fsType.uppercased()) · \(disk.usePercent)%")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(disk.usePercent >= 85 ? .orange : .secondary)
                    }
                    ProgressView(value: Double(disk.usePercent), total: 100)
                        .tint(disk.usePercent >= 85 ? .orange : .blue)
                    HStack {
                        Text("Used: \(Formatters.bytes(disk.usedBytes))")
                        Spacer()
                        Text("Free: \(Formatters.bytes(disk.availableBytes))")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    Text("Total capacity: \(Formatters.bytes(disk.totalBytes))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        }
    }

    private func btrfsPoolSection(_ pool: BtrfsPoolStatus) -> some View {
        let isHealthy = pool.deviceMissing == 0

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Btrfs Pool (/mnt/storage)")
                    .font(.headline)
                Spacer()
                Label(
                    isHealthy ? "Healthy" : "\(pool.deviceMissing) missing",
                    systemImage: isHealthy ? "checkmark.shield.fill" : "exclamationmark.triangle.fill"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(isHealthy ? .green : .red)
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Allocated space")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Text("\(Int(pool.allocatedFraction * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: pool.allocatedFraction)
                    .tint(.teal)

                LazyVGrid(columns: gridColumns, spacing: 10) {
                    StorageStatRow(title: "Allocated", value: Formatters.bytes(pool.allocatedBytes))
                    StorageStatRow(title: "Unallocated", value: Formatters.bytes(pool.unallocatedBytes))
                    StorageStatRow(title: "Data used", value: Formatters.bytes(pool.usedBytes))
                    StorageStatRow(title: "Est. free", value: Formatters.bytes(pool.freeEstimatedBytes))
                }

                Divider()

                HStack {
                    Text("Profiles: Data \(pool.dataProfile) · Metadata \(pool.metadataProfile)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    private func physicalDrivesSection(_ devices: [BlockDevice]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Physical Drives")
                .font(.headline)

            VStack(spacing: 0) {
                ForEach(Array(devices.enumerated()), id: \.element.id) { index, device in
                    HStack(spacing: 12) {
                        Image(systemName: device.isRotational ? "opticaldiscdrive" : "memorychip")
                            .font(.title3)
                            .foregroundStyle(device.isRotational ? .blue : .purple)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("/dev/\(device.name) · \(device.model)")
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            Text("\(device.mediaKind) · \(device.transport)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text(Formatters.bytes(device.sizeBytes))
                            .font(.subheadline.weight(.medium))
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 12)

                    if index < devices.count - 1 {
                        Divider().padding(.leading, 56)
                    }
                }
            }
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    private func timersSection(_ timers: [MaintenanceTimer]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Btrfs Maintenance")
                .font(.headline)

            VStack(spacing: 0) {
                ForEach(Array(timers.enumerated()), id: \.element.id) { index, timer in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(timer.name)
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(timer.activeState)
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(
                                    (timer.isActive ? Color.green : Color.orange).opacity(0.15),
                                    in: Capsule()
                                )
                                .foregroundStyle(timer.isActive ? .green : .orange)
                        }
                        Text("Next: \(timer.nextRun)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Last: \(timer.lastRun)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding()

                    if index < timers.count - 1 {
                        Divider().padding(.leading)
                    }
                }
            }
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    private func containersSummaryBanner(_ containers: [ContainerStatus]) -> some View {
        let runningCount = containers.filter(\.isRunning).count
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Label("\(runningCount) of \(containers.count) running", systemImage: "shippingbox.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.teal)
                Text("Tap a container to view logs")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let lastUpdated {
                Text(lastUpdated, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func containersSection(_ containers: [ContainerStatus]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(containers.enumerated()), id: \.element.id) { index, container in
                HStack(spacing: 12) {
                    Button {
                        inspectedContainer = IdentifiableString(value: container.name)
                    } label: {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(container.isRunning ? Color.green : Color.gray)
                                .frame(width: 10, height: 10)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 4) {
                                    Text(container.name)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Image(systemName: "chevron.right")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                }
                                Text(container.status)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if activeContainerAction == container.name {
                        ProgressView()
                            .controlSize(.small)
                    } else if container.controllable {
                        HStack(spacing: 8) {
                            if container.isRunning {
                                Button {
                                    pendingAction = PendingDockerAction(container: container.name, action: .restart)
                                } label: {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.subheadline.weight(.semibold))
                                }
                                .buttonStyle(.glass)
                                .tint(.blue)
                                .accessibilityLabel("Restart \(container.name)")

                                Button {
                                    pendingAction = PendingDockerAction(container: container.name, action: .stop)
                                } label: {
                                    Image(systemName: "stop.fill")
                                        .font(.subheadline.weight(.semibold))
                                }
                                .buttonStyle(.glass)
                                .tint(.red)
                                .accessibilityLabel("Stop \(container.name)")
                            } else {
                                Button {
                                    pendingAction = PendingDockerAction(container: container.name, action: .start)
                                } label: {
                                    Image(systemName: "play.fill")
                                        .font(.subheadline.weight(.semibold))
                                }
                                .buttonStyle(.glassProminent)
                                .tint(.green)
                                .accessibilityLabel("Start \(container.name)")
                            }
                        }
                    } else {
                        Text("Protected")
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.gray.opacity(0.15), in: Capsule())
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 10)

                if index < containers.count - 1 {
                    Divider().padding(.leading, 36)
                }
            }
        }
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "server.rack")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            if let errorMessage {
                Text(errorMessage)
                    .font(.subheadline)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            } else {
                Text("No server data yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                Button("Retry") {
                    Task { await refresh() }
                }
                .buttonStyle(.glassProminent)

                Button("Settings") {
                    showingSettings = true
                }
                .buttonStyle(.glass)
            }
        }
        .padding(.top, 56)
    }

    @MainActor
    private func refresh(silent: Bool = false) async {
        if !silent {
            isLoading = true
        }
        defer {
            if !silent {
                isLoading = false
            }
        }
        do {
            let result = try await APIClient.fetchStatus(baseURL: baseURL, token: token)
            status = result
            errorMessage = nil
            lastUpdated = Date()
        } catch {
            if !silent || status == nil {
                errorMessage = error.localizedDescription
            }
        }
    }

    @MainActor
    private func runDockerAction(_ pending: PendingDockerAction) async {
        activeContainerAction = pending.container
        defer { activeContainerAction = nil }
        do {
            _ = try await APIClient.performDockerAction(
                baseURL: baseURL,
                token: token,
                container: pending.container,
                action: pending.action
            )
            await refresh()
        } catch {
            actionError = error.localizedDescription
        }
    }
}

private struct MetricCard: View {
    let title: String
    let icon: String
    let tint: Color
    let primary: String
    let secondary: String
    let footer: String
    var useGlassBackground: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
            Text(primary)
                .font(.title2.bold())
            Text(secondary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if !footer.isEmpty {
                Text(footer)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background {
            if useGlassBackground {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            }
        }
    }
}

private struct StorageStatRow: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var baseURL: String
    @Binding var token: String
    let onSave: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Server") {
                    TextField("Base URL", text: $baseURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)

                    Button("Use Tailscale HTTPS template") {
                        baseURL = "https://your-server.tailnet.ts.net:9095"
                    }
                    Button("Use LAN template") {
                        baseURL = "http://192.168.1.100:9095"
                    }
                }

                Section("Authentication") {
                    SecureField("Bearer Token", text: $token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave()
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct PendingDockerAction: Equatable {
    let container: String
    let action: DockerAction
}

private struct IdentifiableURL: Identifiable {
    let id = UUID()
    let url: URL
}

private struct IdentifiableString: Identifiable {
    let id = UUID()
    let value: String
}

private struct LiveTaskKey: Equatable {
    let isEnabled: Bool
    let isActive: Bool
    let hasToken: Bool
}

private struct DockerLogsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let container: String
    let baseURL: String
    let token: String

    @State private var logs = ""
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && logs.isEmpty {
                    ProgressView("Loading \(container) logs...")
                } else if let errorMessage, logs.isEmpty {
                    ContentUnavailableView(
                        "Failed to load logs",
                        systemImage: "exclamationmark.triangle",
                        description: Text(errorMessage)
                    )
                } else if logs.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ContentUnavailableView(
                        "No recent logs",
                        systemImage: "doc.text",
                        description: Text("This container has no recent log output.")
                    )
                } else {
                    ScrollView {
                        Text(logs)
                            .font(.system(.caption2, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding()
                    }
                    .defaultScrollAnchor(.bottom)
                }
            }
            .navigationTitle(container)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        UIPasteboard.general.string = logs
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .disabled(logs.isEmpty)

                    Button {
                        Task { await loadLogs() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isLoading)
                }
            }
            .task {
                await loadLogs()
            }
        }
    }

    @MainActor
    private func loadLogs() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await APIClient.fetchDockerLogs(
                baseURL: baseURL,
                token: token,
                container: container
            )
            logs = response.logs
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
