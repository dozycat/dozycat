import SwiftUI
import AppKit

/// Search Everything（⌥空格）：左路搜本机文件与回忆混排，右路直接问问题
/// —— RAG 从回忆里作答（设计稿「SEARCH EVERYTHING」）。
struct SearchPanelView: View {
    @ObservedObject private var model = SearchModel.shared
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchField
            if model.isQuestion, model.answer != nil || model.answering {
                answerView
            } else if !model.query.isEmpty {
                resultsView
            }
            footer
        }
        .frame(width: 640)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(DS.paper)
            .shadow(color: DS.ink.opacity(0.18), radius: 32, y: 24))
        .onAppear { focused = true }
    }

    private var searchField: some View {
        HStack(spacing: 14) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16))
                .foregroundStyle(DS.muted)
            TextField("找点什么，或者直接问", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 17, weight: .light))
                .foregroundStyle(DS.ink)
                .focused($focused)
                .onSubmit { model.submit() }
            Text(verbatim: "esc")
                .font(.system(size: 11))
                .foregroundStyle(DS.faint)
                .padding(.vertical, 3).padding(.horizontal, 8)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(DS.line, lineWidth: 1))
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 24)
        .overlay(alignment: .bottom) {
            if !model.query.isEmpty { DS.line.frame(height: 1) }
        }
    }

    // MARK: 混排结果

    private var resultsView: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !model.memoryHits.isEmpty {
                sectionLabel("回忆")
                ForEach(model.memoryHits) { hit in
                    memoryRow(hit)
                }
            }
            if !model.fileHits.isEmpty {
                sectionLabel("文件")
                    .overlay(alignment: .top) {
                        if !model.memoryHits.isEmpty { DS.lineSoft.frame(height: 1) }
                    }
                ForEach(model.fileHits) { file in
                    fileRow(file)
                }
            }
            if model.memoryHits.isEmpty && model.fileHits.isEmpty {
                Text("没找到。直接问问它？")
                    .font(.system(size: 13))
                    .foregroundStyle(DS.faint)
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
    }

    private func sectionLabel(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.system(size: 10))
            .tracking(2.5)
            .foregroundStyle(DS.faint)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func memoryRow(_ hit: PetStore.MemoryHit) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Circle().fill(DS.blue).frame(width: 6, height: 6).padding(.top, 7)
            VStack(alignment: .leading, spacing: 3) {
                Text(hit.text).font(.system(size: 14)).lineSpacing(4).foregroundStyle(DS.ink)
                Text(hit.source).font(.system(size: 12)).foregroundStyle(DS.muted)
            }
            Spacer()
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
    }

    private func fileRow(_ file: FileHit) -> some View {
        HStack(spacing: 14) {
            Text(verbatim: file.ext.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(DS.inkSoft)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 8).fill(DS.bg))
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: file.name).font(.system(size: 14)).foregroundStyle(DS.ink)
                Text(verbatim: file.folder).font(.system(size: 12)).foregroundStyle(DS.muted)
            }
            Spacer()
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .contentShape(Rectangle())
        .onTapGesture { NSWorkspace.shared.open(URL(fileURLWithPath: file.path)) }
    }

    // MARK: RAG 回答

    private var answerView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                CatFace(size: 36, outlined: true)
                if model.answering {
                    Text("想一下……")
                        .font(.system(size: 15))
                        .foregroundStyle(DS.muted)
                        .padding(.top, 2)
                } else if let answer = model.answer {
                    Text(answer)
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
                    Text("它想起来的依据")
                        .font(.system(size: 10)).tracking(2.5).foregroundStyle(DS.faint)
                        .padding(.vertical, 6)
                    ForEach(model.answerSources) { hit in
                        HStack(alignment: .top, spacing: 14) {
                            Circle().fill(DS.blue).frame(width: 6, height: 6).padding(.top, 7)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(hit.text).font(.system(size: 13)).foregroundStyle(DS.ink)
                                Text(hit.source).font(.system(size: 12)).foregroundStyle(DS.muted)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 8)
                    }
                }
                .overlay(alignment: .top) { DS.lineSoft.frame(height: 1) }
            }
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 24)
    }

    private var footer: some View {
        HStack(spacing: 18) {
            Text("↵ 打开").font(.system(size: 11)).foregroundStyle(DS.faint)
            Text("esc 关闭").font(.system(size: 11)).foregroundStyle(DS.faint)
            Spacer()
            Text("回忆搜索在本机完成，不上传")
                .font(.system(size: 11)).foregroundStyle(DS.muted)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 24)
        .overlay(alignment: .top) {
            if !model.query.isEmpty { DS.line.frame(height: 1) }
        }
    }
}

// MARK: - 模型

struct FileHit: Identifiable {
    let id = UUID()
    let name: String
    let folder: String
    let path: String
    var ext: String { (name as NSString).pathExtension.isEmpty ? "?" : (name as NSString).pathExtension }
}

@MainActor
final class SearchModel: ObservableObject {
    static let shared = SearchModel()

    @Published var query = "" {
        didSet { queryChanged() }
    }
    @Published var memoryHits: [PetStore.MemoryHit] = []
    @Published var fileHits: [FileHit] = []
    @Published var answer: String?
    @Published var answering = false
    @Published var answerSources: [PetStore.MemoryHit] = []

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

    private func queryChanged() {
        answer = nil
        answerSources = []
        searchTask?.cancel()
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else {
            memoryHits = []; fileHits = []
            return
        }
        memoryHits = PetStore.shared.search(q)
        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000) // debounce
            guard !Task.isCancelled else { return }
            let hits = await Self.mdfind(q)
            guard !Task.isCancelled else { return }
            self?.fileHits = hits
        }
    }

    /// 回车：问题交给 searcher agent（agentic RAG——多轮翻小传/笔记/人物卡/文件找线索）。
    func submit() {
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

    /// Spotlight 文件搜索（mdfind，本机完成）。searcher agent 也用它。
    nonisolated static func mdfind(_ q: String) async -> [FileHit] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
                proc.arguments = ["-onlyin", NSHomeDirectory(),
                                  "kMDItemFSName == '*\(q)*'cd"]
                let pipe = Pipe()
                proc.standardOutput = pipe
                proc.standardError = FileHandle.nullDevice
                var hits: [FileHit] = []
                do {
                    try proc.run()
                    let deadline = Date().addingTimeInterval(2)
                    while proc.isRunning && Date() < deadline {
                        usleep(50_000)
                    }
                    if proc.isRunning { proc.terminate() }
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let paths = String(decoding: data, as: UTF8.self)
                        .split(separator: "\n").prefix(5)
                    hits = paths.map { path in
                        let p = String(path)
                        let url = URL(fileURLWithPath: p)
                        return FileHit(
                            name: url.lastPathComponent,
                            folder: url.deletingLastPathComponent().path
                                .replacingOccurrences(of: NSHomeDirectory(), with: "~"),
                            path: p
                        )
                    }
                } catch {}
                continuation.resume(returning: hits)
            }
        }
    }
}
