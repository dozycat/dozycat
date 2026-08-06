import SwiftUI
import Security

enum LLMProvider: String, CaseIterable, Identifiable {
    case openai, deepseek, custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .openai: return "OpenAI"
        case .deepseek: return "DeepSeek"
        case .custom: return String(localized: "自定义")
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .openai: return "https://api.openai.com/v1"
        case .deepseek: return "https://api.deepseek.com"
        case .custom: return ""
        }
    }

    var defaultModel: String {
        switch self {
        case .openai: return "gpt-5-mini"
        case .deepseek: return "deepseek-chat"
        case .custom: return ""
        }
    }
}

/// BYOK 配置：provider/model/baseURL 在 UserDefaults，API Key 只进 Keychain。
@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @AppStorage("llmProvider") var providerRaw: String = LLMProvider.openai.rawValue
    @AppStorage("llmModel") var model: String = ""
    @AppStorage("llmBaseURL") var baseURL: String = ""
    @Published var apiKey: String

    private init() {
        // 环境变量优先（CI/自动化测试注入），日常走钥匙串。
        apiKey = ProcessInfo.processInfo.environment["DOZYCAT_LLM_KEY"]
            ?? Keychain.get("llm-api-key") ?? ""
    }

    var provider: LLMProvider {
        get { LLMProvider(rawValue: providerRaw) ?? .openai }
        set { providerRaw = newValue.rawValue }
    }

    func persistKey() {
        Keychain.set(apiKey.trimmingCharacters(in: .whitespacesAndNewlines), for: "llm-api-key")
    }

    /// 可用的模型配置；Key 或 URL 缺失时为 nil（聊天回退内置回复）。
    var llmConfig: LLMClient.Config? {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }
        let urlString = baseURL.isEmpty ? provider.defaultBaseURL : baseURL
        guard let url = URL(string: urlString), url.scheme == "https" else { return nil }
        let modelName = model.isEmpty ? provider.defaultModel : model
        guard !modelName.isEmpty else { return nil }
        return LLMClient.Config(baseURL: url, model: modelName, apiKey: key)
    }
}

/// 极简 Keychain 封装（generic password，可同步条目）。
///
/// `kSecAttrSynchronizable` = 经 iCloud 钥匙串在用户设备间端到端同步。
/// iOS app 与 macOS 桌宠共享同一条目还需 shared keychain access group
/// （签名时给两个 target 加 `com.paperboytm.dozycat.shared` entitlement，
/// 代码不用改——默认写入 entitlement 列表的第一个组）。
enum Keychain {
    private static func query(_ key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.paperboytm.dozycat",
            kSecAttrAccount as String: key,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
        ]
    }

    static func set(_ value: String, for key: String) {
        SecItemDelete(query(key) as CFDictionary)
        guard !value.isEmpty, let data = value.data(using: .utf8) else { return }
        var attrs = query(key)
        attrs[kSecAttrSynchronizable as String] = true
        attrs[kSecValueData as String] = data
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let syncStatus = SecItemAdd(attrs as CFDictionary, nil)
        guard syncStatus != errSecSuccess else { return }

        // Ad-hoc / 本地 Debug 构建通常没有 iCloud Keychain entitlement。
        // 这时同步条目会写失败，自动回退为同 service/account 的本机条目；
        // `get` 使用 SynchronizableAny，发布签名与本机条目都能读取。
        attrs.removeValue(forKey: kSecAttrSynchronizable as String)
        let localStatus = SecItemAdd(attrs as CFDictionary, nil)
        if localStatus != errSecSuccess {
            NSLog("Keychain: failed to store \(key) (sync=\(syncStatus), local=\(localStatus))")
        }
    }

    static func get(_ key: String) -> String? {
        var attrs = query(key)
        attrs[kSecReturnData as String] = true
        attrs[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(attrs as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
