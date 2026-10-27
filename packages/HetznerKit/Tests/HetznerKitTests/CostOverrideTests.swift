import Foundation
import Testing
@testable import HetznerKit

struct CostOverrideTests {
    let pricing = Pricing(
        currency: "EUR",
        vatRate: 19,
        primaryIps: [],
        floatingIps: [],
        volumePerGBMonth: money("0.044"),
        serverBackupPercentage: 20
    )
    let now = date("2026-10-11T10:30:00Z")

    func line(_ report: CostReport, _ kind: CostLine.Kind, _ id: Int64) -> CostLine? {
        report.lines.first { $0.kind == kind && $0.resourceID == id }
    }

    @Test func userPriceReplacesListPriceForMonthToDateAndForecast() throws {
        let inventory = Inventory(servers: [server(1, backups: true), server(2)])
        let report = CostEstimator(pricing: pricing, serverPrices: [1: Decimal(string: "7.44")!]).estimate(inventory, now: now)

        let own = try #require(line(report, .server, 1))
        #expect(own.monthToDate == Decimal(string: "2.51"))
        #expect(own.forecast == Decimal(string: "7.44"))
        #expect(own.userPrice)

        let backup = try #require(line(report, .backup, 1))
        #expect(backup.monthToDate == Decimal(string: "0.502"))
        #expect(backup.forecast == Decimal(string: "1.488"))
        #expect(backup.userPrice)

        let listed = try #require(line(report, .server, 2))
        #expect(listed.forecast == 5)
        #expect(!listed.userPrice)
        #expect(report.forecast == Decimal(string: "13.928"))
    }

    @Test func userPriceIsProratedFromCreationAndAddsVATForGross() throws {
        let inventory = Inventory(servers: [server(1, created: date("2026-10-11T08:00:00Z"))])
        let net = CostEstimator(pricing: pricing, serverPrices: [1: Decimal(string: "7.44")!]).estimate(inventory, now: now)
        let created = try #require(line(net, .server, 1))
        #expect(created.monthToDate == Decimal(string: "0.03"))
        #expect(created.forecast == Decimal(string: "4.96"))

        let gross = CostEstimator(pricing: pricing, priceKind: .gross, serverPrices: [1: Decimal(string: "7.44")!])
            .estimate(Inventory(servers: [server(1)]), now: now)
        let withVAT = try #require(line(gross, .server, 1))
        #expect(withVAT.monthToDate == Decimal(string: "2.9869"))
        #expect(withVAT.forecast == Decimal(string: "8.8536"))
    }

    @Test func userPriceCoversServersWithoutListPriceAndKeepsIdleReason() throws {
        let unlisted = Server(
            id: 3,
            name: "old-box",
            status: .off,
            created: date("2026-01-01T00:00:00Z"),
            serverType: ServerType(id: 9, name: "cx11", description: "CX11", cores: 1, memory: 2, disk: 20, prices: []),
            location: Location(id: 1, name: "fsn1"),
            backupWindow: nil
        )
        let without = CostEstimator(pricing: pricing).estimate(Inventory(servers: [unlisted]), now: now)
        #expect(without.missingPrices == ["old-box"])

        let with = CostEstimator(pricing: pricing, serverPrices: [3: Decimal(string: "3.72")!])
            .estimate(Inventory(servers: [unlisted]), now: now)
        #expect(with.missingPrices.isEmpty)
        let own = try #require(line(with, .server, 3))
        #expect(own.forecast == Decimal(string: "3.72"))
        #expect(own.idleReason == "Stopped, still billed")
        #expect(with.idleMonthToDate == Decimal(string: "1.255"))
    }

    @Test func zeroUserPriceFallsBackToListPrice() throws {
        let report = CostEstimator(pricing: pricing, serverPrices: [1: 0]).estimate(Inventory(servers: [server(1)]), now: now)
        let own = try #require(line(report, .server, 1))
        #expect(own.forecast == 5)
        #expect(!own.userPrice)
    }

    @Test func budgetRuleUsesForecastWithUserPrice() {
        let inventory = Inventory(servers: [server(1)])
        let engine = RuleEngine(settings: AlertSettings(budget: 6), calendar: utc)
        func evaluate(_ prices: [Int64: Decimal]) -> AlertState {
            let forecast = CostEstimator(pricing: pricing, serverPrices: prices).estimate(inventory, now: now).forecast
            let snapshot = PollSnapshot(time: now, servers: inventory.servers, costForecast: forecast)
            return engine.evaluate(snapshot, state: AlertState()).0
        }

        #expect(evaluate([:]).firing.isEmpty)
        #expect(evaluate([1: Decimal(string: "7.44")!]).firing.map(\.id) == ["budget"])
        #expect(evaluate([1: 4]).firing.isEmpty)
    }

    @Test func disablingBudgetRuleResolvesFiringAlert() {
        let snapshot = PollSnapshot(time: now, servers: [server(1)], costForecast: 10)
        let (firing, _) = RuleEngine(settings: AlertSettings(budget: 6), calendar: utc).evaluate(snapshot, state: AlertState())
        #expect(firing.firing.map(\.id) == ["budget"])

        var off = AlertSettings(budget: nil)
        if let index = off.rules.firstIndex(where: { $0.kind == .budget }) { off.rules[index].enabled = false }
        let later = PollSnapshot(time: now + 60, servers: [server(1)])
        let (state, events) = RuleEngine(settings: off, calendar: utc).evaluate(later, state: firing)
        #expect(state.firing.isEmpty)
        #expect(events == [.resolved(id: "budget")])
    }
}
