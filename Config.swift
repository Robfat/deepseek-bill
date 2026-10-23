import Foundation

struct AppConfig {
    var apiKey: String?
    var platformToken: String?
}

enum ConfigStore {
    static let appDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/DeepSeekBill", isDirectory: true)
    static let configURL = appDir.appendingPathComponent("config.json")

    static func load() -> AppConfig {
        if let data = try? Data(contentsOf: configURL),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return AppConfig(apiKey: obj["apiKey"] as? String,
                             platformToken: obj["platformToken"] as? String)
        }
        return AppConfig(apiKey: fallbackAPIKey(), platformToken: nil)
    }

    /// 没有配置文件时，从 DSH 的凭据文件里读 API Key（只读）。
    static func fallbackAPIKey() -> String? {
        let path = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".dsh/.credentials.yaml")
        guard let text = try? String(contentsOf: path, encoding: .utf8) else { return nil }
        guard let range = text.range(of: #"(?m)^\s+DEEPSEEK_API_KEY:\s*(\S+)\s*$"#, options: .regularExpression) else { return nil }
        let line = String(text[range])
        return line.split(separator: ":", maxSplits: 1).last.map { $0.trimmingCharacters(in: .whitespaces) }
    }
}
