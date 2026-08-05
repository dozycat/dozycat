import Foundation

/// OpenAI 兼容的 chat/completions 客户端——OpenAI、DeepSeek 及一切兼容
/// 服务共用这一个实现（BYOK，见 SettingsStore）。
enum LLMClient {
    struct Config {
        var baseURL: URL
        var model: String
        var apiKey: String
    }

    enum LLMError: Error {
        case badStatus(Int)
        case emptyReply
    }

    /// 懒猫人设——只负责用户本人，不帮干活。
    static let persona = """
    你是「懒猫」（dozycat），住在用户手机和桌面里的陪伴 AI。你不帮用户干活——\
    工作交给别的 AI，你只负责用户本人：情绪、休息、喝水、睡觉这些小事。\
    语气轻、短、口语化、不说教，一两句话就好，偶尔像猫一样懒懒的。\
    永远用用户最后一条消息的语言回复。
    """

    static func reply(history: [(role: String, content: String)],
                      config: Config) async throws -> String {
        let url = config.baseURL.appendingPathComponent("chat/completions")
        var request = URLRequest(url: url, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")

        struct Message: Codable { let role: String; let content: String }
        struct Body: Codable { let model: String; let messages: [Message] }
        let messages = [Message(role: "system", content: persona)]
            + history.suffix(12).map { Message(role: $0.role, content: $0.content) }
        request.httpBody = try JSONEncoder().encode(Body(model: config.model, messages: messages))

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw LLMError.badStatus(http.statusCode)
        }

        struct Choice: Codable { struct Msg: Codable { let content: String? }; let message: Msg }
        struct Reply: Codable { let choices: [Choice] }
        let reply = try JSONDecoder().decode(Reply.self, from: data)
        guard let text = reply.choices.first?.message.content?
            .trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            throw LLMError.emptyReply
        }
        return text
    }
}
