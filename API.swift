import Foundation

struct Summary {
    var balance: Double
    var totalCost: Double
    var currency: String
}

struct CostPoint: Identifiable {
    var id: Int { day }
    let day: Int          // 当天 00:00 +08:00 的 unix 秒
    let cost: Double
    var date: Date { Date(timeIntervalSince1970: TimeInterval(day)) }
}

struct KeyCost: Identifiable {
    var id: String { name }
    let name: String
    let cost: Double
}

struct ModelCost: Identifiable {
    var id: String { name }
    let name: String
    let cost: Double
}

struct CostReport {
    var points: [CostPoint] = []
    var byKey: [KeyCost] = []
    var byModel: [ModelCost] = []
    var todayCost: Double = 0
    var yesterdayCost: Double = 0
    var todayRequests: Int = 0
    var todayTokens: Int = 0
}

enum APIError: LocalizedError {
    case http(Int)
    case api(String)
    case malformed

    var errorDescription: String? {
        switch self {
        case .http(let code): return "HTTP \(code)"
        case .api(let msg): return msg.isEmpty ? "接口返回错误" : msg
        case .malformed: return "返回数据格式异常"
        }
    }
}

enum DeepSeekAPI {
    static let tzOffset = 8 * 3600
    static let ua = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"

    private static func getJSON(_ url: URL, token: String, platform: Bool) async throws -> [String: Any] {
        var req = URLRequest(url: url)
        req.timeoutInterval = 20
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if platform {
            req.setValue("web", forHTTPHeaderField: "x-client-platform")
            req.setValue("https://platform.deepseek.com/usage", forHTTPHeaderField: "Referer")
            req.setValue(ua, forHTTPHeaderField: "User-Agent")
        }
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw APIError.malformed }
        guard http.statusCode == 200 else { throw APIError.http(http.statusCode) }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw APIError.malformed }
        if let code = obj["code"] as? Int, code != 0 {
            throw APIError.api(obj["msg"] as? String ?? "")
        }
        return obj
    }

    private static func num(_ v: Any?) -> Double {
        if let d = v as? Double { return d }
        if let i = v as? Int { return Double(i) }
        if let s = v as? String { return Double(s) ?? 0 }
        if let n = v as? NSNumber { return n.doubleValue }
        return 0
    }

    static func summary(token: String) async throws -> Summary {
        let url = URL(string: "https://platform.deepseek.com/api/v0/users/get_user_summary")!
        let obj = try await getJSON(url, token: token, platform: true)
        let biz = (obj["data"] as? [String: Any])?["biz_data"] as? [String: Any] ?? [:]
        let wallets = biz["normal_wallets"] as? [[String: Any]] ?? []
        let wallet = wallets.first ?? [:]
        let costs = biz["total_costs"] as? [[String: Any]] ?? []
        let cost = costs.first ?? [:]
        return Summary(balance: num(wallet["balance"]),
                       totalCost: num(cost["amount"]),
                       currency: wallet["currency"] as? String ?? "CNY")
    }

    static func balance(apiKey: String) async throws -> Double {
        let url = URL(string: "https://api.deepseek.com/user/balance")!
        let obj = try await getJSON(url, token: apiKey, platform: false)
        let infos = obj["balance_infos"] as? [[String: Any]] ?? []
        return num(infos.first?["total_balance"])
    }

    static func cost(token: String, days: Int) async throws -> CostReport {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: tzOffset) ?? .current
        let now = Date()
        let todayStart = cal.startOfDay(for: now)
        let start = cal.date(byAdding: .day, value: -(days - 1), to: todayStart) ?? todayStart
        let end = cal.date(byAdding: .day, value: 1, to: todayStart) ?? now
        let startTS = Int(start.timeIntervalSince1970)
        let endTS = Int(end.timeIntervalSince1970)

        func url(_ kind: String) -> URL {
            URL(string: "https://platform.deepseek.com/api/v0/usage/by_api_key/\(kind)?start=\(startTS)&end=\(endTS)&tz=\(tzOffset)")!
        }

        async let costObj = getJSON(url("cost"), token: token, platform: true)
        async let amountObj = getJSON(url("amount"), token: token, platform: true)
        let (cObj, aObj) = try await (costObj, amountObj)

        var report = CostReport()
        var perDay: [Int: Double] = [:]
        var perKey: [String: Double] = [:]
        var perModel: [String: Double] = [:]

        let biz = (cObj["data"] as? [String: Any])?["biz_data"] as? [String: Any] ?? [:]
        for cur in biz["data"] as? [[String: Any]] ?? [] {
            for s in cur["series"] as? [[String: Any]] ?? [] {
                let keyName = ((s["api_key"] as? [String: Any])?["name"] as? String) ?? "未命名 Key"
                let model = s["model"] as? String ?? "未知模型"
                let buckets = s["buckets"] as? [[String: Any]] ?? []
                for b in buckets {
                    let t = Int(num(b["time"]))
                    let c = num(b["cost"])
                    perDay[t, default: 0] += c
                    perKey[keyName, default: 0] += c
                    perModel[model, default: 0] += c
                }
            }
        }

        let todayTS = Int(todayStart.timeIntervalSince1970)
        report.todayCost = perDay[todayTS] ?? 0
        report.yesterdayCost = perDay[todayTS - 86400] ?? 0
        report.points = (0..<days).compactMap { i in
            guard let d = cal.date(byAdding: .day, value: i, to: start) else { return nil }
            let ts = Int(d.timeIntervalSince1970)
            return CostPoint(day: ts, cost: perDay[ts] ?? 0)
        }
        report.byKey = perKey.map { KeyCost(name: $0.key, cost: $0.value) }.sorted { $0.cost > $1.cost }
        report.byModel = perModel.map { ModelCost(name: $0.key, cost: $0.value) }.sorted { $0.cost > $1.cost }

        // 今日请求数 / token（官方 amount 接口）
        let abiz = (aObj["data"] as? [String: Any])?["biz_data"] as? [String: Any] ?? [:]
        var requests = 0, tokens = 0
        for s in abiz["series"] as? [[String: Any]] ?? [] {
            for b in s["buckets"] as? [[String: Any]] ?? [] {
                guard Int(num(b["time"])) == todayTS else { continue }
                let u = b["usage"] as? [String: Any] ?? [:]
                requests += Int(num(u["REQUEST"]))
                tokens += Int(num(u["PROMPT_CACHE_HIT_TOKEN"]) + num(u["PROMPT_CACHE_MISS_TOKEN"]) + num(u["RESPONSE_TOKEN"]))
            }
        }
        report.todayRequests = requests
        report.todayTokens = tokens
        return report
    }
}
