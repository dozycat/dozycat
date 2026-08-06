import SwiftUI

/// 能量胶囊 — 悬停猫猫才出现，数字平时藏起来（设计稿「能量刻度」）。
struct EnergyCapsule: View {
    @ObservedObject private var feed = SenseFeed.shared

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                row(label: "心理能量", value: feed.mind, color: DS.blue, warn: false)
                bar(value: feed.mind, color: DS.blue)
                row(label: "生理能量", value: feed.phys, color: DS.coral, warn: feed.phys < 50)
                bar(value: feed.phys, color: DS.coral)
                Text(tip)
                    .font(.system(size: 12))
                    .lineSpacing(4)
                    .foregroundStyle(DS.inkSoft)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 10)
                    .overlay(alignment: .top) { DS.lineSoft.frame(height: 1) }
            }
            .padding(16)
            .frame(width: 220)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(DS.paper)
                .shadow(color: DS.ink.opacity(0.16), radius: 22, y: 16))

            DS.lineStrong.frame(width: 1, height: 14)
        }
    }

    private var tip: LocalizedStringKey {
        if feed.phys < 50 { return "久坐掉的。站起来 3 分钟就能回 10 点" }
        if feed.mind < 50 { return "心理有点耗。跟我说说，或者出去走走？" }
        return "状态不错。保持这个节奏就好"
    }

    private func row(label: LocalizedStringKey, value: Int, color: Color, warn: Bool) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(.system(size: 11)).tracking(2.2).foregroundStyle(DS.muted)
            Spacer()
            Text("\(value)")
                .font(.system(size: 15, weight: .light))
                .foregroundStyle(warn ? color : DS.ink)
        }
    }

    private func bar(value: Int, color: Color) -> some View {
        GeometryReader { geo in
            Capsule().fill(DS.bg)
                .overlay(alignment: .leading) {
                    Capsule().fill(color)
                        .frame(width: geo.size.width * CGFloat(min(max(value, 0), 100)) / 100)
                }
        }
        .frame(height: 3)
    }
}

/// 提醒卡 — 右上角滑入，20 秒后自己走（设计稿「提醒」）。
struct ReminderCard: View {
    let message: String
    let countLine: String
    var onGo: () -> Void
    var onSnooze: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                CatFace(size: 40, outlined: true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(message)
                        .font(.system(size: 14))
                        .lineSpacing(5)
                        .foregroundStyle(DS.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(countLine)
                        .font(.system(size: 12))
                        .foregroundStyle(DS.muted)
                }
            }
            HStack(spacing: 10) {
                Button("这就去", action: onGo).buttonStyle(SmallInkPill())
                Button("3 分钟后", action: onSnooze).buttonStyle(SmallGhostPill())
            }
            .padding(.leading, 54)
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 20)
        .frame(width: 360, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(DS.paper)
            .shadow(color: DS.ink.opacity(0.16), radius: 25, y: 20))
    }
}

struct SmallInkPill: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13)).foregroundStyle(DS.paper)
            .padding(.vertical, 8).padding(.horizontal, 18)
            .background(Capsule().fill(DS.ink))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

