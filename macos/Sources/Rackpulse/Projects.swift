import HetznerKit
import AppKit
import Foundation
import Observation
import ServiceManagement
import SwiftUI

enum ServerEnvironment: String, Codable, CaseIterable, Identifiable {
    case none, production, staging, development

    var id: String { rawValue }

    init?(labels: [String: String]) {
        guard let value = labels.first(where: { ["env", "environment"].contains($0.key.lowercased()) })?.value else { return nil }
        switch value.lowercased() {
        case "prod", "production", "prd", "live": self = .production
        case "stage", "staging", "stg": self = .staging
        case "dev", "development", "test": self = .development
        default: return nil
        }
    }

    var title: String {
        switch self {
        case .none: "None"
        case .production: "Production"
        case .staging: "Staging"
        case .development: "Development"
        }
    }

    var badge: String? {
        switch self {
        case .none: nil
        case .production: "PROD"
        case .staging: "STAGING"
        case .development: "DEV"
        }
    }

    var tagColor: Color {
        switch self {
        case .none: Color(nsColor: .systemGray)
        case .production: Color(nsColor: .systemRed)
        case .staging: Color(nsColor: .systemOrange)
        case .development: Color(nsColor: .systemBlue)
        }
    }
}

enum ProjectColor: String, Codable, CaseIterable, Identifiable {
    case primary, red, orange, yellow, green, mint, teal, blue, indigo, purple, pink, gray

    var id: String { rawValue }

    var title: String {
        self == .primary ? "Black or white" : rawValue.capitalized
    }

    var nsColor: NSColor? {
        switch self {
        case .primary: nil
        case .red: .systemRed
        case .orange: .systemOrange
        case .yellow: .systemYellow
        case .green: .systemGreen
        case .mint: .systemMint
        case .teal: .systemTeal
        case .blue: .systemBlue
        case .indigo: .systemIndigo
        case .purple: .systemPurple
        case .pink: .systemPink
        case .gray: .systemGray
        }
    }

    var color: Color {
        switch self {
        case .primary: Color.primary
        case .red: Color(nsColor: .systemRed)
        case .orange: Color(nsColor: .systemOrange)
        case .yellow: Color(nsColor: .systemYellow)
        case .green: Color(nsColor: .systemGreen)
        case .mint: Color(nsColor: .systemMint)
        case .teal: Color(nsColor: .systemTeal)
        case .blue: Color(nsColor: .systemBlue)
        case .indigo: Color(nsColor: .systemIndigo)
        case .purple: Color(nsColor: .systemPurple)
        case .pink: Color(nsColor: .systemPink)
        case .gray: Color(nsColor: .systemGray)
        }
    }
}

struct Project: Codable, Identifiable, Hashable {
    static let icons = [
        "server.rack", "square.3.layers.3d", "cloud", "globe", "cart", "bolt",
        "flask", "hammer", "briefcase", "house", "gamecontroller", "leaf",
        "heart", "star", "shippingbox", "cpu", "lock.shield", "chart.bar",
    ]

    let id: UUID
    var name: String
    let addedAt: Date
    var environment: ServerEnvironment
    var color: ProjectColor
    var icon: String
    var budget: Decimal?
    var sshUser: String
    var access: TokenAccess
    var consoleID: String?

    init(id: UUID = UUID(), name: String, addedAt: Date = .now) {
        self.id = id
        self.name = name
        self.addedAt = addedAt
        environment = .none
        color = .primary
        icon = "server.rack"
        sshUser = "root"
        access = .readOnly
    }

    enum CodingKeys: String, CodingKey {
        case id, name, addedAt, environment, color, icon, budget, sshUser, access, consoleID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        addedAt = try container.decode(Date.self, forKey: .addedAt)
        environment = (try? container.decodeIfPresent(ServerEnvironment.self, forKey: .environment)) ?? .none
        color = (try? container.decodeIfPresent(ProjectColor.self, forKey: .color)) ?? .primary
        icon = (try? container.decodeIfPresent(String.self, forKey: .icon)) ?? "server.rack"
        budget = try? container.decodeIfPresent(Decimal.self, forKey: .budget)
        sshUser = (try? container.decodeIfPresent(String.self, forKey: .sshUser)) ?? "root"
        access = (try? container.decodeIfPresent(TokenAccess.self, forKey: .access)) ?? .readOnly
        consoleID = try? container.decodeIfPresent(String.self, forKey: .consoleID)
    }
}

