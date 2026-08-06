import SwiftUI
import AppKit

/// Search Everything（⌥空格）：回忆、时间笔记与本机文件在同一个稳定的面板里混排。
struct SearchPanelView: View {
    @ObservedObject private var model = SearchModel.shared
    @FocusState private var focused: Bool

    private let panelShape = RoundedRectangle(cornerRadius: 22, style: .continuous)

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Group {
                if model.isQuestion, model.answer != nil || model.answering {
                    answerView
                } else if model.query.isEmpty {
                    idleView
                } else {
                    resultsView
                }
            }
            .frame(height: 390, alignment: .top)
            .clipped()
            footer
        }
        .frame(width: 680)
        .background(panelShape.fill(DS.paper))
        // Find 的轮廓必须是实色。透明只留给面板外的窗口，不让内容边缘发虚。
        .overlay(panelShape.strokeBorder(DS.lineStrong, lineWidth: 1))
        .environment(\.openURL, OpenURLAction { url in
            SearchOpenTarget.open(url: url) ? .handled : .discarded
        })
        .onAppear { focused = true }
        .onExitCommand { PetPanels.shared.closeSearch() }
        .onKeyPress(.downArrow) {
            model.moveSelection(by: 1)
            return .handled
        }
        .onKeyPress(.upArrow) {
            model.moveSelection(by: -1)
            return .handled
        }
    }

    private var searchField: some View {
        HStack(spacing: 14) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DS.inkSoft)
                .frame(width: 32, height: 32)
                .background(Circle().fill(DS.bg))

            TextField("搜索回忆、时间笔记、应用或文件", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 17))
                .foregroundStyle(DS.ink)
                .focused($focused)
                .onSubmit { model.activatePrimaryResult() }

            if model.isSearching {
                ProgressView()
                    .controlSize(.small)
                    .tint(DS.muted)
            } else if !model.query.isEmpty {
                Button {
                    model.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(DS.faint)
                }
                .buttonStyle(.plain)
                .help("清空")
            }

            keycap("esc")
        }
        .padding(.vertical, 17)
        .padding(.horizontal, 20)
        .overlay(alignment: .bottom) { DS.line.frame(height: 1) }
    }

    private var idleView: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 6) {
                Text("从刚刚做过的事开始找")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(DS.ink)
                Text("应用、文件路径和 Markdown 链接会直接变成可打开的入口。")
                    .font(.system(size: 13))
                    .foregroundStyle(DS.mutedWarm)
            }

            VStack(spacing: 0) {
                idleHint(icon: "clock.arrow.circlepath", title: "时间笔记",
                         detail: "搜刚刚在哪个 App 里做过什么")
                DS.lineSoft.frame(height: 1).padding(.leading, 42)
                idleHint(icon: "doc.text.magnifyingglass", title: "本机文件",
                         detail: "按文件名查找，回车直接打开")
                DS.lineSoft.frame(height: 1).padding(.leading, 42)
                idleHint(icon: "sparkles", title: "直接问",
                         detail: "输入完整问题，让懒猫替你翻线索")
            }
            .padding(.horizontal, 14)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(DS.bg.opacity(0.58)))
        }
        .padding(.top, 42)
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func idleHint(icon: String, title: LocalizedStringKey, detail: LocalizedStringKey) -> some View {
        HStack(spacing: 13) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(DS.blue)
                .frame(width: 28)
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DS.ink)
                .frame(width: 74, alignment: .leading)
            Text(detail)
                .font(.system(size: 12))
                .foregroundStyle(DS.mutedWarm)
            Spacer()
        }
        .padding(.vertical, 13)
    }

    // MARK: - 混排结果

    private var resultsView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if !model.noteHits.isEmpty {
                    sectionLabel("时间笔记", count: model.noteHits.count)
                    ForEach(model.noteHits) { hit in
                        noteRow(hit)
                        rowDivider(after: hit.id, in: model.noteHits.map(\.id))
                    }
                }

                if !model.memoryHits.isEmpty {
                    sectionLabel("回忆", count: model.memoryHits.count)
                    ForEach(model.memoryHits.prefix(6)) { hit in
                        memoryRow(hit)
                    }
                }

                if !model.fileHits.isEmpty {
                    sectionLabel("文件与应用", count: model.fileHits.count)
                    ForEach(model.fileHits) { file in
                        fileRow(file)
                    }
                }

                if model.noteHits.isEmpty && model.memoryHits.isEmpty && model.fileHits.isEmpty && !model.isSearching {
                    ContentUnavailableView {
                        Label("没找到", systemImage: "magnifyingglass")
                    } description: {
                        if model.isQuestion {
                            Text("按回车，我再替你翻一遍线索。")
                        } else {
                            Text("试试更短的关键词，或直接输入完整问题。")
                        }
                    }
                    .foregroundStyle(DS.mutedWarm)
                    .padding(.top, 72)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 14)
        }
        .scrollIndicators(.never)
    }

    private func sectionLabel(_ title: LocalizedStringKey, count: Int) -> some View {
        HStack(spacing: 8) {
            Text(title)
            Text(verbatim: "\(count)")
                .foregroundStyle(DS.faint)
            Spacer()
        }
        .font(.system(size: 10, weight: .medium))
        .tracking(2.1)
        .foregroundStyle(DS.mutedWarm)
        .padding(.top, 16)
        .padding(.bottom, 7)
        .padding(.horizontal, 12)
    }

    private func noteRow(_ hit: NoteHit) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                model.openNote(hit)
            } label: {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 8) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(DS.blue)
                        Text(verbatim: hit.source)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(DS.inkSoft)
                        Spacer()
                        Text(verbatim: hit.filename)
                            .font(.system(size: 11))
                            .foregroundStyle(DS.faint)
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(DS.faint)
                    }
                    MarkdownText(hit.preview)
                        .font(.system(size: 14))
                        .lineSpacing(4)
                        .foregroundStyle(DS.ink)
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !hit.targets.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 7) {
                        ForEach(hit.targets.prefix(5)) { target in
                            targetChip(target)
                        }
                    }
                }
                .scrollIndicators(.never)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(resultBackground(id: hit.selectionID))
        .onHover { inside in if inside { model.selectedResultID = hit.selectionID } }
    }

    private func memoryRow(_ hit: PetStore.MemoryHit) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Circle().fill(DS.blue).frame(width: 6, height: 6).padding(.top, 7)
            VStack(alignment: .leading, spacing: 4) {
                MarkdownText(hit.text)
                    .font(.system(size: 14))
                    .lineSpacing(4)
                    .foregroundStyle(DS.ink)
                HStack(spacing: 7) {
                    Text(verbatim: hit.source)
                    if let note = hit.note, !note.isEmpty {
                        Text(verbatim: "·")
                        Text(verbatim: note)
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(DS.muted)
            }
            Spacer()
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 14)
    }

    private func fileRow(_ file: FileHit) -> some View {
        Button {
            model.openFile(file)
        } label: {
            HStack(spacing: 13) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: file.path))
                    .resizable()
                    .scaledToFit()
                    .frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: file.name)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(DS.ink)
                        .lineLimit(1)
                    Text(verbatim: file.folder)
                        .font(.system(size: 11))
                        .foregroundStyle(DS.mutedWarm)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Text(verbatim: file.ext.uppercased())
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(DS.mutedWarm)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 7)
                    .background(Capsule().fill(DS.bg))
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(DS.faint)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .contentShape(Rectangle())
            .background(resultBackground(id: file.selectionID))
        }
        .buttonStyle(.plain)
        .onHover { inside in if inside { model.selectedResultID = file.selectionID } }
    }

    private func targetChip(_ target: SearchOpenTarget) -> some View {
        Button {
            target.open()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: target.systemImage)
                    .font(.system(size: 10, weight: .semibold))
                Text(verbatim: target.label)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(DS.inkSoft)
            .padding(.vertical, 6)
            .padding(.horizontal, 9)
            .background(Capsule().fill(DS.bg))
            .overlay(Capsule().stroke(DS.lineStrong, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help(target.help)
    }

    @ViewBuilder
    private func rowDivider(after id: String, in ids: [String]) -> some View {
        if id != ids.last {
            DS.lineSoft.frame(height: 1).padding(.horizontal, 14)
        }
    }

    private func resultBackground(id: String) -> some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(model.selectedResultID == id ? DS.bg : Color.clear)
    }

    // MARK: - RAG 回答

    private var answerView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 14) {
                    CatFace(size: 36, outlined: true)
                    if model.answering {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("正在翻回忆和时间笔记……")
                        }
                        .font(.system(size: 14))
                        .foregroundStyle(DS.mutedWarm)
                        .padding(.top, 5)
                    } else if let answer = model.answer {
                        MarkdownText(answer)
                            .font(.system(size: 15))
                            .lineSpacing(6)
                            .foregroundStyle(DS.ink)
                            .padding(.top, 2)
                            .textSelection(.enabled)
                    }
                    Spacer(minLength: 0)
                }

                if !model.answerSources.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        sectionLabel("依据", count: model.answerSources.count)
                        ForEach(model.answerSources) { hit in
                            memoryRow(hit)
                        }
                    }
                    .overlay(alignment: .top) { DS.lineSoft.frame(height: 1) }
                }
            }
            .padding(.vertical, 22)
            .padding(.horizontal, 24)
        }
        .scrollIndicators(.never)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            keycap("↵")
            Text(verbatim: model.primaryActionLabel)
            if model.hasActionableResults {
                keycap("↑↓")
                Text("选择")
            }
            Spacer()
            Image(systemName: "lock")
                .font(.system(size: 9, weight: .semibold))
            Text("笔记与文件搜索只在本机完成")
        }
        .font(.system(size: 11))
        .foregroundStyle(DS.mutedWarm)
        .padding(.vertical, 11)
        .padding(.horizontal, 20)
        .overlay(alignment: .top) { DS.line.frame(height: 1) }
    }

    private func keycap(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(DS.mutedWarm)
            .padding(.vertical, 3)
            .padding(.horizontal, 7)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(DS.bg))
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).stroke(DS.lineStrong, lineWidth: 1))
    }
}

