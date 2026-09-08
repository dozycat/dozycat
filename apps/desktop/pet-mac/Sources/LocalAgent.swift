import Foundation
import CoreImage
import ImageIO
import MLX
import MLXLMCommon
import MLXVLM

struct LocalMessage: Sendable {
    var role: String
    var content: String
    var calls: [ToolCall] = []
    var callID: String? = nil
}

struct LocalReply: Sendable {
    var text = ""
    var calls: [ToolCall] = []
}

@MainActor
enum LocalAgent {
    static func run(system: String, history: [(role: String, content: String)],
                    tools: [AgentTool], config: LLMClient.Config, maxSteps: Int,
                    imageData: Data?, onStep: ((String) -> Void)?) async throws -> String {
        guard let directory = config.localModelDirectory,
              LocalModelStore.isInstalled(config.model) else { throw LocalModelError.notInstalled }
        var messages = [LocalMessage(role: "system", content: system)]
            + history.map { LocalMessage(role: $0.role, content: $0.content) }
        let definitions = tools.map { tool -> [String: Any] in
            ["type": "function", "function": ["name": tool.name, "description": tool.description,
                "parameters": ["type": "object", "properties": tool.parameters, "required": tool.requiredParameters, "additionalProperties": false]]]
        }
        let data = try JSONSerialization.data(withJSONObject: definitions)
        for _ in 0..<min(maxSteps, 6) {
            try Task.checkCancellation()
            let reply = try await LocalModelRuntime.shared.reply(directory: directory, messages: messages,
                                                                 toolsData: data, imageData: imageData)
            if reply.calls.isEmpty {
                guard !reply.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw LLMClient.LLMError.emptyReply }
                return reply.text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard reply.calls.count <= 4 else { throw LocalModelError.invalidToolCall }
            messages.append(LocalMessage(role: "assistant", content: reply.text, calls: reply.calls))
            for call in reply.calls {
                try Task.checkCancellation()
                guard let tool = tools.first(where: { $0.name == call.function.name }) else { throw LocalModelError.invalidToolCall }
                let args = call.function.arguments.mapValues(\.anyValue)
                // Never turn malformed arguments into an empty dictionary and execute a write.
                guard tool.requiredParameters.allSatisfy({ args[$0] != nil }),
                      args.keys.allSatisfy({ tool.parameters[$0] != nil }) else { throw LocalModelError.invalidToolCall }
                for (key, value) in call.function.arguments {
                    let type = (tool.parameters[key] as? [String: Any])?["type"] as? String
                    switch (type, value) {
                    case ("string", .string), ("integer", .int), ("number", .int), ("number", .double),
                         ("boolean", .bool), ("array", .array), ("object", .object), (nil, _): break
                    default: throw LocalModelError.invalidToolCall
                    }
                }
                onStep?(tool.name)
                let result = await tool.run(args)
                messages.append(LocalMessage(role: "tool", content: String(result.prefix(2000)), callID: call.id))
            }
        }
        return "（这次没能整理完，试试缩小问题范围吧。）"
    }
}

