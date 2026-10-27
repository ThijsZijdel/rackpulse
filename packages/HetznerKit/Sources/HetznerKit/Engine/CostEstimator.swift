import Foundation

public struct Inventory: Sendable, Hashable {
    public var servers: [Server]
    public var volumes: [Volume]
    public var primaryIPs: [PrimaryIP]
    public var floatingIPs: [FloatingIP]
    public var loadBalancers: [LoadBalancer]
    public var storageBoxes: [StorageBox]

    public init(
        servers: [Server] = [],
        volumes: [Volume] = [],
        primaryIPs: [PrimaryIP] = [],
        floatingIPs: [FloatingIP] = [],
        loadBalancers: [LoadBalancer] = [],
        storageBoxes: [StorageBox] = []
    ) {
        self.servers = servers
        self.volumes = volumes
        self.primaryIPs = primaryIPs
        self.floatingIPs = floatingIPs
        self.loadBalancers = loadBalancers
        self.storageBoxes = storageBoxes
    }
}

public struct CostLine: Sendable, Hashable, Identifiable {
    public enum Kind: String, Sendable, Hashable {
        case server, backup, volume, primaryIP, floatingIP, loadBalancer, storageBox
    }

    public let kind: Kind
    public let resourceID: Int64
    public let name: String
    public let monthToDate: Decimal
    public let forecast: Decimal
    public let idleReason: String?
    public var userPrice = false

    public var id: String { "\(kind.rawValue):\(resourceID)" }
}

public struct CostReport: Sendable, Hashable {
    public let currency: String
    public let priceKind: PriceKind
    public let monthStart: Date
    public let monthEnd: Date
    public let lines: [CostLine]
    public let missingPrices: [String]

    public var monthToDate: Decimal { lines.reduce(0) { $0 + $1.monthToDate } }
    public var forecast: Decimal { lines.reduce(0) { $0 + $1.forecast } }
    public var idleMonthToDate: Decimal { lines.filter { $0.idleReason != nil }.reduce(0) { $0 + $1.monthToDate } }
}

public struct CostEstimator: Sendable {
    public let pricing: Pricing?
    public let priceKind: PriceKind
    public let serverPrices: [Int64: Decimal]
    public let calendar: Calendar

    public init(pricing: Pricing?, priceKind: PriceKind = .net, serverPrices: [Int64: Decimal] = [:], timeZone: TimeZone = .gmt) {
        self.pricing = pricing
        self.priceKind = priceKind
        self.serverPrices = serverPrices
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        self.calendar = calendar
    }

    public func estimate(_ inventory: Inventory, now: Date) -> CostReport {
        let month = calendar.dateInterval(of: .month, for: now)!
        var billing = Billing(month: month, now: now, kind: priceKind)

        for server in inventory.servers {
            let idle = server.status == .off ? "Stopped, still billed" : nil
            let line: CostLine
            if let monthly = userPrice(server.id) {
                line = billing.prorated(.server, server.id, server.name, monthly: monthly, since: server.created,
                                        idle: idle, userPrice: true)
            } else {
                guard let listed = billing.hourly(.server, server.id, server.name, listPrice(server), since: server.created, idle: idle) else {
                    billing.missing.append(server.name)
                    continue
                }
                line = listed
            }
            if server.backupsEnabled, let percentage = pricing?.serverBackupPercentage {
                let share = percentage / 100
                billing.lines.append(CostLine(
                    kind: .backup,
                    resourceID: server.id,
                    name: server.name,
                    monthToDate: line.monthToDate * share,
                    forecast: line.forecast * share,
                    idleReason: idle,
                    userPrice: line.userPrice
                ))
            }
        }

        for volume in inventory.volumes {
            guard let perGB = pricing?.volumePerGBMonth.value(priceKind) else {
                billing.missing.append(volume.name)
                continue
            }
            let monthly = perGB * Decimal(volume.size)
            billing.prorated(.volume, volume.id, volume.name, monthly: monthly, since: volume.created,
                             idle: volume.server == nil ? "Detached" : nil)
        }

        for ip in inventory.primaryIPs {
            let price = pricing?.primaryIP(ip.type, at: ip.location.name)
            if price == nil && ip.type == .ipv6 { continue }
            if billing.hourly(.primaryIP, ip.id, ip.name, price, since: ip.created,
                              idle: ip.isUnassigned ? "Not assigned" : nil) == nil {
                billing.missing.append(ip.name)
            }
        }

        for ip in inventory.floatingIPs {
            guard let monthly = pricing?.floatingIP(ip.type, at: ip.homeLocation.name)?.priceMonthly.value(priceKind) else {
                billing.missing.append(ip.name)
                continue
            }
            billing.prorated(.floatingIP, ip.id, ip.name, monthly: monthly, since: ip.created,
                             idle: ip.server == nil ? "Not assigned" : nil)
        }

        for balancer in inventory.loadBalancers {
            let price = balancer.loadBalancerType.prices.price(at: balancer.location.name)
            if billing.hourly(.loadBalancer, balancer.id, balancer.name, price, since: balancer.created, idle: nil) == nil {
                billing.missing.append(balancer.name)
            }
        }

        for box in inventory.storageBoxes {
            let price = box.storageBoxType.prices.price(at: box.location.name)
            if billing.hourly(.storageBox, box.id, box.name, price, since: box.created, idle: nil) == nil {
                billing.missing.append(box.name)
            }
        }

        return CostReport(
            currency: pricing?.currency ?? "EUR",
            priceKind: priceKind,
            monthStart: month.start,
            monthEnd: month.end,
            lines: billing.lines,
            missingPrices: billing.missing
        )
    }

