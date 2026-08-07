import SwiftUI
import AppKit

/// Search Everything（⌥空格）·「懒猫探案」：每次搜索都是一次小型办案——
/// 受理（空状态）→ 布线（证物板）→ 结案（报告 + 盖章）。
/// 证物主要来自花园（~/.dozycat/garden：时间笔记、人物卡、链接卡、小传），
/// 本机文件只在花园之外补位。
struct SearchPanelView: View {
    @ObservedObject private var model = SearchModel.shared
    @FocusState private var focused: Bool
    @State private var peeking = false
    @State private var spinnerVisible = false

    private let panelShape = RoundedRectangle(cornerRadius: 22, style: .continuous)

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // 侦探从面板后面探出头（第一幕 · 受理）
            DeskCat(mood: .curious, size: 60)
                .offset(x: -44, y: peeking ? -2 : 40)
                .opacity(peeking ? 1 : 0)
            panel
        }
        .padding(.top, 30)
        .onAppear {
            focused = true
            model.loadOpenCases()
            // 唤起下落由 CardPanel 在窗口层做；这里只管猫探头
            withAnimation(.spring(response: 0.32, dampingFraction: 0.7).delay(0.18)) { peeking = true }
        }
    }

    private var panel: some View {
        VStack(spacing: 0) {
            searchField
            Group {
                if model.answering || model.caseReport != nil {
                    CaseReportView(model: model)
                } else if model.query.isEmpty {
                    idleView
                } else {
                    EvidenceBoardView(model: model)
                }
            }
            .frame(height: 390, alignment: .top)
            .clipped()
            footer
        }
        .frame(width: 680)
        // 半透明纸面罩在 CardPanel 的 vibrancy 上：既保住纸的暖色，又有真模糊
        .background(panelShape.fill(DS.paper.opacity(0.82)))
        // Find 的轮廓必须是实色。透明只留给面板外的窗口，不让内容边缘发虚。
        .overlay(panelShape.strokeBorder(DS.lineStrong, lineWidth: 1))
        .environment(\.openURL, OpenURLAction { url in
            SearchOpenTarget.open(url: url) ? .handled : .discarded
        })
        .onExitCommand { PetPanels.shared.closeSearch() }
        .onKeyPress(.downArrow) {
            model.moveSelection(by: 1)
            return .handled
        }
        .onKeyPress(.upArrow) {
            model.moveSelection(by: -1)
            return .handled
        }
        .onKeyPress(.tab) {
            guard !model.query.isEmpty, !model.answering else { return .ignored }
            model.askQuestion(force: true)
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

            TextField("想查点什么？人、事，或一种感觉", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 17, weight: .light))
                .foregroundStyle(DS.ink)
                .focused($focused)
                .onSubmit { model.activatePrimaryResult() }

            if spinnerVisible {
                ProgressView()
                    .controlSize(.small)
                    .tint(DS.muted)
            } else if !model.query.isEmpty, model.caseReport == nil {
                Text(verbatim: model.caseCaption)
                    .font(.system(size: 11))
                    .foregroundStyle(DS.faint)
                    .lineLimit(1)
            }

            keycap("esc")
        }
        .padding(.vertical, 17)
        .padding(.horizontal, 20)
        .overlay(alignment: .bottom) { DS.line.frame(height: 1) }
        // 学 sheru：忙碌指示延迟 150ms 才现身，快路径永远不闪 spinner
        .task(id: model.isSearching) {
            guard model.isSearching else {
                spinnerVisible = false
                return
            }
            try? await Task.sleep(nanoseconds: 150_000_000)
            if !Task.isCancelled, model.isSearching { spinnerVisible = true }
        }
    }

    // MARK: - 第一幕 · 受理（空状态）

    private var idleView: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !model.openCases.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("未结的案子")
                        .font(.system(size: 10, weight: .medium))
                        .tracking(2.5)
                        .foregroundStyle(DS.faint)
                    HStack(spacing: 10) {
                        ForEach(Array(model.openCases.enumerated()), id: \.element) { i, name in
                            Button {
                                model.query = name
                            } label: {
                                HStack(spacing: 7) {
                                    Circle()
                                        .fill(i % 2 == 0 ? DS.blue : DS.coral)
                                        .frame(width: 6, height: 6)
                                    Text(verbatim: name)
                                        .font(.system(size: 13))
                                        .foregroundStyle(DS.ink)
                                }
                                .padding(.vertical, 7)
                                .padding(.horizontal, 15)
                                .background(Capsule().stroke(DS.line, lineWidth: 1))
                                .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.top, 18)
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
                DS.lineSoft.frame(height: 1)
            }

            VStack(spacing: 0) {
                idleHint(color: DS.blue, title: "时间笔记",
                         detail: "搜刚刚在哪个 App 里做过什么 · 试试「下午改过的那个文档」",
                         highlighted: true)
                idleHint(color: DS.muted, title: "花园与文件",
                         detail: "人物卡、链接卡和本机文件，回车直接打开",
                         highlighted: false)
                idleHint(color: DS.coral, title: "直接问",
                         detail: "输入完整问题，懒猫替你布线取证 · 试试「上次牙疼是什么时候」",
                         highlighted: false)
            }
            .padding(.top, 10)
            .padding(.horizontal, 12)

            HStack(alignment: .top, spacing: 14) {
                CatFace(size: 30, outlined: true)
                Text("应用、文件路径和链接会直接变成可打开的入口，不用先搜再点。")
                    .font(.system(size: 12))
                    .lineSpacing(4)
                    .foregroundStyle(DS.inkSoft)
                Spacer()
            }
            .padding(.top, 14)
            .padding(.horizontal, 26)
            .overlay(alignment: .top) { DS.lineSoft.frame(height: 1).padding(.horizontal, 12) }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func idleHint(color: Color, title: LocalizedStringKey,
                          detail: LocalizedStringKey, highlighted: Bool) -> some View {
        HStack(spacing: 14) {
            Circle().fill(color).frame(width: 6, height: 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14))
                    .foregroundStyle(DS.ink)
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(DS.muted)
            }
            Spacer()
            if highlighted { keycap("↵") }
        }
        .padding(.vertical, 13)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(highlighted ? DS.lineSoft : Color.clear)
        )
    }

    private var footer: some View {
        HStack(spacing: 14) {
            if model.caseReport != nil {
                keycap("esc")
                Text("结案退出")
            } else if !model.query.isEmpty {
                keycap("↑↓")
                Text("在证物间跳")
                keycap("↵")
                Text(verbatim: model.primaryActionLabel)
                keycap("⇥")
                Text("串线索")
            } else {
                Text("输入即立案 · 文件与回忆一并取证")
            }
            Spacer()
            Image(systemName: "lock")
                .font(.system(size: 9, weight: .semibold))
            Text(model.caseReport != nil ? "报告存档，供《传》取材" : "全程本机办案，卷宗不出门")
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

// MARK: - 第二幕 · 布线（证物板）

/// 点阵软木板：证物一张张钉上（pinDrop 逐张 120ms），红线 900ms 牵完全场。
private struct EvidenceBoardView: View {
    @ObservedObject var model: SearchModel
    @State private var thread: CGFloat = 0

    /// 板上最多 4 张证物 + 1 张推理卡（680×390 空间的固定槽位）。
    private static let slots: [(x: CGFloat, y: CGFloat, w: CGFloat, rot: Double)] = [
        (28, 30, 175, -3), (140, 222, 185, 2), (300, 38, 175, 1.5), (312, 224, 190, -2),
    ]
    private static let inferenceSlot: (x: CGFloat, y: CGFloat, w: CGFloat, rot: Double)
        = (486, 96, 176, 1)

    var body: some View {
        ZStack(alignment: .topLeading) {
            DS.headShade
            dotGrid
            if model.evidence.isEmpty && !model.isSearching {
                emptyView
            } else {
                ThreadShape(points: pinPoints)
                    .trim(from: 0, to: thread)
                    .stroke(DS.coral, style: StrokeStyle(lineWidth: 2, lineCap: .round,
                                                         lineJoin: .round))
                ForEach(Array(model.evidence.enumerated()), id: \.element.id) { i, item in
                    let slot = Self.slots[i]
                    EvidenceCard(item: item, index: i,
                                 selected: model.selectedResultID == item.id,
                                 latest: item.id == model.latestEvidenceID
                                     && model.selectedResultID == nil,
                                 width: slot.w)
                        .rotationEffect(.degrees(slot.rot))
                        .offset(x: slot.x, y: slot.y)
                        .modifier(PinDrop(delay: 0.05 + Double(i) * 0.08))
                        .onTapGesture { model.open(item) }
                        .onHover { inside in if inside { model.selectedResultID = item.id } }
                }
                if !model.evidence.isEmpty {
                    inferenceCard
                        .rotationEffect(.degrees(Self.inferenceSlot.rot))
                        .offset(x: Self.inferenceSlot.x, y: Self.inferenceSlot.y)
                        .modifier(PinDrop(delay: 0.05 + Double(model.evidence.count) * 0.08 + 0.25))
                }
            }
        }
        .frame(width: 680, height: 390)
        // 不用 .id(generation) 炸整棵子树重建：ForEach 按证物 id diff，
        // 留下来的卡不重播钉入动画，只有新卡才落钉；红线单独重牵。
        .onAppear { pullThread() }
        .onChange(of: model.searchGeneration) {
            thread = 0
            pullThread()
        }
    }

    /// 红线 · 钉子落完就开始牵（连续打字时旧线立即归零重来）
    private func pullThread() {
        guard model.evidence.count > 0 else { return }
        withAnimation(.easeInOut(duration: 0.55).delay(0.4)) { thread = 1 }
    }

    /// 证物卡顶部图钉的位置（红线沿钉走）
    private var pinPoints: [CGPoint] {
        var points = model.evidence.indices.map { i -> CGPoint in
            let slot = Self.slots[i]
            return CGPoint(x: slot.x + slot.w / 2, y: slot.y + 2)
        }
        if !model.evidence.isEmpty {
            points.append(CGPoint(x: Self.inferenceSlot.x + Self.inferenceSlot.w / 2,
                                  y: Self.inferenceSlot.y + 2))
        }
        return points
    }

    private var dotGrid: some View {
        Canvas { ctx, size in
            let spacing: CGFloat = 26
            var y: CGFloat = 13
            while y < size.height {
                var x: CGFloat = 13
                while x < size.width {
                    ctx.fill(Path(ellipseIn: CGRect(x: x - 1, y: y - 1, width: 2, height: 2)),
                             with: .color(Color(hex: 0xE4E2DB)))
                    x += spacing
                }
                y += spacing
            }
        }
    }

    private var inferenceCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                CatFace(size: 24, outlined: true)
                Text("本猫的推理")
                    .font(.system(size: 10, weight: .medium))
                    .tracking(2)
                    .foregroundStyle(DS.faint)
            }
            Text(verbatim: model.inferenceHint)
                .font(.system(size: 12, design: .serif))
                .lineSpacing(6)
                .foregroundStyle(Color(hex: 0x43423E))
            Button {
                model.askQuestion(force: true)
            } label: {
                Text("继续查 ⇥")
                    .font(.system(size: 11))
                    .foregroundStyle(DS.paper)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 14)
                    .background(Capsule().fill(DS.ink))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .frame(width: EvidenceBoardView.inferenceSlot.w, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(DS.card)
                .shadow(color: DS.ink.opacity(0.16), radius: 16, y: 10)
        )
        .overlay(alignment: .top) {
            Circle().fill(DS.ink)
                .frame(width: 10, height: 10)
                .shadow(color: DS.ink.opacity(0.35), radius: 2, y: 2)
                .offset(y: -5)
        }
    }

    private var emptyView: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 22))
                .foregroundStyle(DS.faint)
            Text("板上还没钉上证物")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(DS.inkSoft)
            Text("试试更短的关键词，或按 ⇥ 直接让本猫去查。")
                .font(.system(size: 12))
                .foregroundStyle(DS.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 一张证物卡：白卡 + 图钉 + 轻微旋转；最新一件带珊瑚描边（证物 D · 最新）。
private struct EvidenceCard: View {
    let item: SearchModel.Evidence
    let index: Int
    let selected: Bool
    let latest: Bool
    let width: CGFloat

    private static let letters = ["A", "B", "C", "D", "E"]

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Text(verbatim: "证物 \(Self.letters[min(index, 4)]) · \(item.kind.label)")
                    .font(.system(size: 10, weight: .medium))
                    .tracking(1.5)
                    .foregroundStyle(latest ? DS.coral : DS.faint)
                if latest {
                    Text("最新")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(DS.coral)
                }
            }
            if item.kind == .file {
                HStack(spacing: 8) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: item.path ?? ""))
                        .resizable()
                        .scaledToFit()
                        .frame(width: 26, height: 26)
                    Text(verbatim: item.title)
                        .font(.system(size: 13))
                        .foregroundStyle(DS.ink)
                        .lineLimit(2)
                }
            } else if item.kind == .moment || item.kind == .person {
                Text(verbatim: "「\(item.text)」")
                    .font(.system(size: 13, design: .serif))
                    .lineSpacing(5)
                    .foregroundStyle(DS.ink)
                    .lineLimit(3)
            } else {
                if !item.title.isEmpty {
                    Text(verbatim: item.title)
                        .font(.system(size: 13))
                        .foregroundStyle(DS.ink)
                        .lineLimit(1)
                }
                Text(verbatim: item.text)
                    .font(.system(size: 12))
                    .lineSpacing(4)
                    .foregroundStyle(DS.inkSoft)
                    .lineLimit(3)
            }
            Text(verbatim: item.dateLabel)
                .font(.system(size: 11))
                .foregroundStyle(DS.muted)
                .lineLimit(1)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .frame(width: width, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(DS.card)
                .shadow(color: DS.ink.opacity(selected ? 0.2 : 0.12),
                        radius: selected ? 14 : 10, y: selected ? 8 : 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(selected || latest ? DS.coral : .clear, lineWidth: 1.5)
        )
        .overlay(alignment: .top) {
            Circle().fill(DS.coral)
                .frame(width: 10, height: 10)
                .shadow(color: DS.ink.opacity(0.35), radius: 2, y: 2)
                .offset(y: -5)
        }
        .scaleEffect(selected ? 1.03 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: selected)
        .contentShape(Rectangle())
    }
}

