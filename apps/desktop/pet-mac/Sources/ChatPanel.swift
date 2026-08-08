import SwiftUI

/// 对话 widget——点猫猫展开，随手一句话的地方（设计稿「对话」）。
struct ChatMsg: Identifiable, Equatable {
    enum Role { case me, cat }

    let id = UUID()
    let role: Role
    var text: String
    /// 「它记下了：……」——这轮对话里存进小传的小事。
    var memoryRef: String?
}

@MainActor
final class ChatModel: ObservableObject {
    static let shared = ChatModel()

    @Published var messages: [ChatMsg] = [
        ChatMsg(role: .cat, text: String(localized: "我在。想到哪儿说到哪儿就好。"), memoryRef: nil)
    ]
    @Published var thinking = false

    /// 真 pi 的持久续聊 session：一次运行一条线（~/.pi 里可翻）。
    private let sessionID = UUID().uuidString
    private var savedThisTurn: String?

    func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !thinking else { return }
        messages.append(ChatMsg(role: .me, text: trimmed, memoryRef: nil))
        thinking = true
        Task {
            defer { thinking = false }
            await reply(to: trimmed)
        }
    }

    private func reply(to text: String) async {
        // 真 pi 优先：session 落 ~/.pi，值得记的小事经 moments_inbox 交接入库
        if PiCLI.available {
            Garden.ensure()
            MomentsBridge.writeSnapshot()
            let system = LLMClient.persona + """


            工作目录是懒猫的花园，moments_snapshot.md 是你记得的小传（可自然引用，不要逐条复述）。
            \(MomentsBridge.howToSave)只在聊到值得记的事实、情绪或约定时才存，闲聊不存，也不用告诉用户你存了。
            """
            if let out = await PiCLI.run(name: "dozycat·聊天", system: system,
                                         prompt: text, cwd: Garden.root,
                                         sessionID: sessionID, timeout: 120) {
                let saved = MomentsBridge.ingest()
                messages.append(ChatMsg(
                    role: .cat, text: out,
                    memoryRef: saved.first.map { String(localized: "它记下了：\($0)") }
                ))
                return
            }
        }

        // 内置回路（自定义端点 / 没装 pi）：带小传上下文 + save_moment 工具
        guard let config = SettingsStore.shared.llmConfig else {
            messages.append(ChatMsg(
                role: .cat,
                text: String(localized: "（要先在设置里配一个模型，我才能接上话。）"),
                memoryRef: nil
            ))
            return
        }
        let history = messages.suffix(12).map {
            (role: $0.role == .cat ? "assistant" : "user", content: $0.text)
        }
        var system = LLMClient.persona
        let memoryContext = PetStore.shared.recent(limit: 8)
            .map { "\($0.source)：\($0.text)" }
            .joined(separator: "\n")
        if !memoryContext.isEmpty {
            system += "\n\n你记得的关于用户的小传（可自然引用，不要逐条复述）：\n" + memoryContext
        }
        system += "\n\n如果这轮聊到了值得记进小传的一件小事（事实、情绪或约定），调用 save_moment 存下来（白描 ≤40 字 + 两三个字的情绪 note），不用告诉用户你存了。闲聊不存。"
        savedThisTurn = nil
        let saveTool = AgentTool(
            name: "save_moment",
            description: "把这轮对话里值得记住的一件小事存进用户的小传",
            parameters: ["text": ["type": "string"], "note": ["type": "string"]]
        ) { [weak self] args in
            guard let text = args["text"] as? String, !text.isEmpty else { return "text 缺失" }
            PetStore.shared.addMemory(text: text, note: args["note"] as? String)
            self?.savedThisTurn = text
            return "已记下"
        }
        do {
            let reply = try await PiAgent.run(system: system, history: history,
                                              tools: [saveTool], config: config, maxSteps: 4)
            messages.append(ChatMsg(
                role: .cat, text: reply,
                memoryRef: savedThisTurn.map { String(localized: "它记下了：\($0)") }
            ))
        } catch {
            messages.append(ChatMsg(
                role: .cat,
                text: String(localized: "（模型连不上了…没关系，我自己也能陪你。）"),
                memoryRef: nil
            ))
        }
    }
}

