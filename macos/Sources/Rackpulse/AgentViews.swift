import AppKit
import HetznerKit
import SwiftUI

struct AgentSetupView: View {
    let server: Server
    let project: Project
    let monitor: Monitor
    let firewalls: [Int64: String]
    let back: () -> Void

    @State private var address: AgentAddress = .publicIPv4
    @State private var custom = ""
    @State private var port = String(AgentEndpoint.defaultPort)
    @State private var copied: String?
    @State private var tries = 0

    private var store: AgentStore { monitor.agents }
    private var link: AgentLink? { store.link(project.id, server.id) }
    private var state: AgentState? { store.state(project.id, server.id) }
    private var portNumber: Int { Int(port).flatMap { (1...65_535).contains($0) ? $0 : nil } ?? AgentEndpoint.defaultPort }
    private var host: String { address == .custom ? custom.trimmingCharacters(in: .whitespaces) : address.host(for: server) ?? "" }
    private var addresses: [AgentAddress] { AgentAddress.allCases.filter { $0 == .custom || $0.host(for: server) != nil } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Text("Rackpulse works without the agent. Install it on this server to also see memory, disk space, Docker containers, and 30 days of uptime recorded on the server.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
                .padding(.top, 10)

            SectionHeader("How it works").padding(.top, 16)
            facts.padding(.horizontal, 16)

            if link?.isPaired == true {
                SectionHeader("Status").padding(.top, 18)
                status.padding(.horizontal, 16)
                SectionHeader("Key").padding(.top, 18)
                keyStep.padding(.horizontal, 16)
                if let version = link?.version, version.compare(AgentStore.latestVersion, options: .numeric) == .orderedAscending {
                    SectionHeader("Update").padding(.top, 18)
                    step("Agent \(AgentStore.latestVersion) is available. Run this on the server to update. It keeps the key and settings.") {
                        code(AgentStore.updateCommand)
                    }
                    .padding(.horizontal, 16)
                }
            } else {
                SectionHeader("1. Address").padding(.top, 18)
                addressStep.padding(.horizontal, 16)
                SectionHeader("2. Open the port").padding(.top, 18)
                firewallStep.padding(.horizontal, 16)
                SectionHeader("3. Run on the server").padding(.top, 18)
                installStep.padding(.horizontal, 16)
                status.padding(.horizontal, 16).padding(.top, 10)
            }

            SectionHeader("Remove").padding(.top, 18)
            step("Run this on the server to remove the agent, its user and its data. Then remove the firewall rule.") {
                code("sudo rackpulse-agent uninstall")
            }
            .padding(.horizontal, 16)
            if link != nil {
                Button("Remove agent from Rackpulse", role: .destructive) {
                    store.remove(project.id, server.id)
                    back()
                }
                .buttonStyle(.link)
                .font(.system(size: 12))
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            Color.clear.frame(height: 14)
        }
        .onExitCommand(perform: back)
        .onAppear(perform: load)
        .onChange(of: address) { save() }
        .onChange(of: custom) { save() }
        .onChange(of: port) { save() }
        .task(id: link?.endpoint) {
            while !Task.isCancelled, link.map({ !$0.isPaired }) ?? false {
                await store.tryPair(project.id, server: server.id)
                tries += 1
                try? await Task.sleep(for: .seconds(3))
            }
        }
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
                    Text("Rackpulse agent").font(.system(size: 14, weight: .semibold))
                    Text("OPTIONAL")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.4)
                        .foregroundStyle(Theme.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Theme.card, in: Capsule())
                }
                Text(server.name).font(.system(size: 12)).foregroundStyle(Theme.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
    }