struct SmallGhostPill: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13)).foregroundStyle(DS.inkSoft)
            .padding(.vertical, 8).padding(.horizontal, 18)
            .background(Capsule().stroke(DS.lineStrong, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// 对话 widget — 点猫猫展开，随手一句话的地方（设计稿「对话」）。
struct ChatWidget: View {
    @ObservedObject private var chat = PetChat.shared
    @State private var draft = ""
    @FocusState private var focused: Bool
    var onCollapse: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {
                        ForEach(chat.messages) { message in
                            bubble(message).id(message.id)
                        }
                        if let note = chat.memoryNote {
                            HStack(spacing: 8) {
                                DS.blue.frame(width: 10, height: 1)
                                Text(note).font(.system(size: 11)).foregroundStyle(DS.blue)
                                Spacer()
                            }
                            .padding(.leading, 2)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.vertical, 18)
                    .padding(.horizontal, 20)
                }
                .frame(height: 240)
                .onChange(of: chat.messages.count) {
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("bottom") }
                }
            }
            inputBar
        }
        .frame(width: 380)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(DS.paper)
            .shadow(color: DS.ink.opacity(0.16), radius: 26, y: 20))
        .onAppear { focused = true }
    }

    private var header: some View {
        HStack(spacing: 12) {
            CatFace(size: 34, outlined: true)
            VStack(alignment: .leading, spacing: 1) {
                Text("懒猫").font(.system(size: 14, weight: .medium)).foregroundStyle(DS.ink)
                Text("一直都在").font(.system(size: 11)).foregroundStyle(DS.muted)
            }
            Spacer()
            Button(action: onCollapse) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 11))
                    .foregroundStyle(DS.faint)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 20)
        .overlay(alignment: .bottom) { DS.line.frame(height: 1) }
    }

    @ViewBuilder
    private func bubble(_ message: ChatMessage) -> some View {
        if message.role == .cat {
            Text(message.text)
                .font(.system(size: 14)).lineSpacing(5).foregroundStyle(DS.ink)
                .padding(.vertical, 11).padding(.horizontal, 15)
                .background(UnevenRoundedRectangle(
                    topLeadingRadius: 4, bottomLeadingRadius: 16,
                    bottomTrailingRadius: 16, topTrailingRadius: 16,
                    style: .continuous).fill(DS.lineSoft))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 56)
        } else {
            Text(message.text)
                .font(.system(size: 14)).lineSpacing(5).foregroundStyle(DS.paper)
                .padding(.vertical, 11).padding(.horizontal, 15)
                .background(UnevenRoundedRectangle(
                    topLeadingRadius: 16, bottomLeadingRadius: 16,
                    bottomTrailingRadius: 16, topTrailingRadius: 4,
                    style: .continuous).fill(DS.ink))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.leading, 56)
        }
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("随便说点什么", text: $draft)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(DS.ink)
                .focused($focused)
                .onSubmit(send)
            Button(action: send) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(DS.coral))
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 16)
        .padding(.trailing, 7)
        .padding(.vertical, 7)
        .overlay(RoundedRectangle(cornerRadius: 999).stroke(DS.lineStrong, lineWidth: 1))
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .padding(.top, 4)
    }

    private func send() {
        chat.send(draft)
        draft = ""
    }
}

/// 桌面对话的模型层：BYOK LLM + 真记忆——聊天带小传上下文，
/// 每轮对话后抽取值得记住的小事写入 dozycat-core。
@MainActor
final class PetChat: ObservableObject {
    static let shared = PetChat()

    @Published var messages: [ChatMessage] = [
        ChatMessage(role: .cat, text: String(localized: "嗨，我在呢。想说什么都行。")),
    ]
    @Published var memoryNote: String?

    func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        messages.append(ChatMessage(role: .me, text: trimmed))
        guard let config = SettingsStore.shared.llmConfig else {
            messages.append(ChatMessage(role: .cat, text: String(localized: "嗯嗯，我听着呢。不用急，慢慢说。")))
            return
        }
        let history = messages.suffix(12).map {
            (role: $0.role == .cat ? "assistant" : "user", content: $0.text)
        }
        let memoryContext = PetStore.shared.recent(limit: 8)
            .map { "\($0.source)：\($0.text)" }
            .joined(separator: "\n")
        var system = LLMClient.persona
        if !memoryContext.isEmpty {
            system += "\n\n你记得的关于用户的小传（可自然引用，不要逐条复述）：\n" + memoryContext
        }
        system += "\n\n如果这轮聊到了值得记进小传的一件小事（事实、情绪或约定），调用 save_moment 存下来（白描 ≤40 字 + 两三个字的情绪 note），不用告诉用户你存了。闲聊不存。"

        let saveTool = AgentTool(
            name: "save_moment",
            description: "把这轮对话里值得记住的一件小事存进用户的小传",
            parameters: ["text": ["type": "string"], "note": ["type": "string"]]
        ) { [weak self] args in
            guard let text = args["text"] as? String, !text.isEmpty else { return "text 缺失" }
            PetStore.shared.addMemory(text: text, note: args["note"] as? String)
            self?.memoryNote = String(localized: "它记下了：\(text)")
            return "已记下"
        }

        Task {
            do {
                let reply = try await PiAgent.run(system: system, history: history,
                                                  tools: [saveTool], config: config, maxSteps: 4)
                messages.append(ChatMessage(role: .cat, text: reply))
            } catch {
                messages.append(ChatMessage(
                    role: .cat,
                    text: String(localized: "（模型连不上了…没关系，我自己也能陪你。）")))
            }
        }
    }
}

/// ChatMessage 的桌面副本（iOS 的定义在 AppModel.swift，未共享进 pet target）。
struct ChatMessage: Identifiable, Equatable {
    enum Role { case cat, me }
    let id = UUID()
    let role: Role
    let text: String
}