struct ChatPanelView: View {
    @ObservedObject private var model = ChatModel.shared
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(model.messages) { message in
                            bubble(message).id(message.id)
                        }
                        if model.thinking { thinkingBubble }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 18)
                }
                .scrollIndicators(.never)
                .onChange(of: model.messages.count) { _, _ in
                    withAnimation(.easeOut(duration: 0.25)) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
                .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            inputBar
        }
        .frame(width: 380, height: 480)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(DS.paper.opacity(0.82)))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .strokeBorder(DS.lineStrong, lineWidth: 1))
        .onAppear { focused = true }
        .onExitCommand { PetPanels.shared.closeChat() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            CatFace(size: 34, outlined: true)
            VStack(alignment: .leading, spacing: 1) {
                Text("懒猫").font(.system(size: 14, weight: .medium)).foregroundStyle(DS.ink)
                Text("一直都在").font(.system(size: 11)).foregroundStyle(DS.muted)
            }
            Spacer()
            Button {
                PetPanels.shared.closeChat()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DS.faint)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("收起")
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 20)
        .overlay(alignment: .bottom) { DS.line.frame(height: 1) }
    }

    @ViewBuilder
    private func bubble(_ message: ChatMsg) -> some View {
        if message.role == .cat {
            VStack(alignment: .leading, spacing: 8) {
                Text(verbatim: message.text)
                    .font(.system(size: 14))
                    .lineSpacing(5)
                    .foregroundStyle(DS.ink)
                    .padding(.vertical, 11)
                    .padding(.horizontal, 15)
                    .background(
                        UnevenRoundedRectangle(
                            topLeadingRadius: 4, bottomLeadingRadius: 16,
                            bottomTrailingRadius: 16, topTrailingRadius: 16,
                            style: .continuous
                        )
                        .fill(DS.lineSoft)
                    )
                    .textSelection(.enabled)
                if let ref = message.memoryRef {
                    HStack(spacing: 8) {
                        DS.blue.frame(width: 10, height: 1)
                        Text(verbatim: ref)
                            .font(.system(size: 11))
                            .foregroundStyle(DS.blue)
                    }
                    .padding(.leading, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 48)
        } else {
            Text(verbatim: message.text)
                .font(.system(size: 14))
                .lineSpacing(5)
                .foregroundStyle(DS.paper)
                .padding(.vertical, 11)
                .padding(.horizontal, 15)
                .background(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 16, bottomLeadingRadius: 16,
                        bottomTrailingRadius: 16, topTrailingRadius: 4,
                        style: .continuous
                    )
                    .fill(DS.ink)
                )
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.leading, 48)
        }
    }

    private var thinkingBubble: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.mini)
            Text("懒猫想了想…")
                .font(.system(size: 12))
                .foregroundStyle(DS.mutedWarm)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 4)
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("随便说点什么", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(DS.ink)
                .focused($focused)
                .lineLimit(1...4)
                .onKeyPress { press in
                    guard press.key == .return else { return .ignored }
                    if press.modifiers.contains(.shift) { return .ignored }
                    sendDraft()
                    return .handled
                }
            Button(action: sendDraft) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(DS.coral))
            }
            .buttonStyle(.plain)
            .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            .help("发送（Return）；Shift-Return 换行")
        }
        .padding(.leading, 16)
        .padding(.trailing, 7)
        .padding(.vertical, 7)
        .overlay(Capsule().stroke(DS.lineStrong, lineWidth: 1))
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .padding(.top, 4)
    }

    private func sendDraft() {
        let text = draft
        draft = ""
        model.send(text)
    }
}

#Preview {
    ChatPanelView()
}
