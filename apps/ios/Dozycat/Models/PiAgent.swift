import Foundation

/// pi 式 agent 循环：system + 工具 + 多轮 tool-calling，直到给出最终回答。
///
/// 这是 dozycat 所有 agent（chat / sequence / dream / searcher）共用的执行器，
/// OpenAI 兼容 function calling（DeepSeek/OpenAI 通吃）。行为（prompt + 工具集）
/// 与执行器分离——将来换成 pocket-pi(QuickJS) 运行时，行为定义原样迁移。
struct AgentTool {
    let name: String
    let description: String
    /// JSON Schema（properties 部分）
    let parameters: [String: Any]
    let run: @MainActor ([String: Any]) async -> String
}

@MainActor
enum PiAgent {
    enum AgentError: Error {
        case badStatus(Int)
        case malformed
    }

    /// 跑一个 agent 回合。`history` 是 (role, content) 对话；工具循环最多 `maxSteps` 轮。
    static func run(system: String,
                    history: [(role: String, content: String)],
                    tools: [AgentTool] = [],
                    config: LLMClient.Config,
                    maxSteps: Int = 10,
                    onStep: ((String) -> Void)? = nil) async throws -> String {
        var messages: [[String: Any]] = [["role": "system", "content": system]]
        messages += history.map { ["role": $0.role, "content": $0.content] }

        let toolDefs: [[String: Any]] = tools.map { tool in
            ["type": "function",
             "function": ["name": tool.name,
                          "description": tool.description,
                          "parameters": ["type": "object",
                                         "properties": tool.parameters] as [String: Any]]]
        }

        for _ in 0..<maxSteps {
            let message = try await chat(messages: messages,
                                         tools: toolDefs.isEmpty ? nil : toolDefs,
                                         config: config)
            messages.append(message)

            guard let calls = message["tool_calls"] as? [[String: Any]], !calls.isEmpty else {
                return (message["content"] as? String ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            for call in calls {
                let function = call["function"] as? [String: Any]
                let name = function?["name"] as? String ?? ""
                let argsData = Data((function?["arguments"] as? String ?? "{}").utf8)
                let args = (try? JSONSerialization.jsonObject(with: argsData)) as? [String: Any] ?? [:]
                onStep?(name)
                let result: String
                if let tool = tools.first(where: { $0.name == name }) {
                    result = await tool.run(args)
                } else {
                    result = "unknown tool: \(name)"
                }
                messages.append(["role": "tool",
                                 "tool_call_id": call["id"] as? String ?? "",
                                 "content": String(result.prefix(6000))])
            }
        }
        return String(localized: "（转了好多圈还没理出头绪…要不换个说法再问我？）")
    }

    private static func chat(messages: [[String: Any]],
                             tools: [[String: Any]]?,
                             config: LLMClient.Config) async throws -> [String: Any] {
        var body: [String: Any] = ["model": config.model, "messages": messages]
        if let tools { body["tools"] = tools }

        var request = URLRequest(url: config.baseURL.appendingPathComponent("chat/completions"),
                                 timeoutInterval: 120)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw AgentError.badStatus(http.statusCode)
        }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choice = (obj["choices"] as? [[String: Any]])?.first,
              var message = choice["message"] as? [String: Any] else {
            throw AgentError.malformed
        }
        if message["content"] is NSNull { message["content"] = "" }
        return message
    }
}