/// 证物 · 逐张钉上板（pinDrop：落下 + 从 1.2 缩回）
private struct PinDrop: ViewModifier {
    let delay: Double
    @State private var dropped = false

    func body(content: Content) -> some View {
        content
            .opacity(dropped ? 1 : 0)
            .scaleEffect(dropped ? 1 : 1.2)
            .offset(y: dropped ? 0 : -14)
            .onAppear {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8).delay(delay)) {
                    dropped = true
                }
            }
    }
}

/// 红线：把图钉按顺序连起来
private struct ThreadShape: Shape {
    let points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        return path
    }
}

// MARK: - 第三幕 · 结案（报告 + 盖章）

private struct CaseReportView: View {
    @ObservedObject var model: SearchModel
    @State private var stamped = false

    var body: some View {
        ScrollView {
            if model.answering {
                HStack(alignment: .top, spacing: 14) {
                    CatFace(size: 36, outlined: true)
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("正在取证……翻回忆、笔记和链接卡")
                    }
                    .font(.system(size: 14))
                    .foregroundStyle(DS.mutedWarm)
                    .padding(.top, 5)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 24)
                .padding(.horizontal, 24)
            } else if let report = model.caseReport {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(verbatim: "结案报告 · 案卷 №\(report.seq)「\(report.title)」")
                            .font(.system(size: 16, weight: .semibold, design: .serif))
                            .foregroundStyle(DS.ink)
                        Spacer()
                        Text(verbatim: "取证 \(String(format: "%.1f", report.duration)) 秒 · 证物 \(report.sources.count) 件")
                            .font(.system(size: 11))
                            .foregroundStyle(DS.faint)
                    }
                    .padding(.bottom, 14)
                    .overlay(alignment: .bottom) { DS.lineSoft.frame(height: 1) }

                    ForEach(Array(report.sources.prefix(5).enumerated()), id: \.element.id) { i, hit in
                        sourceRow(index: i, hit: hit)
                            .modifier(PopIn(delay: 0.25 + Double(i) * 0.15))
                    }

                    if let reasoning = report.reasoning {
                        HStack(alignment: .top, spacing: 14) {
                            Text("推理")
                                .font(.system(size: 10, weight: .medium))
                                .tracking(2.5)
                                .foregroundStyle(DS.faint)
                                .padding(.top, 5)
                            Text(verbatim: reasoning)
                                .font(.system(size: 13, design: .serif))
                                .lineSpacing(8)
                                .foregroundStyle(Color(hex: 0x43423E))
                                .textSelection(.enabled)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 14)
                        .overlay(alignment: .bottom) { DS.lineSoft.frame(height: 1) }
                        .modifier(PopIn(delay: 0.25 + Double(min(report.sources.count, 5)) * 0.15))
                    }

                    HStack(alignment: .top, spacing: 14) {
                        Text("结论")
                            .font(.system(size: 10, weight: .medium))
                            .tracking(2.5)
                            .foregroundStyle(DS.faint)
                            .padding(.top, 5)
                        MarkdownText(report.conclusion)
                            .font(.system(size: 14))
                            .lineSpacing(7)
                            .foregroundStyle(DS.ink)
                            .textSelection(.enabled)
                            .padding(.trailing, 100)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 16)
                    .overlay(alignment: .topTrailing) {
                        // 结案章 · 320ms 砸下来
                        Text("本猫断定")
                            .font(.system(size: 13, weight: .semibold, design: .serif))
                            .tracking(3)
                            .foregroundStyle(DS.coral)
                            .padding(.vertical, 7)
                            .padding(.horizontal, 10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(DS.coral, lineWidth: 2.5)
                            )
                            .rotationEffect(.degrees(-8))
                            .opacity(stamped ? 1 : 0)
                            .scaleEffect(stamped ? 1 : 1.9)
                            .padding(.top, 14)
                    }
                    .modifier(PopIn(delay: 0.25 + Double(min(report.sources.count, 5) + 1) * 0.15))

                    if let url = report.fileURL {
                        HStack {
                            Button {
                                NSWorkspace.shared.open(url)
                            } label: {
                                Text("打开卷宗")
                                    .font(.system(size: 12))
                                    .foregroundStyle(DS.inkSoft)
                                    .padding(.vertical, 7)
                                    .padding(.horizontal, 16)
                                    .background(Capsule().stroke(DS.lineStrong, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            Spacer()
                            Text("报告已存档 · 供《传》取材")
                                .font(.system(size: 11))
                                .foregroundStyle(DS.faint)
                        }
                        .padding(.top, 12)
                    }
                }
                .padding(.vertical, 20)
                .padding(.horizontal, 24)
                .onAppear {
                    stamped = false
                    let rows = Double(min(report.sources.count, 5))
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.62)
                        .delay(0.45 + rows * 0.15)) { stamped = true }
                }
            }
        }
        .scrollIndicators(.never)
    }

    private func sourceRow(index: Int, hit: PetStore.MemoryHit) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(verbatim: ["A", "B", "C", "D", "E"][min(index, 4)])
                .font(.system(size: 10, design: .serif))
                .foregroundStyle(DS.inkSoft)
                .frame(width: 22, height: 22)
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(DS.lineStrong, lineWidth: 1.5)
                )
            MarkdownText(hit.text)
                .font(.system(size: 13))
                .lineSpacing(5)
                .foregroundStyle(DS.ink)
            Spacer(minLength: 12)
            Text(verbatim: hit.source)
                .font(.system(size: 11))
                .foregroundStyle(DS.faint)
                .padding(.top, 3)
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { DS.lineSoft.frame(height: 1) }
    }
}

