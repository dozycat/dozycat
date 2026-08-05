import SwiftUI

struct ChatView: View {
    @EnvironmentObject private var model: AppModel
    @State private var draft = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 14) {
                        Text(dayLabel)
                            .font(.system(size: 11))
                            .tracking(1.6)
                            .foregroundStyle(DS.faint)
                            .padding(.top, 8)

                        ForEach(model.messages) { message in
                            bubble(message).id(message.id)
                        }

                        if let replies = model.quickReplies {
                            quickReplyRow(replies)
                        }

                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.horizontal, 28)
                    .padding(.bottom, 12)
                }
                .onChange(of: model.messages.count) { _, _ in
                    withAnimation(.easeOut(duration: 0.25)) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }
            inputBar
        }
        .background(DS.paper)
    }

    private var dayLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return String(localized: "今天 \(formatter.string(from: Date()))")
    }

    // MARK: 顶栏

    private var header: some View {
        HStack(spacing: 12) {
            CatFace(size: 44, outlined: true)
            VStack(alignment: .leading, spacing: 2) {
                Text("懒猫")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(DS.ink)
                Text("一直都在")
                    .font(.system(size: 12))
                    .foregroundStyle(DS.muted)
            }
            Spacer()
        }
        .padding(.horizontal, 28)
        .padding(.top, 8)
        .padding(.bottom, 14)
        .overlay(alignment: .bottom) { DS.line.frame(height: 1) }
    }

    // MARK: 气泡

    @ViewBuilder
    private func bubble(_ message: ChatMessage) -> some View {
        if message.role == .cat {
            VStack(alignment: .leading, spacing: 8) {
                Text(message.text)
                    .font(.system(size: 15))
                    .lineSpacing(7)
                    .foregroundStyle(DS.ink)
                    .padding(.vertical, 14)
                    .padding(.horizontal, 18)
                    .background(
                        UnevenRoundedRectangle(
                            topLeadingRadius: 4, bottomLeadingRadius: 20,
                            bottomTrailingRadius: 20, topTrailingRadius: 20,
                            style: .continuous
                        )
                        .fill(DS.lineSoft)
                    )
                if let ref = message.memoryRef {
                    HStack(spacing: 8) {
                        DS.blue.frame(width: 12, height: 1)
                        Text(ref)
                            .font(.system(size: 12))
                            .foregroundStyle(DS.blue)
                    }
                    .padding(.leading, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 56)
        } else {
            Text(message.text)
                .font(.system(size: 15))
                .lineSpacing(7)
                .foregroundStyle(DS.paper)
                .padding(.vertical, 14)
                .padding(.horizontal, 18)
                .background(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 20, bottomLeadingRadius: 20,
                        bottomTrailingRadius: 20, topTrailingRadius: 4,
                        style: .continuous
                    )
                    .fill(DS.ink)
                )
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.leading, 56)
        }
    }

    private func quickReplyRow(_ replies: [String]) -> some View {
        HStack(spacing: 10) {
            ForEach(replies, id: \.self) { reply in
                Button {
                    model.tapQuickReply(reply)
                } label: {
                    Text(reply)
                        .font(.system(size: 13))
                        .foregroundStyle(reply == replies.first ? DS.ink : DS.inkSoft)
                        .padding(.vertical, 9)
                        .padding(.horizontal, 18)
                        .background(Capsule().stroke(DS.lineStrong, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.top, 2)
    }

    // MARK: 输入

    private var inputBar: some View {
        HStack(spacing: 12) {
            TextField("随便说点什么", text: $draft, axis: .vertical)
                .font(.system(size: 14))
                .lineLimit(1...4)
                .focused($inputFocused)
                .foregroundStyle(DS.ink)
            Button(action: sendDraft) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(DS.coral))
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 20)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 27, style: .continuous)
                .stroke(DS.lineStrong, lineWidth: 1)
        )
        .padding(.horizontal, 28)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private func sendDraft() {
        model.send(draft)
        draft = ""
    }
}

#Preview {
    RootView()
}
