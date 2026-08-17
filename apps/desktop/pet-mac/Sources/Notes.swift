import SwiftUI

/// 记事本——和懒猫的沟通方式：你记，它读。
/// 不是实时对话（那太吵），是一本随手写的便签本：你想到什么写一句，
/// 落进花园（jots/<日期>.md），懒猫做梦时会翻，把值得记的收进小传、
/// 该跟进的记下来。写完就走，它自己消化，不打断你。
struct Jot: Identifiable, Equatable {
    let id: String       // "<date>#<行号>"，稳定不重排
    let at: Date
    let text: String
}

@MainActor
final class NotesStore: ObservableObject {
    static let shared = NotesStore()

    @Published private(set) var jots: [Jot] = []

    private var dir: URL { Garden.root.appendingPathComponent("jots") }

    private init() { reload() }

    /// 最近三天的便签，按时间倒序（新的在上）。
    func reload() {
        var all: [Jot] = []
        for offset in 0..<3 {
            let day = Garden.day(Date().addingTimeInterval(Double(-offset) * 86400))
            let url = dir.appendingPathComponent("\(day).md")
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            for (i, line) in text.split(separator: "\n", omittingEmptySubsequences: true).enumerated() {
                guard let jot = Self.parse(String(line), day: day, index: i) else { continue }
                all.append(jot)
            }
        }
        jots = all.sorted { $0.at > $1.at }
    }

    /// 记一条：追加进当天的便签文件（一行一条，带本地时间），懒猫稍后读。
    func write(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        Garden.ensure()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let now = Date()
        let hm = DateFormatter(); hm.dateFormat = "HH:mm"
        // 一行一条，换行折成空格——便签是碎的，不留多行噪音
        let flat = text.replacingOccurrences(of: "\n", with: " ")
        let line = "- \(hm.string(from: now))｜\(flat)\n"
        let url = dir.appendingPathComponent("\(Garden.day(now)).md")
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
        reload()
    }

    /// "- HH:mm｜正文" → Jot。时间搭上当天的日期还原成绝对时刻。
    private static func parse(_ line: String, day: String, index: Int) -> Jot? {
        var s = line
        if s.hasPrefix("- ") { s.removeFirst(2) }
        guard let bar = s.firstIndex(where: { $0 == "｜" || $0 == "|" }) else { return nil }
        let hm = String(s[s.startIndex..<bar]).trimmingCharacters(in: .whitespaces)
        let body = String(s[s.index(after: bar)...]).trimmingCharacters(in: .whitespaces)
        guard !body.isEmpty else { return nil }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm"
        let at = f.date(from: "\(day) \(hm)") ?? Date.distantPast
        return Jot(id: "\(day)#\(index)", at: at, text: body)
    }
}

struct NotesPanelView: View {
    @ObservedObject private var store = NotesStore.shared
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            entries
            inputBar
        }
        .frame(width: 380, height: 480)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(DS.paper.opacity(0.82)))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .strokeBorder(DS.lineStrong, lineWidth: 1))
        .onExitCommand { PetPanels.shared.closeNotes() }
        .onAppear { focused = true; store.reload() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            CatFace(size: 34, outlined: true)
            VStack(alignment: .leading, spacing: 1) {
                Text("记事本").font(.system(size: 14, weight: .medium)).foregroundStyle(DS.ink)
                Text("你记，我读").font(.system(size: 11)).foregroundStyle(DS.muted)
            }
            Spacer()
            Button {
                PetPanels.shared.closeNotes()
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
    private var entries: some View {
        if store.jots.isEmpty {
            VStack(spacing: 10) {
                Spacer()
                Text("想到什么，写一句给我。")
                    .font(.system(size: 13)).foregroundStyle(DS.muted)
                Text("我做梦时会翻，值得记的替你记住。")
                    .font(.system(size: 12)).foregroundStyle(DS.faint)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(store.jots) { jot in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(verbatim: jot.text)
                                .font(.system(size: 14))
                                .lineSpacing(4)
                                .foregroundStyle(DS.ink)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                            Text(verbatim: Self.stamp(jot.at))
                                .font(.system(size: 10)).foregroundStyle(DS.faint)
                        }
                        .padding(.vertical, 11).padding(.horizontal, 14)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(DS.card))
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
            }
            .scrollIndicators(.never)
        }
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("写一句…", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(DS.ink)
                .lineLimit(1...4)
                .focused($focused)
                .onSubmit(save)
            Button(action: save) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(DS.coral))
            }
            .buttonStyle(.plain)
            .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.leading, 16).padding(.trailing, 7).padding(.vertical, 7)
        .overlay(Capsule().stroke(DS.lineStrong, lineWidth: 1))
        .padding(.horizontal, 16).padding(.bottom, 16).padding(.top, 4)
    }

    private func save() {
        let text = draft
        draft = ""
        store.write(text)
    }

    private static func stamp(_ date: Date) -> String {
        let cal = Calendar.current
        let hm = DateFormatter(); hm.dateFormat = "HH:mm"
        if cal.isDateInToday(date) { return String(localized: "今天 \(hm.string(from: date))") }
        if cal.isDateInYesterday(date) { return String(localized: "昨天 \(hm.string(from: date))") }
        let f = DateFormatter(); f.dateFormat = "M月d日 HH:mm"
        return f.string(from: date)
    }
}