/// SwiftUI 原生 AttributedString 渲染 inline Markdown；解析失败时退回原文。
private struct MarkdownText: View {
    let attributed: AttributedString

    init(_ markdown: String) {
        attributed = (try? AttributedString(
            markdown: markdown,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(markdown)
    }

    var body: some View { Text(attributed) }
}

// MARK: - 可打开目标

struct SearchOpenTarget: Identifiable, Hashable {
    enum Kind: String { case app, file, web }

    let kind: Kind
    let label: String
    /// app = bundle id / app name；file = 绝对路径；web = URL 字符串。
    let value: String

    var id: String { "\(kind.rawValue):\(value)" }
    var systemImage: String {
        switch kind {
        case .app: "app.dashed"
        case .file: "doc"
        case .web: "link"
        }
    }
    var help: String {
        switch kind {
        case .app: String(localized: "打开应用：\(label)")
        case .file: String(localized: "打开文件：\(value)")
        case .web: String(localized: "打开链接：\(value)")
        }
    }

    @MainActor
    func open() {
        switch kind {
        case .app:
            if let url = Self.applicationURL(identifierOrName: value, displayName: label) {
                NSWorkspace.shared.open(url)
            } else {
                NSSound.beep()
            }
        case .file:
            let expanded = (value as NSString).expandingTildeInPath
            let url = URL(fileURLWithPath: expanded).standardizedFileURL
            guard FileManager.default.fileExists(atPath: url.path) else {
                NSSound.beep()
                return
            }
            NSWorkspace.shared.open(url)
        case .web:
            guard let url = URL(string: value), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
                NSSound.beep()
                return
            }
            NSWorkspace.shared.open(url)
        }
    }

    @MainActor
    static func open(url: URL) -> Bool {
        switch url.scheme?.lowercased() {
        case "app":
            let identifier = String(url.absoluteString.dropFirst("app://".count))
                .removingPercentEncoding ?? ""
            SearchOpenTarget(kind: .app, label: identifier, value: identifier).open()
            return true
        case "file":
            SearchOpenTarget(kind: .file, label: url.lastPathComponent, value: url.path).open()
            return true
        case "http", "https":
            SearchOpenTarget(kind: .web, label: url.host ?? url.absoluteString,
                             value: url.absoluteString).open()
            return true
        default:
            return false
        }
    }

    private static func applicationURL(identifierOrName: String, displayName: String) -> URL? {
        if identifierOrName.contains("."),
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifierOrName) {
            return url
        }
        if let running = NSWorkspace.shared.runningApplications.first(where: {
            $0.localizedName?.localizedCaseInsensitiveCompare(identifierOrName) == .orderedSame
                || $0.localizedName?.localizedCaseInsensitiveCompare(displayName) == .orderedSame
        }), let url = running.bundleURL {
            return url
        }
        let names = [identifierOrName, displayName].filter { !$0.isEmpty }
        let roots = [
            (NSHomeDirectory() as NSString).appendingPathComponent("Applications"),
            "/Applications", "/System/Applications", "/System/Applications/Utilities",
        ]
        for name in names {
            for root in roots {
                let url = URL(fileURLWithPath: root).appendingPathComponent("\(name).app")
                if FileManager.default.fileExists(atPath: url.path) { return url }
            }
        }
        return nil
    }