    public func listPrice(_ server: Server) -> LocationPrice? {
        server.serverType.prices.price(at: server.location.name)
            ?? pricing?.serverTypes.first { $0.name == server.serverType.name }?.prices.price(at: server.location.name)
    }

    public func userPrice(_ server: Int64) -> Decimal? {
        guard let net = serverPrices[server], net > 0 else { return nil }
        guard priceKind == .gross, let vat = pricing?.vatRate else { return net }
        return net * (1 + vat / 100)
    }
}

private struct Billing {
    let month: DateInterval
    let now: Date
    let kind: PriceKind
    var lines: [CostLine] = []
    var missing: [String] = []

    var hoursInMonth: Decimal { Decimal(month.duration / 3600) }

    func billedHours(from start: Date, to end: Date) -> Decimal {
        Decimal((max(0, end.timeIntervalSince(start)) / 3600).rounded(.up))
    }

    @discardableResult
    mutating func hourly(
        _ lineKind: CostLine.Kind,
        _ id: Int64,
        _ name: String,
        _ price: LocationPrice?,
        since created: Date,
        idle: String?
    ) -> CostLine? {
        guard let price else { return nil }
        let monthly = price.priceMonthly.value(kind)
        guard let hourly = price.priceHourly?.value(kind) else {
            let hours = hoursInMonth
            return add(lineKind, id, name, monthly: monthly, since: created, idle: idle) { monthly * $0 / hours }
        }
        return add(lineKind, id, name, monthly: monthly, since: created, idle: idle) { hourly * $0 }
    }

    @discardableResult
    mutating func prorated(
        _ lineKind: CostLine.Kind,
        _ id: Int64,
        _ name: String,
        monthly: Decimal,
        since created: Date,
        idle: String?,
        userPrice: Bool = false
    ) -> CostLine {
        let hours = hoursInMonth
        return add(lineKind, id, name, monthly: monthly, since: created, idle: idle, userPrice: userPrice) { monthly * $0 / hours }
    }

    @discardableResult
    private mutating func add(
        _ lineKind: CostLine.Kind,
        _ id: Int64,
        _ name: String,
        monthly: Decimal,
        since created: Date,
        idle: String?,
        userPrice: Bool = false,
        cost: (Decimal) -> Decimal
    ) -> CostLine {
        let start = max(created, month.start)
        let line = CostLine(
            kind: lineKind,
            resourceID: id,
            name: name,
            monthToDate: min(cost(billedHours(from: start, to: now)), monthly),
            forecast: min(cost(billedHours(from: start, to: month.end)), monthly),
            idleReason: idle,
            userPrice: userPrice
        )
        lines.append(line)
        return line
    }
}
