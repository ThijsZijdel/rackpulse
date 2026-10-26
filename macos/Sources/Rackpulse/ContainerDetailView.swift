import Charts
import HetznerKit
import SwiftUI

struct ContainerDetailView: View {
    let server: Server
    let project: Project
    let monitor: Monitor
    let name: String
    let back: () -> Void

    @State private var range = ContainerRange.day
    @State private var history: ContainerHistory?
    @State private var failed = false
    @State private var hover: Date?

    private var container: AgentSnapshot.Container? {
        monitor.agents.state(project.id, server.id)?.snapshot?.docker?.containers.first { $0.name == name }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if let container {
                resources(container)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                SectionHeader("Activity").padding(.top, 18)
                SegmentedControl(selection: $range, options: ContainerRange.allCases.map { ($0, $0.rawValue) })
                    .padding(.horizontal, 16)
                    .padding(.top, 2)
                VStack(spacing: 14) {
                    chart("CPU", icon: "cpu", points: cpuPoints, format: { Format.cpu($0) }, domain: nil)
                    chart("Memory", icon: "memorychip", points: memoryPoints, format: { Format.memory(Int64($0 ?? 0)) }, domain: nil)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)

                lists(container)
            } else {
                Text("This container no longer exists on \(server.name).")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondary)
                    .padding(16)
            }
            Color.clear.frame(height: 14)
        }
        .onExitCommand(perform: back)
        .task(id: range) { await load() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button(action: back) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 7))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back to \(server.name)")
            .keyboardShortcut("[", modifiers: .command)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Circle().fill(container.map { ContainerRow.describe($0).0 } ?? Theme.off).frame(width: 8, height: 8)
                    Text(name).font(.system(size: 14, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                    if let health = container?.health { HealthBadge(health: health) }
                }
                Text(container.map { "\($0.image) · \(server.name)" } ?? server.name)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
    }

    private var snapshot: AgentSnapshot? {
        monitor.agents.state(project.id, server.id)?.snapshot
    }

    private func resources(_ container: AgentSnapshot.Container) -> some View {
        let share = ContainerRow.memoryShare(container, hostMemory: snapshot?.memory.total ?? 0)
        let cpu = container.cpu ?? 0
        return VStack(spacing: 0) {
            meterRow(icon: "cpu", tint: .blue, title: "CPU", value: Format.cpu(container.cpu),
                     detail: "of the whole server", fraction: container.isRunning ? cpu / 100 : nil, divider: true)
            meterRow(icon: "memorychip", tint: .purple, title: "Memory", value: container.memory.map { Format.memory($0) } ?? "-",
                     detail: share?.of ?? "", fraction: container.isRunning ? share?.fraction : nil, divider: false)
        }
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 9))
    }

    private func meterRow(icon: String, tint: Color, title: String, value: String, detail: String, fraction: Double?, divider: Bool) -> some View {
        HStack(spacing: 10) {
            IconTile(symbol: icon, tint: tint)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title).font(.system(size: 12, weight: .semibold))
                    Spacer(minLength: 6)
                    Text(value).font(.system(size: 13, weight: .semibold)).rolling(value)
                    Text(detail).font(.system(size: 11)).foregroundStyle(Theme.secondary)
                }
                if let fraction {
                    UsageBar(fraction: fraction, color: UsageBar.color(fraction))
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) {
            if divider { Theme.divider.frame(height: 1).padding(.leading, 44).padding(.trailing, 10) }
        }
    }

    @ViewBuilder
    private func lists(_ container: AgentSnapshot.Container) -> some View {
        let (color, status) = ContainerRow.describe(container)
        SectionHeader("Container").padding(.top, 20)
        InfoList {
            InfoRow(symbol: "power", tint: color == Theme.green ? .green : color == Theme.off ? .gray : .orange,
                    title: "Status", value: status,
                    detail: container.startedAt.map { "Started \($0.formatted(date: .abbreviated, time: .shortened))" })
            if let health = container.health {
                InfoRow(symbol: "heart.text.square", tint: health == "healthy" ? .green : health == "unhealthy" ? .red : .orange,
                        title: "Health", value: health.capitalized,
                        detail: container.healthLog.flatMap { log in log.time.map { "Checked \(Format.compactDuration(since: $0)) ago" } })
            }
            InfoRow(symbol: "arrow.clockwise", tint: container.isRestartLoop ? .orange : .teal, title: "Restarts",
                    value: container.restartCount == 0 ? "None" : "\(container.restartCount)",
                    detail: container.restartsLastHour > 0 ? "\(container.restartsLastHour) in the last hour" : nil)
            if container.state != "running", container.finishedAt != nil {
                InfoRow(symbol: "xmark.octagon", tint: Self.cleanExit(container) ? .gray : .red, title: "Exit code",
                        value: "\(container.exitCode)", detail: Self.cleanExit(container) ? "Stopped normally" : "Stopped with an error")
            }
            InfoRow(symbol: "shippingbox", tint: .brown, title: "Image", value: ContainerRow.shortImage(container.image),
                    detail: container.image.contains("/") ? container.image : nil)
            if let project = container.project {
                InfoRow(symbol: "square.stack.3d.up", tint: .indigo, title: "Compose project", value: project)
            }
            if let created = container.createdAt {
                InfoRow(symbol: "calendar", tint: .gray, title: "Created", value: "\(Format.compactDuration(since: created)) ago",
                        detail: created.formatted(date: .abbreviated, time: .shortened))
            }
        }

        if container.ports == nil {
            AgentNotice(kind: .info, text: "Update the agent to 0.1.1 or later to see ports, volumes, networks and history for each container.")
                .padding(.horizontal, 16)
                .padding(.top, 14)
        } else {
            network(container)
            storage(container)
        }

        if let log = container.healthLog, !log.output.isEmpty {
            SectionHeader("Last health check").padding(.top, 20)
            VStack(alignment: .leading, spacing: 6) {
                Label(log.exitCode == 0 ? "Passed" : "Failed with code \(log.exitCode)",
                      systemImage: log.exitCode == 0 ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(log.exitCode == 0 ? Theme.green : Theme.red)
                Text(log.output)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 9))
            .padding(.horizontal, 16)
        }
    }

    @ViewBuilder
    private func network(_ container: AgentSnapshot.Container) -> some View {
        let ports = container.ports ?? []
        let networks = container.networks ?? []
        if !ports.isEmpty || !networks.isEmpty {
            SectionHeader("Network").padding(.top, 20)
            InfoList {
                ForEach(Array(ports.enumerated()), id: \.offset) { _, port in
                    let reach = Self.reach(port)
                    InfoRow(symbol: reach.symbol, tint: reach.tint, title: port.public.map { "\($0) → \(port.private)/\(port.type)" } ?? "\(port.private)/\(port.type)",
                            value: reach.text, detail: port.ip.flatMap { $0 == "0.0.0.0" || $0 == "::" ? nil : "Bound to \($0)" }, monospaced: true)
                }
                ForEach(networks, id: \.self) { name in
                    InfoRow(symbol: "point.3.connected.trianglepath.dotted", tint: .cyan, title: name, value: "Network")
                }
            }
        }
    }

    @ViewBuilder
    private func storage(_ container: AgentSnapshot.Container) -> some View {
        let mounts = container.mounts ?? []
        if !mounts.isEmpty {
            let sizes = Dictionary((snapshot?.docker?.volumes ?? []).map { ($0.name, $0.size) }, uniquingKeysWith: { first, _ in first })
            SectionHeader("Storage").padding(.top, 20)
            InfoList {
                ForEach(Array(mounts.enumerated()), id: \.offset) { _, mount in
                    let size = mount.name.flatMap { sizes[$0] }
                    InfoRow(
                        symbol: mount.type == "volume" ? "cylinder" : mount.type == "tmpfs" ? "memorychip" : "folder",
                        tint: mount.type == "volume" ? .orange : mount.type == "tmpfs" ? .purple : .blue,
                        title: mount.destination,
                        value: size.map { $0 >= 0 ? Format.size($0) : "Size unknown" } ?? Self.kind(mount),
                        detail: [mount.name ?? mount.source, mount.readOnly == true ? "read-only" : nil].compactMap { $0 }.joined(separator: " · "),
                        monospaced: true
                    )
                }
            }
            if mounts.contains(where: { $0.type == "bind" }) {
                Text("Docker measures the size of volumes only. Bind mounts are folders on the server; their space counts toward the server's disk.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
            }
        }
    }

    private static func kind(_ mount: AgentSnapshot.Container.Mount) -> String {
        switch mount.type {
        case "bind": "Bind mount"
        case "tmpfs": "In memory"
        case "volume": "Volume"
        default: mount.type.capitalized
        }
    }

    private static func reach(_ port: AgentSnapshot.Container.Port) -> (symbol: String, tint: Color, text: String) {
        guard port.public != nil else { return ("shippingbox", .gray, "Inside Docker") }
        if let ip = port.ip, ip.hasPrefix("127.") || ip == "::1" { return ("lock", .green, "This server only") }
        return ("globe", .orange, "Open to the network")
    }

    private static func cleanExit(_ container: AgentSnapshot.Container) -> Bool {
        AgentSnapshot.Container.stopSignals.contains(container.exitCode)
    }

    private var cpuPoints: [MetricPoint] {
        (history?.samples ?? []).compactMap { sample in sample.cpu.map { MetricPoint(time: sample.t, value: $0) } }
    }

    private var memoryPoints: [MetricPoint] {
        (history?.samples ?? []).compactMap { sample in sample.memory.map { MetricPoint(time: sample.t, value: Double($0)) } }
    }

    private func chart(_ title: String, icon: String, points: [MetricPoint], format: @escaping (Double?) -> String, domain: ClosedRange<Double>?) -> some View {
        let picked = hover.flatMap { date in points.min { abs($0.time.timeIntervalSince(date)) < abs($1.time.timeIntervalSince(date)) } }
        let end = Date.now
        let start = end.addingTimeInterval(-range.seconds)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: icon).foregroundStyle(Theme.secondary).frame(width: 14)
                Text(title)
                Spacer()
                if let picked {
                    Text("\(format(picked.value)) at \(picked.time.formatted(.dateTime.hour().minute()))").fontWeight(.semibold)
                } else if let last = points.last {
                    Text("\(format(last.value)) now · peak \(format(points.map(\.value).max()))").fontWeight(.semibold)
                }
            }
            .font(.system(size: 12))
            ZStack {
                if points.isEmpty {
                    Text(placeholder).font(.system(size: 11)).foregroundStyle(Theme.secondary)
                } else {
                    Chart {
                        ForEach(points, id: \.time) { point in
                            AreaMark(x: .value("Time", point.time), y: .value(title, point.value))
                                .foregroundStyle(Color.accentColor.opacity(0.12))
                            LineMark(x: .value("Time", point.time), y: .value(title, point.value))
                                .foregroundStyle(Color.accentColor)
                                .lineStyle(StrokeStyle(lineWidth: 1.5))
                        }
                        if let picked {
                            RuleMark(x: .value("Time", picked.time)).foregroundStyle(Theme.secondary.opacity(0.5))
                        }
                    }
                    .chartXSelection(value: $hover)
                    .chartXScale(domain: start...end)
                    .chartYScale(domain: domain ?? 0...max(1, (points.map(\.value).max() ?? 1) * 1.15))
                    .chartYAxis {
                        AxisMarks(position: .leading, values: .automatic(desiredCount: 2)) { value in
                            AxisGridLine()
                            AxisValueLabel { Text(format(value.as(Double.self))) }
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: [0.15, 0.5, 0.85].map { start.addingTimeInterval(range.seconds * $0) }) { _ in
                            AxisValueLabel(format: range == .week ? .dateTime.month(.abbreviated).day() : .dateTime.hour().minute(), anchor: .top)
                        }
                    }
                }
            }
            .frame(height: 64)
        }
    }

    private var placeholder: String {
        if failed { return "History needs agent 0.1.1 or later." }
        return history == nil ? "Loading…" : "No data for this period yet."
    }

    private func load() async {
        guard let result = await monitor.agents.containerHistory(project.id, server.id, name: name, since: .now.addingTimeInterval(-range.seconds)) else {
            failed = true
            return
        }
        failed = false
        history = result
    }
}