    static func markdownTarget(label: String, rawTarget: String, relativeTo directory: URL) -> SearchOpenTarget? {
        let raw = rawTarget.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }

        if raw.lowercased().hasPrefix("app://") {
            let value = String(raw.dropFirst("app://".count)).removingPercentEncoding ?? ""
            return value.isEmpty ? nil : SearchOpenTarget(kind: .app, label: label, value: value)
        }
        if raw.lowercased().hasPrefix("file://") {
            let decoded = String(raw.dropFirst("file://".count)).removingPercentEncoding
                ?? String(raw.dropFirst("file://".count))
            let path = decoded.hasPrefix("/") ? decoded : "/" + decoded
            return SearchOpenTarget(kind: .file, label: label, value: path)
        }
        if raw.lowercased().hasPrefix("http://") || raw.lowercased().hasPrefix("https://") {
            return SearchOpenTarget(kind: .web, label: label, value: raw)
        }
        if raw.hasPrefix("/") || raw.hasPrefix("~/") {
            let expanded = (raw as NSString).expandingTildeInPath
            return SearchOpenTarget(kind: .file, label: label, value: expanded)
        }
        // 相对路径只按 note 所在目录解析，不交给 shell，也不允许其它 scheme。
        if !raw.contains("://") {
            let url = directory.appendingPathComponent(raw).standardizedFileURL
            if FileManager.default.fileExists(atPath: url.path) {
                return SearchOpenTarget(kind: .file, label: label, value: url.path)
            }
        }
        return nil
    }
}