/// One loaded VLM, one generation at a time, including across suspension points.
/// The gate also protects model replacement; actor isolation alone cannot do that.
actor LocalModelRuntime {
    static let shared = LocalModelRuntime()
    private var container: ModelContainer?
    private var loadedDirectory: URL?
    private var idleUnload: Task<Void, Never>?
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    private func acquire() async {
        if busy { await withCheckedContinuation { waiters.append($0) } }
        else { busy = true }
    }
    private func release() {
        if waiters.isEmpty { busy = false }
        else { waiters.removeFirst().resume() }
    }

    func unload() async {
        await acquire()
        idleUnload?.cancel()
        container = nil
        loadedDirectory = nil
        MLX.Memory.clearCache()
        release()
    }

    private func scheduleUnload() {
        guard !busy else { return }
        idleUnload = Task {
            do { try await Task.sleep(for: .seconds(90)) } catch { return }
            guard !busy else { return }
            container = nil
            loadedDirectory = nil
            MLX.Memory.clearCache()
        }
    }

    func reply(directory: URL, messages: [LocalMessage], toolsData: Data, imageData: Data?) async throws -> LocalReply {
        await acquire()
        idleUnload?.cancel()
        defer { MLX.Memory.clearCache(); release(); scheduleUnload() }
        try Task.checkCancellation()
        if container == nil || loadedDirectory != directory {
            container = nil
            loadedDirectory = nil
            MLX.Memory.clearCache()
            MLX.Memory.cacheLimit = 128 * 1024 * 1024
            let loaded = try await VLMModelFactory.shared.loadContainer(from: directory, using: LocalTokenizerLoader())
            await loaded.update { $0.configuration.toolCallFormat = .qwen35 }
            container = loaded
            loadedDirectory = directory
        }
        guard let container else { throw LocalModelError.notInstalled }
        return try await container.perform { context in
            try Task.checkCancellation()
            let specs = try JSONDecoder().decode([[String: JSONValue]].self, from: toolsData)
                .map { $0.mapValues(\.localSendable) }
            var chat: [Chat.Message] = messages.map { message in
                switch message.role {
                case "system": return .system(message.content)
                case "assistant": return .assistant(message.content, toolCalls: message.calls.isEmpty ? nil : message.calls)
                case "tool": return .tool(message.content, id: message.callID)
                default: return .user(message.content)
                }
            }
            if let imageData {
                guard imageData.count <= 32 * 1024 * 1024,
                      let source = CGImageSourceCreateWithData(imageData as CFData, nil),
                      let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceThumbnailMaxPixelSize: 768,
                        kCGImageSourceShouldCacheImmediately: true
                      ] as CFDictionary),
                      let lastUser = chat.lastIndex(where: { $0.role == .user }) else {
                    throw LocalModelError.invalidImage
                }
                chat[lastUser].images = [.ciImage(CIImage(cgImage: thumbnail))]
            }
            let processing = UserInput.Processing(resize: CGSize(width: 768, height: 768), maxPixels: 512 * 1024)
            var input = try await context.processor.prepare(input: UserInput(
                chat: chat, processing: processing, tools: specs.isEmpty ? nil : specs,
                additionalContext: ["enable_thinking": false]))
            // Remove whole old turns, preserving each assistant call and its tool results.
            while input.text.tokens.size > 3072 {
                let users = chat.indices.filter { chat[$0].role == .user }
                if users.count > 1 {
                    chat.removeSubrange(users[0]..<users[1])
                } else {
                    let assistants = chat.indices.filter { chat[$0].role == .assistant }
                    if assistants.count > 1 {
                        chat.removeSubrange(assistants[0]..<assistants[1])
                    } else if let longest = chat.indices.filter({ chat[$0].role == .tool && chat[$0].content.count > 200 })
                        .max(by: { chat[$0].content.count < chat[$1].content.count }) {
                        chat[longest].content = String(chat[longest].content.prefix(chat[longest].content.count / 2)) + "\n（结果已截短）"
                    } else {
                        throw LocalModelError.contextTooLong
                    }
                }
                input = try await context.processor.prepare(input: UserInput(
                    chat: chat, processing: processing, tools: specs.isEmpty ? nil : specs,
                    additionalContext: ["enable_thinking": false]))
            }
            guard LocalMemory.footprint < 5_500_000_000 else { throw LocalModelError.memoryBudget }
            let parameters = GenerateParameters(maxTokens: 1024, temperature: 0.7, topP: 0.8, topK: 20,
                                                 prefill: .init(stepSize: 128))
            let iterator = try TokenIterator(input: input, model: context.model, parameters: parameters)
            let (stream, task) = MLXLMCommon.generateTask(
                promptTokenCount: input.text.tokens.size, modelConfiguration: context.configuration,
                tokenizer: context.tokenizer, iterator: iterator, tools: specs.isEmpty ? nil : specs)
            var reply = LocalReply()
            var failure: Error?
            await withTaskCancellationHandler {
                for await event in stream {
                    if Task.isCancelled { failure = CancellationError(); task.cancel(); break }
                    if LocalMemory.footprint >= 5_800_000_000 { failure = LocalModelError.memoryBudget; task.cancel(); break }
                    switch event {
                    case .chunk(let text): reply.text += text
                    case .toolCall(let call):
                        reply.calls.append(ToolCall(function: call.function, id: call.id ?? UUID().uuidString))
                    case .rejectedToolCall: failure = LocalModelError.invalidToolCall; task.cancel()
                    case .info: break
                    }
                }
                await task.value // no GPU work survives release of the serialization gate
            } onCancel: { task.cancel() }
            if let failure { throw failure }
            try Task.checkCancellation()
            return reply
        }
    }
}

enum LocalMemory {
    static var footprint: UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : 0
    }
}

private extension JSONValue {
    var localSendable: any Sendable {
        switch self {
        case .null: return NSNull()
        case .bool(let value): return value
        case .int(let value): return value
        case .double(let value): return value
        case .string(let value): return value
        case .array(let value): return value.map(\.localSendable)
        case .object(let value): return value.mapValues(\.localSendable)
        }
    }
}