    private var facts: some View {
        VStack(alignment: .leading, spacing: 9) {
            fact("lock.shield", "Read-only. The agent cannot run commands or change anything on the server.")
            fact("arrow.down.left.circle", "Your Mac connects to the agent over HTTPS on one TCP port. The server never connects to your Mac.")
            fact("key", "Only Rackpulse with this server's key can read it. The key is stored in your Keychain, and Rackpulse checks the agent's certificate on every connection.")
            fact("clock.arrow.circlepath", "It keeps 30 days of history on the server, so uptime and charts fill in after your Mac sleeps.")
            fact("shippingbox", "To list containers it joins the docker group, which can control Docker. The agent only reads from Docker.")
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 9))
    }

    private func fact(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: icon).foregroundStyle(Theme.secondary).frame(width: 16)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 12))
    }

    private var addressStep: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Where Rackpulse reaches the agent from this Mac.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondary)
            HStack(spacing: 8) {
                Picker("Address", selection: $address) {
                    ForEach(addresses) { option in
                        Text(option.title).tag(option)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity)
                TextField("Port", text: $port)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 64)
                    .help("TCP port, 7311 by default")
            }
            if address == .custom {
                TextField("100.101.102.103 or web-1.tailnet.ts.net", text: $custom)
                    .textFieldStyle(.roundedBorder)
                Text("For example the server's Tailscale or VPN address.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondary)
            }
        }
    }

    private var firewallStep: some View {
        let attached = (server.publicNet.firewalls ?? []).compactMap { ref in ref.id.map { firewalls[$0] ?? "#\($0)" } }
        let portText = String(portNumber)
        return VStack(alignment: .leading, spacing: 8) {
            if address.isPublic {
                if attached.isEmpty {
                    Text("This server has no Hetzner Cloud Firewall, so the port is open to the internet once the agent runs. To limit who can reach it, add a firewall with an inbound rule for TCP port \(portText).")
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("This server uses the firewall \(attached.joined(separator: ", ")). In the Hetzner Console, add an inbound rule: TCP, port \(portText). If your Mac has a fixed IP address, set it as the source.")
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button(attached.isEmpty ? "Open firewalls in the Console" : "Open firewall in the Console") {
                    NSWorkspace.shared.open(firewallsURL)
                }
                .controlSize(.small)
                Text("If ufw is active on the server, also run:").foregroundStyle(Theme.secondary)
                code("sudo ufw allow \(portText)/tcp")
            } else {
                Text("No public firewall rule is needed. If ufw is active on the server, allow the port on the private interface:")
                    .fixedSize(horizontal: false, vertical: true)
                code(address == .privateNetwork
                     ? "sudo ufw allow from 10.0.0.0/8 to any port \(portText) proto tcp"
                     : "sudo ufw allow in on tailscale0 to any port \(portText) proto tcp")
            }
        }
        .font(.system(size: 12))
    }

    private var installStep: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Run as root or with sudo. It downloads the agent for the server's CPU, checks its checksum, and starts it as a service.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let command = store.installCommand(project.id, server.id), !host.isEmpty {
                code(command)
                Text("The command contains this server's key. It starts with a space so bash does not save it in the shell history. Don't share it or screenshots of it.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondary)
            } else {
                Text("Enter an address first.").font(.system(size: 12)).foregroundStyle(Theme.orange)
            }
        }
    }

    @ViewBuilder
    private var keyStep: some View {
        if link?.isRotating == true, let command = store.rotationCommand(project.id, server.id) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Run this on the server. It installs a new key and updates the agent. The old key stops working as soon as it runs.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                code(command)
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Waiting for the agent to use the new key…").font(.system(size: 12, weight: .semibold))
                    Spacer(minLength: 0)
                    Button("Cancel") { store.cancelRotation(project.id, server.id) }.controlSize(.small)
                }
                .padding(10)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 9))
            }
            .task(id: link?.isRotating) {
                while !Task.isCancelled, link?.isRotating == true {
                    await store.tryRotation(project.id, server: server.id)
                    try? await Task.sleep(for: .seconds(3))
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Each server has its own key. Change it if the install command or a screenshot of it was shared. Whoever has the key can read this server's agent data, but cannot change anything.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Change key") { store.startRotation(project.id, server.id) }
                    .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private var status: some View {
        let place = link?.place ?? "port \(portNumber)"
        HStack(alignment: .top, spacing: 8) {
            if link?.isPaired == true {
                Image(systemName: state?.problem == nil ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(state?.problem == nil ? Theme.green : Theme.orange)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Connected at \(place)").font(.system(size: 12, weight: .semibold))
                    Text(pairedDetail).font(.system(size: 11)).foregroundStyle(Theme.secondary)
                    if let problem = state?.problem, let link {
                        Text(problem.text(link)).font(.system(size: 11)).foregroundStyle(Theme.orange)
                            .fixedSize(horizontal: false, vertical: true)
                        if problem == .agent(.certificateChanged) {
                            Button("Pair again") { store.pairAgain(project.id, server.id) }.controlSize(.small)
                        }
                    }
                }
            } else {
                ProgressView().controlSize(.small)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Waiting for the agent at \(place)…").font(.system(size: 12, weight: .semibold))
                    if let problem = state?.problem, let link, tries > 1 {
                        Text(problem.text(link)).font(.system(size: 11)).foregroundStyle(Theme.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("Rackpulse checks every few seconds while this page is open.")
                            .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 9))
    }

    private var pairedDetail: String {
        var parts: [String] = []
        if let version = link?.version { parts.append("Agent \(version)") }
        if let seen = state?.seen { parts.append("last report \(Format.ago(seen, now: .now))") }
        if let paired = link?.pairedAt { parts.append("paired \(paired.formatted(date: .abbreviated, time: .omitted))") }
        return parts.joined(separator: " · ")
    }

    private func step(_ text: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            content()
        }
    }

    private func code(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(text)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                copied = text
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    if copied == text { copied = nil }
                }
            } label: {
                Image(systemName: copied == text ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(copied == text ? Theme.green : Theme.secondary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Copy")
        }
        .padding(8)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 7))
    }

    private var firewallsURL: URL {
        guard let id = project.consoleID else { return URL(string: "https://console.hetzner.com/projects")! }
        return URL(string: "https://console.hetzner.com/projects/\(id)/firewalls")!
    }

    private func load() {
        if let link {
            address = link.address
            port = String(link.endpoint.port)
            if link.address == .custom { custom = link.endpoint.host }
        } else {
            address = addresses.first ?? .custom
            save()
        }
    }

    private func save() {
        guard link?.isPaired != true, !host.isEmpty else { return }
        store.prepare(project.id, server: server.id, address: address, host: host, port: portNumber)
    }
}

struct UsageBar: View {
    let fraction: Double
    let color: Color

    static func color(_ fraction: Double, warn: Bool = false) -> Color {
        warn || fraction >= 0.95 ? Theme.red : fraction >= 0.85 ? Theme.orange : Theme.green
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.divider.opacity(0.6))
                Capsule().fill(color).frame(width: max(3, proxy.size.width * min(1, max(0, fraction))))
            }
        }
        .frame(height: 4)
    }
}

struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon
            configuration.title
        }
    }
}