@MainActor
@Observable
final class ProjectStore {
    private static let projectsKey = "projects"
    private static let selectedKey = "selectedProject"
    private static let showsAllKey = "showsAllProjects"
    private static let collapsedKey = "collapsedProjects"

    private(set) var projects: [Project]
    var selectedID: UUID? {
        didSet { UserDefaults.standard.set(selectedID?.uuidString, forKey: Self.selectedKey) }
    }
    var showsAll: Bool {
        didSet { UserDefaults.standard.set(showsAll, forKey: Self.showsAllKey) }
    }
    var collapsed: Set<UUID> {
        didSet { UserDefaults.standard.set(collapsed.map(\.uuidString), forKey: Self.collapsedKey) }
    }

    init() {
        let data = UserDefaults.standard.data(forKey: Self.projectsKey)
        projects = data.flatMap { try? JSONDecoder().decode([Project].self, from: $0) } ?? []
        let saved = UserDefaults.standard.string(forKey: Self.selectedKey).flatMap(UUID.init)
        showsAll = UserDefaults.standard.object(forKey: Self.showsAllKey) as? Bool ?? true
        collapsed = Set((UserDefaults.standard.stringArray(forKey: Self.collapsedKey) ?? []).compactMap(UUID.init))
        selectedID = projects.contains { $0.id == saved } ? saved : projects.first?.id
    }

    var scope: [Project] {
        if showsAll { return projects }
        return selected.map { [$0] } ?? []
    }

    var selected: Project? {
        projects.first { $0.id == selectedID }
    }

    func project(_ id: UUID?) -> Project? {
        projects.first { $0.id == id }
    }

    func token(for project: Project) -> String? {
        Keychain.read(account: project.id.uuidString)
    }

    func add(name: String, token: String, access: TokenAccess) throws {
        var project = Project(name: name)
        project.access = access
        try Keychain.save(token, account: project.id.uuidString)
        projects.append(project)
        persist()
        selectedID = project.id
        if projects.count == 1 && ProcessInfo.processInfo.environment["RACKPULSE_DEV"] == nil {
            try? SMAppService.mainApp.register()
        }
    }

    func replaceToken(_ id: UUID, token: String, access: TokenAccess) throws {
        try Keychain.save(token, account: id.uuidString)
        update(id) { $0.access = access }
    }

    func update(_ id: UUID, _ change: (inout Project) -> Void) {
        guard let index = projects.firstIndex(where: { $0.id == id }) else { return }
        change(&projects[index])
        persist()
    }

    func remove(_ project: Project) {
        Keychain.delete(account: project.id.uuidString)
        projects.removeAll { $0.id == project.id }
        persist()
        if selectedID == project.id { selectedID = projects.first?.id }
    }

    private func persist() {
        UserDefaults.standard.set(try? JSONEncoder().encode(projects), forKey: Self.projectsKey)
    }
}

struct EnvironmentBadge: View {
    let environment: ServerEnvironment

    var body: some View {
        if let badge = environment.badge {
            Text(badge)
                .font(.system(size: 9, weight: .bold))
                .tracking(0.4)
                .foregroundStyle(environment.tagColor)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(environment.tagColor.opacity(0.15), in: Capsule())
                .fixedSize()
        }
    }
}

struct EnvironmentPicker<Label: View>: View {
    let settings: SettingsStore
    let project: UUID
    let server: Server
    @ViewBuilder let label: Label

    var body: some View {
        Picker(selection: Binding(
            get: { settings.environmentChoice(project: project, server: server.id) },
            set: { settings.setEnvironment($0, project: project, server: server.id) }
        )) {
            Text(automatic).tag(nil as ServerEnvironment?)
            Divider()
            ForEach(ServerEnvironment.allCases) { Text($0.title).tag($0 as ServerEnvironment?) }
        } label: {
            label
        }
    }

    private var automatic: String {
        ServerEnvironment(labels: server.labels).map { "Automatic (\($0.title), from label)" } ?? "Automatic"
    }
}

extension Project {
    var menuImage: NSImage {
        let base = NSImage(systemSymbolName: icon, accessibilityDescription: name) ?? NSImage()
        var config = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        if let tint = color.nsColor { config = config.applying(.init(paletteColors: [tint])) }
        let image = base.withSymbolConfiguration(config) ?? base
        image.isTemplate = color.nsColor == nil
        return image
    }
}

extension Project {
    static func consoleID(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, trimmed.allSatisfy(\.isNumber) { return trimmed }
        guard let range = trimmed.range(of: #"projects/(\d+)"#, options: .regularExpression) else { return nil }
        return String(trimmed[range].dropFirst("projects/".count))
    }
}
