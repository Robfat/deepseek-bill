import Foundation
import SwiftUI

final class UsageModel: ObservableObject {
    @Published var balance: Double?
    @Published var totalCost: Double?
    @Published var todayCost: Double?
    @Published var yesterdayCost: Double?
    @Published var points: [CostPoint] = []
    @Published var byKey: [KeyCost] = []
    @Published var byModel: [ModelCost] = []
    @Published var todayRequests: Int = 0
    @Published var todayTokens: Int = 0
    @Published var lastUpdated: Date?
    @Published var error: String?
    @Published var loading = false
    @Published var rangeDays = 7

    var currencySymbol: String = "¥"

    var balanceText: String {
        guard let b = balance else { return "¥--" }
        return String(format: "¥%.2f", b)
    }

    func refresh() {
        if loading { return }
        loading = true
        Task {
            do {
                let cfg = ConfigStore.load()
                var summary: Summary?
                var report: CostReport?
                if let token = cfg.platformToken, !token.isEmpty {
                    summary = try await DeepSeekAPI.summary(token: token)
                    report = try await DeepSeekAPI.cost(token: token, days: 30)
                }
                var bal = summary?.balance
                if bal == nil, let key = cfg.apiKey, !key.isEmpty {
                    bal = try await DeepSeekAPI.balance(apiKey: key)
                }
                let finalSummary = summary
                let finalReport = report
                let finalBalance = bal
                await MainActor.run {
                    self.balance = finalBalance
                    self.totalCost = finalSummary?.totalCost
                    if let r = finalReport {
                        self.todayCost = r.todayCost
                        self.yesterdayCost = r.yesterdayCost
                        self.points = r.points
                        self.byKey = r.byKey
                        self.byModel = r.byModel
                        self.todayRequests = r.todayRequests
                        self.todayTokens = r.todayTokens
                    }
                    self.lastUpdated = Date()
                    self.error = nil
                    self.loading = false
                    self.writeState()
                }
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                await MainActor.run {
                    self.error = message
                    self.loading = false
                }
            }
        }
    }

    private func writeState() {
        let dir = ConfigStore.appDir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let state: [String: Any] = [
            "balance": balance ?? -1,
            "totalCost": totalCost ?? -1,
            "todayCost": todayCost ?? -1,
            "yesterdayCost": yesterdayCost ?? -1,
            "todayRequests": todayRequests,
            "todayTokens": todayTokens,
            "byKey": byKey.map { ["name": $0.name, "cost": $0.cost] },
            "byModel": byModel.map { ["name": $0.name, "cost": $0.cost] },
            "updatedAt": ISO8601DateFormatter().string(from: Date()),
        ]
        if let data = try? JSONSerialization.data(withJSONObject: state, options: [.prettyPrinted]) {
            try? data.write(to: dir.appendingPathComponent("state.json"))
        }
    }
}

func money(_ v: Double?) -> String {
    guard let v else { return "—" }
    return String(format: "¥%.2f", v)
}

func compactTokens(_ n: Int) -> String {
    if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
    if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1_000) }
    return "\(n)"
}