// MARK: - Note 索引

struct NoteHit: Identifiable, Hashable {
    let id: String
    let filename: String
    let source: String
    let preview: String
    let path: String
    let targets: [SearchOpenTarget]

    var selectionID: String { "note:\(path)" }
}

private enum NoteSearchIndex {
    static func search(_ query: String, limit: Int = 6) -> [NoteHit] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }

        let keys: Set<URLResourceKey> = [.isRegularFileKey, .contentModificationDateKey]
        guard let enumerator = FileManager.default.enumerator(
            at: Garden.notes,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var candidates: [(url: URL, modified: Date)] = []
        while let url = enumerator.nextObject() as? URL {
            guard url.pathExtension.lowercased() == "md",
                  let values = try? url.resourceValues(forKeys: keys),
                  values.isRegularFile == true else { continue }
            candidates.append((url, values.contentModificationDate ?? .distantPast))
        }

        return candidates
            .sorted { $0.modified > $1.modified }
            .compactMap { item -> NoteHit? in
                guard let text = try? String(contentsOf: item.url, encoding: .utf8),
                      text.localizedCaseInsensitiveContains(needle) else { return nil }
                return parse(url: item.url, markdown: text)
            }
            .prefix(limit)
            .map { $0 }
    }

    private static func parse(url: URL, markdown: String) -> NoteHit {
        let parsed = frontMatterAndBody(markdown)
        let appName = parsed.metadata["app"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let bundleID = parsed.metadata["appBundleID"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var targets = markdownTargets(in: parsed.body, relativeTo: url.deletingLastPathComponent())

        if !appName.isEmpty {
            let appTarget = SearchOpenTarget(kind: .app, label: appName,
                                             value: bundleID.isEmpty ? appName : bundleID)
            if !targets.contains(where: { $0.kind == .app && $0.value == appTarget.value }) {
                targets.insert(appTarget, at: 0)
            }
        }

        for key in ["file", "path", "filePath"] {
            guard let raw = parsed.metadata[key],
                  let target = SearchOpenTarget.markdownTarget(
                    label: URL(fileURLWithPath: raw).lastPathComponent,
                    rawTarget: raw,
                    relativeTo: url.deletingLastPathComponent()
                  ), !targets.contains(where: { $0.id == target.id }) else { continue }
            targets.append(target)
        }

        let preview = parsed.body.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = parsed.metadata["time"]?
            .replacingOccurrences(of: "（本地时间）", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? url.deletingLastPathComponent().lastPathComponent

        return NoteHit(
            id: url.path,
            filename: url.deletingPathExtension().lastPathComponent,
            source: source,
            preview: preview.isEmpty ? String(localized: "（空白笔记）") : preview,
            path: url.path,
            targets: Array(targets.prefix(8))
        )
    }

    private static func frontMatterAndBody(_ markdown: String) -> (metadata: [String: String], body: String) {
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---",
              let end = lines.dropFirst().firstIndex(where: {
                  $0.trimmingCharacters(in: .whitespaces) == "---"
              }) else { return ([:], markdown) }

        var metadata: [String: String] = [:]
        for line in lines[1..<end] {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            metadata[key] = value
        }
        return (metadata, lines[(end + 1)...].joined(separator: "\n"))
    }

    private static func markdownTargets(in markdown: String, relativeTo directory: URL) -> [SearchOpenTarget] {
        let pattern = #"\[([^\]]+)\]\(([^\)]+)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = markdown as NSString
        var targets: [SearchOpenTarget] = []
        for match in regex.matches(in: markdown, range: NSRange(location: 0, length: ns.length)) {
            guard match.numberOfRanges == 3 else { continue }
            let label = ns.substring(with: match.range(at: 1))
            let raw = ns.substring(with: match.range(at: 2))
            guard let target = SearchOpenTarget.markdownTarget(label: label, rawTarget: raw,
                                                                relativeTo: directory),
                  !targets.contains(where: { $0.id == target.id }) else { continue }
            targets.append(target)
        }

        // 兼容旧 note 中没有 Markdown 包装的绝对路径。
        let barePattern = #"(?<![A-Za-z0-9])(~\/|\/)(?:[^\s\]\[\)\(<>\"']+)"#
        if let regex = try? NSRegularExpression(pattern: barePattern) {
            for match in regex.matches(in: markdown, range: NSRange(location: 0, length: ns.length)) {
                var raw = ns.substring(with: match.range)
                raw = raw.trimmingCharacters(in: CharacterSet(charactersIn: ".,，。:：;；"))
                let expanded = (raw as NSString).expandingTildeInPath
                guard FileManager.default.fileExists(atPath: expanded) else { continue }
                let label = URL(fileURLWithPath: expanded).lastPathComponent
                let target = SearchOpenTarget(kind: .file, label: label, value: expanded)
                if !targets.contains(where: { $0.id == target.id }) { targets.append(target) }
            }
        }
        return targets
    }
}

// MARK: - 模型

struct FileHit: Identifiable, Hashable {
    let name: String
    let folder: String
    let path: String

    var id: String { path }
    var selectionID: String { "file:\(path)" }
    var ext: String {
        let value = (name as NSString).pathExtension
        return value.isEmpty ? "FILE" : value
    }
}

@MainActor
final class SearchModel: ObservableObject {
    static let shared = SearchModel()

    @Published var query = "" {
        didSet { queryChanged() }
    }
    @Published var memoryHits: [PetStore.MemoryHit] = []
    @Published var noteHits: [NoteHit] = []
    @Published var fileHits: [FileHit] = []
    @Published var selectedResultID: String?
    @Published var answer: String?
    @Published var answering = false
    @Published var answerSources: [PetStore.MemoryHit] = []
    @Published var isSearching = false

    private var searchTask: Task<Void, Never>?

    var isQuestion: Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count > 4 else { return false }
        if q.contains("？") || q.contains("?") { return true }
        if ["吗", "呢", "没", "了没", "来着"].contains(where: { q.hasSuffix($0) }) { return true }
        let markers = ["什么", "怎么", "多少", "上次", "哪", "为什么", "是不是", "有没有", "记得",
                       "when", "what", "how", "where", "did i", "do i"]
        return markers.contains { q.lowercased().contains($0) }
    }

    var hasActionableResults: Bool { !actionableResultIDs.isEmpty }
    var primaryActionLabel: String {
        if selectedResultID != nil { return String(localized: "打开") }
        if isQuestion { return String(localized: "替我找线索") }
        return String(localized: "打开第一项")
    }

    private var actionableResultIDs: [String] {
        noteHits.map(\.selectionID) + fileHits.map(\.selectionID)
    }

    private func queryChanged() {
        answer = nil
        answerSources = []
        searchTask?.cancel()
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else {
            memoryHits = []
            noteHits = []
            fileHits = []
            selectedResultID = nil
            isSearching = false
            return
        }

        memoryHits = Array(PetStore.shared.search(q).prefix(6))
        noteHits = []
        fileHits = []
        selectedResultID = nil
        isSearching = true

        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled else { return }
            async let notes = Self.searchNotes(q)
            async let files = Self.mdfind(q)
            let (noteResults, fileResults) = await (notes, files)
            guard !Task.isCancelled, let self else { return }
            self.noteHits = noteResults
            self.fileHits = fileResults
            self.isSearching = false
            self.reconcileSelection()
            self.writeDebugSnapshotIfNeeded()
        }
    }

    func moveSelection(by offset: Int) {
        let ids = actionableResultIDs
        guard !ids.isEmpty else { return }
        guard let selectedResultID, let index = ids.firstIndex(of: selectedResultID) else {
            self.selectedResultID = offset < 0 ? ids.last : ids.first
            return
        }
        self.selectedResultID = ids[(index + offset + ids.count) % ids.count]
    }

    func activatePrimaryResult() {
        if let selectedResultID {
            if let note = noteHits.first(where: { $0.selectionID == selectedResultID }) {
                openNote(note)
                return
            }
            if let file = fileHits.first(where: { $0.selectionID == selectedResultID }) {
                openFile(file)
                return
            }
        }
        if isQuestion {
            askQuestion()
        } else if let first = noteHits.first {
            openNote(first)
        } else if let first = fileHits.first {
            openFile(first)
        }
    }

    /// DEBUG/自动化兼容入口：明确提交问句，不受当前键盘选中项影响。
    func submit() {
        askQuestion()
    }

    func openNote(_ note: NoteHit) {
        NSWorkspace.shared.open(URL(fileURLWithPath: note.path))
    }

    func openFile(_ file: FileHit) {
        NSWorkspace.shared.open(URL(fileURLWithPath: file.path))
    }

    /// 问题交给 searcher agent（agentic RAG——多轮翻小传/笔记/人物卡/文件找线索）。
    private func askQuestion() {
        guard isQuestion, !answering else { return }
        let q = query
        answerSources = []
        answering = true
        Task {
            defer { answering = false }
            do {
                let result = try await SearcherAgent.run(question: q) { step in
                    NSLog("SearcherAgent step: \(step)")
                }
                answer = result.answer
                answerSources = result.sources
                if let out = ProcessInfo.processInfo.environment["DOZYCAT_DEBUG_OUT"] {
                    let sources = result.sources.map { "  - \($0.source)：\($0.text)" }.joined(separator: "\n")
                    try? "Q: \(q)\nA: \(result.answer)\nSOURCES:\n\(sources)\n"
                        .write(toFile: out, atomically: true, encoding: .utf8)
                }
            } catch {
                answer = String(localized: "（模型连不上了…先翻给你看我记得的，在下面。）")
                answerSources = Array(PetStore.shared.recent(limit: 5))
            }
        }
    }

    private func reconcileSelection() {
        let ids = actionableResultIDs
        if let selectedResultID, ids.contains(selectedResultID) { return }
        // 完整问句的默认动作应该是「替我找」，只有按方向键/悬停后才打开具体结果。
        selectedResultID = isQuestion ? nil : ids.first
    }

    nonisolated private static func searchNotes(_ q: String) async -> [NoteHit] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: NoteSearchIndex.search(q))
            }
        }
    }

    /// Spotlight 文件搜索（mdfind，本机完成）。完整路径输入会优先直接命中。
    nonisolated static func mdfind(_ q: String) async -> [FileHit] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let expanded = (q as NSString).expandingTildeInPath
                var paths: [String] = []
                if (q.hasPrefix("/") || q.hasPrefix("~/")),
                   FileManager.default.fileExists(atPath: expanded) {
                    paths.append(URL(fileURLWithPath: expanded).standardizedFileURL.path)
                }

                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
                // 单引号不会进入 shell；这里只是 Spotlight 查询字符串。
                let escaped = q.replacingOccurrences(of: "'", with: "\\'")
                proc.arguments = ["-onlyin", NSHomeDirectory(), "kMDItemFSName == '*\(escaped)*'cd"]
                let pipe = Pipe()
                proc.standardOutput = pipe
                proc.standardError = FileHandle.nullDevice
                do {
                    try proc.run()
                    let deadline = Date().addingTimeInterval(2)
                    while proc.isRunning && Date() < deadline { usleep(50_000) }
                    if proc.isRunning { proc.terminate() }
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    paths.append(contentsOf: String(decoding: data, as: UTF8.self)
                        .split(separator: "\n").prefix(10).map(String.init))
                } catch {}

                var seen = Set<String>()
                let hits = paths.compactMap { path -> FileHit? in
                    let url = URL(fileURLWithPath: path).standardizedFileURL
                    guard seen.insert(url.path).inserted else { return nil }
                    return FileHit(
                        name: url.lastPathComponent,
                        folder: url.deletingLastPathComponent().path
                            .replacingOccurrences(of: NSHomeDirectory(), with: "~"),
                        path: url.path
                    )
                }
                continuation.resume(returning: Array(hits.prefix(6)))
            }
        }
    }

    private func writeDebugSnapshotIfNeeded() {
        #if DEBUG
        guard let path = ProcessInfo.processInfo.environment["DOZYCAT_SEARCH_DEBUG_OUT"] else { return }
        let lines = noteHits.map { hit in
            let targets = hit.targets.map { "\($0.kind.rawValue):\($0.label)=\($0.value)" }.joined(separator: ",")
            return "NOTE|\(hit.source)|\(hit.filename)|\(targets)"
        } + fileHits.map { "FILE|\($0.name)|\($0.path)" }
        try? lines.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
        #endif
    }
}