/// 结案报告的行 · 逐行浮上来（popIn 级联）
private struct PopIn: ViewModifier {
    let delay: Double
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 8)
            .onAppear {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85).delay(delay)) {
                    shown = true
                }
            }
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
    let at: Date
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
                return parse(url: item.url, markdown: text, modified: item.modified)
            }
            .prefix(limit)
            .map { $0 }
    }

    private static func parse(url: URL, markdown: String, modified: Date) -> NoteHit {
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

        // 「使用：[App](app://…)」是给 chips 的元信息，卡片白描里不露原始 markdown
        let preview = parsed.body.split(separator: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("使用：") }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let timeRaw = parsed.metadata["time"]?
            .replacingOccurrences(of: "（本地时间）", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let source = timeRaw ?? url.deletingLastPathComponent().lastPathComponent
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        let at = timeRaw.flatMap { formatter.date(from: $0) } ?? modified

        return NoteHit(
            id: url.path,
            filename: url.deletingPathExtension().lastPathComponent,
            source: source,
            preview: preview.isEmpty ? String(localized: "（空白笔记）") : preview,
            path: url.path,
            at: at,
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
    /// 修改时间在 mdfind 的后台队列里取好，主线程组板时不再碰 FileManager。
    var at: Date = .distantPast

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

    /// 一件证物：来自花园（时间笔记/小传/人物卡/链接卡）或本机文件（补位）。
    struct Evidence: Identifiable, Hashable {
        enum Kind: String {
            case note, moment, person, link, file

            var label: String {
                switch self {
                case .note: String(localized: "时间笔记")
                case .moment: String(localized: "倾诉")
                case .person: String(localized: "人物卡")
                case .link: String(localized: "链接")
                case .file: String(localized: "文件")
                }
            }
        }

        let id: String
        let kind: Kind
        let title: String
        let text: String
        let dateLabel: String
        let at: Date
        let path: String?
        let target: SearchOpenTarget?
    }

    /// 结案报告（第三幕）。
    struct CaseReport {
        let seq: Int
        let title: String
        let reasoning: String?
        let conclusion: String
        let sources: [PetStore.MemoryHit]
        let duration: Double
        let fileURL: URL?
    }

    @Published var query = "" {
        didSet { queryChanged() }
    }
    @Published var evidence: [Evidence] = []
    @Published var totalHits = 0
    @Published var selectedResultID: String?
    @Published var caseReport: CaseReport?
    @Published var answering = false
    @Published var isSearching = false
    @Published var openCases: [String] = []
    @Published var searchGeneration = 0

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

    var primaryActionLabel: String {
        if selectedResultID != nil { return String(localized: "打开证物") }
        if isQuestion { return String(localized: "替我找线索") }
        return String(localized: "打开第一件")
    }

    /// 案由「query」· 取证 N 件 · 跨 X
    var caseCaption: String {
        guard totalHits > 0 else { return "" }
        return String(localized: "取证 \(totalHits) 件 · \(spanLabel)")
    }

    var latestEvidenceID: String? {
        evidence.max(by: { $0.at < $1.at })?.id
    }

    var inferenceHint: String {
        if isQuestion {
            return String(localized: "线索都钉上了。要不要我把它们串成一个故事？")
        }
        if let latest = evidence.max(by: { $0.at < $1.at }) {
            return String(localized: "取证 \(totalHits) 件，最新的是\(latest.dateLabel)。要不要我顺着红线查下去？")
        }
        return String(localized: "板上空着。换个词，或者直接问我。")
    }

    private var spanLabel: String {
        guard let min = evidence.map(\.at).min(),
              let max = evidence.map(\.at).max() else { return "" }
        let days = Calendar.current.dateComponents([.day], from: min, to: max).day ?? 0
        if days >= 60 { return String(localized: "跨 \(days / 30) 个月") }
        if days >= 1 { return String(localized: "跨 \(days) 天") }
        return String(localized: "同一天")
    }

    private func queryChanged() {
        caseReport = nil
        searchTask?.cancel()
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else {
            evidence = []
            totalHits = 0
            selectedResultID = nil
            isSearching = false
            return
        }

        selectedResultID = nil

        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled else { return }
            // 防抖期内不算「在搜」；真正开工才亮忙碌态（UI 侧还会再延迟显示）
            self?.isSearching = true
            // 花园是地基：笔记、人物卡、链接卡先搜；小传在主线程（Loro store）
            let moments = Array(PetStore.shared.search(q).prefix(6))
            async let notes = Self.searchNotes(q)
            async let people = Self.searchPeople(q)
            async let links = Self.searchLinks(q)
            async let files = Self.mdfind(q)
            let (noteResults, personResults, linkResults, fileResults) =
                await (notes, people, links, files)
            guard !Task.isCancelled, let self else { return }
            self.assemble(q: q, notes: noteResults, moments: moments,
                          people: personResults, links: linkResults, files: fileResults)
        }
    }

    /// 组板：花园证物按时间取最近 4 件，不够再用本机文件补位；
    /// 板上按时间从旧到新排（红线才有故事线）。
    private func assemble(q: String, notes: [NoteHit], moments: [PetStore.MemoryHit],
                          people: [Evidence], links: [Evidence], files: [FileHit]) {
        var garden: [Evidence] = []
        garden += notes.map { hit in
            Evidence(id: hit.selectionID, kind: .note, title: "",
                     text: hit.preview, dateLabel: Self.dayLabel(hit.at, fallback: hit.source),
                     at: hit.at, path: hit.path,
                     target: SearchOpenTarget(kind: .file, label: hit.filename, value: hit.path))
        }
        garden += moments.map { hit in
            Evidence(id: "moment:\(hit.id)", kind: .moment, title: "",
                     text: hit.text, dateLabel: hit.source, at: hit.at, path: nil, target: nil)
        }
        garden += people
        garden += links

        let picked = garden.sorted { $0.at > $1.at }.prefix(4)
        var board = Array(picked)
        if board.count < 4 {
            for file in files.prefix(4 - board.count) {
                board.append(Evidence(
                    id: file.selectionID, kind: .file, title: file.name,
                    text: file.folder, dateLabel: Self.dayLabel(file.at, fallback: file.folder),
                    at: file.at, path: file.path,
                    target: SearchOpenTarget(kind: .file, label: file.name, value: file.path)))
            }
        }
        board.sort { $0.at < $1.at }

        evidence = board
        totalHits = garden.count + files.count
        isSearching = false
        searchGeneration += 1
        reconcileSelection()
        writeDebugSnapshotIfNeeded()
    }

    nonisolated private static func dayLabel(_ date: Date, fallback: String) -> String {
        guard date != .distantPast else { return fallback }
        if Calendar.current.isDateInToday(date) {
            let f = DateFormatter(); f.dateFormat = "HH:mm"
            return String(localized: "今天 \(f.string(from: date))")
        }
        if Calendar.current.isDateInYesterday(date) {
            let f = DateFormatter(); f.dateFormat = "HH:mm"
            return String(localized: "昨天 \(f.string(from: date))")
        }
        let f = DateFormatter()
        if Locale.preferredLanguages.first?.hasPrefix("zh") == true {
            f.dateFormat = "M月d日"
        } else {
            f.locale = Locale.current
            f.setLocalizedDateFormatFromTemplate("Md")
        }
        return f.string(from: date)
    }

    // MARK: 键盘与打开

    func moveSelection(by offset: Int) {
        let ids = evidence.map(\.id)
        guard !ids.isEmpty else { return }
        guard let selectedResultID, let index = ids.firstIndex(of: selectedResultID) else {
            self.selectedResultID = offset < 0 ? ids.last : ids.first
            return
        }
        self.selectedResultID = ids[(index + offset + ids.count) % ids.count]
    }

    func activatePrimaryResult() {
        if let selectedResultID,
           let item = evidence.first(where: { $0.id == selectedResultID }) {
            open(item)
            return
        }
        if isQuestion {
            askQuestion()
        } else if let first = evidence.first(where: { $0.target != nil }) {
            open(first)
        } else if !query.isEmpty {
            // 板上没证物：直接立案让猫去查
            askQuestion(force: true)
        }
    }

    func open(_ item: Evidence) {
        selectedResultID = item.id
        if let target = item.target {
            target.open()
        } else {
            NSSound.beep()
        }
    }

    /// DEBUG/自动化兼容入口：明确提交问句，不受当前键盘选中项影响。
    func submit() {
        askQuestion(force: true)
    }

    /// 未结的案子：最近更新过的人物卡（空状态 chips）。目录枚举在后台，
    /// 面板唤起的第一帧不给主线程加磁盘 IO。
    func loadOpenCases() {
        Task { [weak self] in
            let names = await Task.detached(priority: .userInitiated) { () -> [String] in
                let fm = FileManager.default
                return Garden.listFiles(Garden.people)
                    .filter { $0.hasSuffix(".md") }
                    .compactMap { file -> (String, Date)? in
                        let url = Garden.people.appendingPathComponent(file)
                        let date = (try? fm.attributesOfItem(atPath: url.path)[.modificationDate] as? Date)
                            ?? .distantPast
                        return (String(file.dropLast(3)), date ?? .distantPast)
                    }
                    .sorted { $0.1 > $1.1 }
                    .prefix(3)
                    .map(\.0)
            }.value
            self?.openCases = names
        }
    }

    // MARK: 第三幕 · 结案（agentic RAG）

    /// 问题交给 searcher agent（多轮翻花园找线索），回来解析成推理/结论并存档卷宗。
    func askQuestion(force: Bool = false) {
        guard force || isQuestion, !answering, !query.isEmpty else { return }
        let q = query
        answering = true
        let started = Date()
        Task {
            defer { answering = false }
            do {
                let result = try await SearcherAgent.run(question: q) { step in
                    NSLog("SearcherAgent step: \(step)")
                }
                let (reasoning, conclusion) = Self.parseVerdict(result.answer)
                let duration = Date().timeIntervalSince(started)
                let seq = Self.nextCaseSeq()
                let title = Self.caseTitle(from: q)
                let fileURL = Self.archiveCase(seq: seq, title: title, question: q,
                                               reasoning: reasoning, conclusion: conclusion,
                                               sources: result.sources, duration: duration)
                caseReport = CaseReport(seq: seq, title: title, reasoning: reasoning,
                                        conclusion: conclusion, sources: result.sources,
                                        duration: duration, fileURL: fileURL)
                if let out = ProcessInfo.processInfo.environment["DOZYCAT_DEBUG_OUT"] {
                    let sources = result.sources.map { "  - \($0.source)：\($0.text)" }.joined(separator: "\n")
                    try? "Q: \(q)\nA: \(result.answer)\nSOURCES:\n\(sources)\n"
                        .write(toFile: out, atomically: true, encoding: .utf8)
                }
            } catch {
                caseReport = CaseReport(
                    seq: UserDefaults.standard.integer(forKey: "dozycat.caseSeq"),
                    title: Self.caseTitle(from: q), reasoning: nil,
                    conclusion: String(localized: "（模型连不上了…先翻给你看我记得的，在下面。）"),
                    sources: Array(PetStore.shared.recent(limit: 5)),
                    duration: Date().timeIntervalSince(started), fileURL: nil)
            }
        }
    }

    /// 「推理：…\n结论：…」→ (推理, 结论)；不带前缀的行都归结论。
    static func parseVerdict(_ raw: String) -> (reasoning: String?, conclusion: String) {
        var reasoning: [String] = []
        var conclusion: [String] = []
        for rawLine in raw.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            if line.hasPrefix("推理：") || line.hasPrefix("推理:") {
                reasoning.append(String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces))
            } else if line.hasPrefix("结论：") || line.hasPrefix("结论:") {
                conclusion.append(String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces))
            } else {
                conclusion.append(line)
            }
        }
        let joined = conclusion.joined(separator: "\n")
        return (reasoning.isEmpty ? nil : reasoning.joined(separator: " "),
                joined.isEmpty ? raw : joined)
    }

    private static func caseTitle(from q: String) -> String {
        let trimmed = q.trimmingCharacters(in: CharacterSet(charactersIn: " ？?。！!"))
        return String(trimmed.prefix(10))
    }

    private static func nextCaseSeq() -> Int {
        let seq = UserDefaults.standard.integer(forKey: "dozycat.caseSeq") + 1
        UserDefaults.standard.set(seq, forKey: "dozycat.caseSeq")
        return seq
    }

    /// 卷宗存档：garden/cases/<日期>-案卷<N>.md，《传》可取材。
    private static func archiveCase(seq: Int, title: String, question: String,
                                    reasoning: String?, conclusion: String,
                                    sources: [PetStore.MemoryHit], duration: Double) -> URL? {
        Garden.ensure()
        let url = Garden.cases.appendingPathComponent("\(Garden.day())-案卷\(seq).md")
        let sourceLines = sources.map { "- \($0.source)：\($0.text)" }.joined(separator: "\n")
        let md = """
        ---
        case: \(seq)
        q: \(question)
        date: \(Garden.day())
        duration: \(String(format: "%.1f", duration))s
        ---
        # 结案报告 · 案卷 №\(seq)「\(title)」

        \(reasoning.map { "推理：\($0)\n" } ?? "")结论：\(conclusion)

        ## 证物
        \(sourceLines.isEmpty ? "（无）" : sourceLines)
        """
        try? md.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func reconcileSelection() {
        let ids = evidence.map(\.id)
        if let selectedResultID, ids.contains(selectedResultID) { return }
        // 完整问句的默认动作应该是「替我找」，只有按方向键/悬停后才打开具体结果。
        selectedResultID = isQuestion ? nil : evidence.first(where: { $0.target != nil })?.id
    }

    // MARK: 花园搜索（people / links / notes）

    nonisolated private static func searchNotes(_ q: String) async -> [NoteHit] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: NoteSearchIndex.search(q))
            }
        }
    }

    nonisolated private static func searchPeople(_ q: String, limit: Int = 3) async -> [Evidence] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let fm = FileManager.default
                var hits: [Evidence] = []
                for file in Garden.listFiles(Garden.people) where file.hasSuffix(".md") {
                    let name = String(file.dropLast(3))
                    let url = Garden.people.appendingPathComponent(file)
                    guard let text = try? String(contentsOf: url, encoding: .utf8),
                          name.localizedCaseInsensitiveContains(q)
                            || text.localizedCaseInsensitiveContains(q) else { continue }
                    let modified = (try? fm.attributesOfItem(atPath: url.path)[.modificationDate] as? Date)
                        .flatMap { $0 } ?? .distantPast
                    // 跳过 frontmatter 块，取正文第一行做白描
                    var lines = text.split(separator: "\n", omittingEmptySubsequences: false)
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                    if lines.first == "---",
                       let end = lines.dropFirst().firstIndex(of: "---") {
                        lines.removeSubrange(0...end)
                    }
                    let preview = lines.first { !$0.isEmpty && !$0.hasPrefix("#") } ?? ""
                    hits.append(Evidence(
                        id: "person:\(name)", kind: .person, title: name,
                        text: preview.isEmpty ? name : preview,
                        dateLabel: dayLabel(modified, fallback: name),
                        at: modified, path: url.path,
                        target: SearchOpenTarget(kind: .file, label: name, value: url.path)))
                    if hits.count >= limit { break }
                }
                continuation.resume(returning: hits)
            }
        }
    }

    nonisolated private static func searchLinks(_ q: String, limit: Int = 3) async -> [Evidence] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var hits: [Evidence] = []
                for file in Garden.listFiles(Garden.links) where file.hasSuffix(".md") {
                    let name = String(file.dropLast(3))
                    let url = Garden.links.appendingPathComponent(file)
                    guard let text = try? String(contentsOf: url, encoding: .utf8),
                          name.localizedCaseInsensitiveContains(q)
                            || text.localizedCaseInsensitiveContains(q) else { continue }
                    var target = "", date = "", why = ""
                    for line in text.split(separator: "\n") {
                        if line.hasPrefix("target:") {
                            target = line.dropFirst("target:".count).trimmingCharacters(in: .whitespaces)
                        } else if line.hasPrefix("date:") {
                            date = line.dropFirst("date:".count).trimmingCharacters(in: .whitespaces)
                        } else if line.hasPrefix("why:") {
                            why = line.dropFirst("why:".count).trimmingCharacters(in: .whitespaces)
                        }
                    }
                    let open: SearchOpenTarget? = target.isEmpty ? nil
                        : target.hasPrefix("/") || target.hasPrefix("~")
                            ? SearchOpenTarget(kind: .file, label: name, value: target)
                            : SearchOpenTarget(kind: .web, label: name, value: target)
                    let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
                    let at = f.date(from: date) ?? .distantPast
                    hits.append(Evidence(
                        id: "link:\(name)", kind: .link, title: name,
                        text: why.isEmpty ? target : why,
                        dateLabel: dayLabel(at, fallback: date.isEmpty ? name : date),
                        at: at, path: nil, target: open))
                    if hits.count >= limit { break }
                }
                continuation.resume(returning: hits)
            }
        }
    }

    /// Spotlight 文件搜索（mdfind，本机完成）：花园之外的补位证物。
    /// 完整路径输入会优先直接命中。
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
                    let at = (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date) ?? .distantPast
                    return FileHit(
                        name: url.lastPathComponent,
                        folder: url.deletingLastPathComponent().path
                            .replacingOccurrences(of: NSHomeDirectory(), with: "~"),
                        path: url.path,
                        at: at ?? .distantPast
                    )
                }
                continuation.resume(returning: Array(hits.prefix(6)))
            }
        }
    }

    private func writeDebugSnapshotIfNeeded() {
        #if DEBUG
        guard let path = ProcessInfo.processInfo.environment["DOZYCAT_SEARCH_DEBUG_OUT"] else { return }
        let lines = evidence.map { item in
            switch item.kind {
            case .note:
                "NOTE|\(item.dateLabel)|\(item.path.map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent } ?? "")|\(item.target.map { "\($0.kind.rawValue):\($0.label)=\($0.value)" } ?? "")"
            case .file:
                "FILE|\(item.title)|\(item.path ?? "")"
            default:
                "\(item.kind.rawValue.uppercased())|\(item.dateLabel)|\(item.title)|\(item.text.prefix(60))"
            }
        }
        try? lines.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
        #endif
    }
}
