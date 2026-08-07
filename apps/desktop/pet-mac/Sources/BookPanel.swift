import SwiftUI

/// 《传》的宋体（macOS 自带 Songti SC；缺了就回落系统衬线）。
private func serif(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
    .custom("Songti SC", size: size).weight(weight)
}

/// 《传》正文书页：左边深色书脊（竖排书名 + 猫 + 传印），右边当前一回。
/// 点书脊上的「传」印在正文和目录之间切换。
struct BookPanelView: View {
    @ObservedObject private var bio = BiographyStore.shared
    @State private var currentID: String?
    @State private var showTOC = false
    @State private var tocVolume: Int?

    private var current: BioChapter? {
        currentID.flatMap { id in bio.chapters.first { $0.id == id } } ?? bio.latest
    }

    var body: some View {
        HStack(spacing: 0) {
            spine
            Group {
                if bio.chapters.isEmpty {
                    emptyState
                } else if showTOC {
                    tocView
                } else if let chapter = current {
                    readingView(chapter)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: 760, height: 520)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(DS.paper.opacity(0.82)))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .strokeBorder(DS.lineStrong, lineWidth: 1))
        .onExitCommand { PetPanels.shared.closeBook() }
    }

    // MARK: 书脊

    private var spine: some View {
        VStack {
            HStack(alignment: .top, spacing: 18) {
                verticalText(volumeLine, font: .system(size: 12), spacing: 4,
                             color: Color(hex: 0x8B8B93))
                    .padding(.top, 6)
                verticalText(bio.bookTitle ?? String(localized: "还没有名字的一本"),
                             font: serif(30, weight: .semibold), spacing: 10, color: DS.nightInk)
            }
            .padding(.top, 36)
            Spacer()
            VStack(spacing: 14) {
                CatFace(size: 52)
                Button {
                    withAnimation(.easeOut(duration: 0.18)) { showTOC.toggle() }
                } label: {
                    Text(verbatim: "传")
                        .font(serif(11))
                        .foregroundStyle(DS.coral)
                        .frame(width: 22, height: 22)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(DS.coral, lineWidth: 1.5))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(showTOC ? "回到正文" : "目录")
            }
            .padding(.bottom, 30)
        }
        .frame(width: 176)
        .frame(maxHeight: .infinity)
        // 书脊是深色书皮的固有色，不随外观反色（暗色下反白会变成一条亮带）
        .background(DS.night)
    }

    private var volumeLine: String {
        let vol = current.map { bio.volume(of: $0) } ?? 1
        return String(localized: "懒猫 记 · 卷\(ChineseNumeral.ordinal(vol))")
    }

    private func verticalText(_ text: String, font: Font, spacing: CGFloat,
                              color: Color) -> some View {
        VStack(spacing: spacing) {
            ForEach(Array(text.enumerated()), id: \.offset) { _, ch in
                if ch == " " {
                    Spacer().frame(height: spacing * 2)
                } else {
                    Text(verbatim: String(ch)).font(font)
                }
            }
        }
        .foregroundStyle(color)
    }

    // MARK: 正文

    private func readingView(_ chapter: BioChapter) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: String(localized: "第\(ChineseNumeral.ordinal(chapter.index))回 · \(chapter.title)"))
                    .font(serif(21, weight: .semibold))
                    .foregroundStyle(DS.ink)
                Spacer()
                Text(verbatim: chapter.yearMonthLabel
                    + (chapter.done ? "" : String(localized: " · 连载中")))
                    .font(.system(size: 12))
                    .foregroundStyle(DS.faint)
            }
            .padding(.bottom, 6)
            Text(verbatim: chapter.sources)
                .font(.system(size: 12))
                .foregroundStyle(DS.muted)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .bottom) { DS.lineSoft.frame(height: 1) }

            ScrollView {
                Text(verbatim: chapter.body)
                    .font(serif(15))
                    .foregroundStyle(Color(light: 0x43423E, dark: 0xC9C8C2))
                    .lineSpacing(15)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 20)
                    .textSelection(.enabled)
            }
            .scrollIndicators(.never)

            HStack {
                pagerButton(chapterBefore, edge: .leading)
                Spacer()
                HStack(spacing: 5) {
                    ForEach(dotIDs, id: \.self) { id in
                        Circle()
                            .fill(id == chapter.id ? DS.coral : DS.lineStrong)
                            .frame(width: 5, height: 5)
                    }
                }
                Spacer()
                if let next = chapterAfter {
                    pagerButton(next, edge: .trailing)
                } else {
                    Text(chapter.done ? "全书至此" : "待续 ›")
                        .font(.system(size: 12))
                        .foregroundStyle(DS.faint)
                }
            }
            .padding(.top, 18)
        }
        .padding(.vertical, 32)
        .padding(.horizontal, 40)
    }

    private var chapterBefore: BioChapter? {
        guard let chapter = current,
              let i = bio.chapters.firstIndex(of: chapter), i > 0 else { return nil }
        return bio.chapters[i - 1]
    }

    private var chapterAfter: BioChapter? {
        guard let chapter = current,
              let i = bio.chapters.firstIndex(of: chapter),
              i + 1 < bio.chapters.count else { return nil }
        return bio.chapters[i + 1]
    }

    private var dotIDs: [String] { bio.chapters.suffix(5).map(\.id) }

    @ViewBuilder
    private func pagerButton(_ chapter: BioChapter?, edge: HorizontalEdge) -> some View {
        if let chapter {
            Button {
                currentID = chapter.id
            } label: {
                Text(verbatim: (edge == .leading ? "‹ " : "")
                    + String(localized: "第\(ChineseNumeral.ordinal(chapter.index))回 · \(chapter.title)")
                    + (edge == .trailing ? " ›" : ""))
                    .font(.system(size: 12))
                    .foregroundStyle(DS.faint)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            Text(verbatim: " ").font(.system(size: 12))
        }
    }

    // MARK: 目录

    private var tocView: some View {
        let volume = tocVolume ?? current.map { bio.volume(of: $0) } ?? 1
        let years = Array(Set(bio.chapters.map(\.year))).sorted()
        let year = years.indices.contains(volume - 1) ? years[volume - 1] : years.last ?? 0
        let listed = bio.chapters.filter { $0.year == year }.reversed()
        let others = years.enumerated().filter { $0.element != year }

        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: String(localized: "目录 · 卷\(ChineseNumeral.ordinal(volume))"))
                    .font(serif(18, weight: .semibold))
                    .foregroundStyle(DS.ink)
                Spacer()
                Text(verbatim: "\(year)")
                    .font(.system(size: 11))
                    .foregroundStyle(DS.faint)
            }
            .padding(.bottom, 14)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(listed)) { chapter in
                        tocRow(chapter)
                    }
                }
            }
            .scrollIndicators(.never)

            ForEach(Array(others), id: \.element) { i, otherYear in
                let count = bio.chapters.filter { $0.year == otherYear }.count
                HStack(spacing: 12) {
                    Text(verbatim: String(localized: "卷\(ChineseNumeral.ordinal(i + 1)) · \(ChineseNumeral.year(otherYear))（\(ChineseNumeral.ordinal(count))回）"))
                        .font(.system(size: 12))
                        .foregroundStyle(DS.muted)
                    Spacer()
                    Button {
                        tocVolume = i + 1
                    } label: {
                        Text("翻开 ›")
                            .font(.system(size: 12))
                            .foregroundStyle(DS.coral)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 14)
                .overlay(alignment: .top) { DS.lineSoft.frame(height: 1) }
            }
        }
        .padding(.vertical, 30)
        .padding(.horizontal, 34)
    }

    private func tocRow(_ chapter: BioChapter) -> some View {
        Button {
            currentID = chapter.id
            withAnimation(.easeOut(duration: 0.18)) { showTOC = false }
        } label: {
            HStack(alignment: .top, spacing: 14) {
                Text(verbatim: ChineseNumeral.ordinal(chapter.index))
                    .font(serif(13))
                    .foregroundStyle(DS.faint)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(verbatim: chapter.title)
                            .font(serif(15, weight: .semibold))
                            .foregroundStyle(DS.ink)
                        if !chapter.done {
                            Text("连载中")
                                .font(.system(size: 11))
                                .foregroundStyle(DS.coral)
                        }
                    }
                    if let note = chapter.annotation {
                        Text(verbatim: String(localized: "批注：\(note)"))
                            .font(.system(size: 12))
                            .foregroundStyle(DS.muted)
                            .lineLimit(2)
                    }
                }
                Spacer()
                Text(verbatim: chapter.monthLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(DS.faint)
                    .padding(.top, 2)
            }
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .top) { DS.lineSoft.frame(height: 1) }
    }

    // MARK: 空态

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("还没开笔")
                .font(serif(21, weight: .semibold))
                .foregroundStyle(DS.ink)
            Text(bio.writing
                ? "正在写…写完会从桌面递给你。"
                : "它把你的回忆写成一部还在连载的传记——数据是素材，日子是章节。每月初一更新一回；这个月聊过、记过的事攒够了，就能开第一回。")
                .font(.system(size: 13))
                .lineSpacing(7)
                .foregroundStyle(DS.inkSoft)
            if SettingsStore.shared.llmConfig == nil {
                Text("要先在设置里配一个模型。")
                    .font(.system(size: 12))
                    .foregroundStyle(DS.muted)
            } else if !bio.writing {
                Button("让它现在开笔") { bio.tickIfNeeded() }
                    .buttonStyle(SmallInkPill())
                    .padding(.top, 6)
            }
        }
        .padding(40)
    }
}

/// 桌面小件 · 更新那天，它把新的一回递给你（设计稿《传》）。
struct BookNewsCard: View {
    let chapter: BioChapter

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                Text(verbatim: "传")
                    .font(serif(14))
                    .foregroundStyle(DS.coral)
                    .frame(width: 34, height: 34)
                    .background(RoundedRectangle(cornerRadius: 6).fill(DS.ink))
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: String(localized: "第\(ChineseNumeral.ordinal(chapter.index))回\(chapter.done ? String(localized: "写好了") : String(localized: "开笔了"))"))
                        .font(serif(15, weight: .semibold))
                        .foregroundStyle(DS.ink)
                    Text(verbatim: "《\(chapter.title)》· \(chapter.yearMonthLabel)")
                        .font(.system(size: 12))
                        .foregroundStyle(DS.muted)
                }
            }
            Text(verbatim: "「\(excerpt)」")
                .font(serif(13))
                .lineSpacing(12)
                .foregroundStyle(DS.inkSoft)
                .padding(.leading, 14)
                .overlay(alignment: .leading) {
                    Rectangle().fill(DS.lineSoft).frame(width: 2)
                }
            HStack(spacing: 10) {
                Button("读这一回") { BiographyStore.shared.openNews() }
                    .buttonStyle(SmallInkPill())
                Button("睡前再读") { BiographyStore.shared.snoozeNews() }
                    .buttonStyle(SmallGhostPill())
            }
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 22)
        .frame(width: 340, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(DS.paper)
            .shadow(color: DS.ink.opacity(0.16), radius: 25, y: 20))
    }

    /// 摘第一句当引文。
    private var excerpt: String {
        let flat = chapter.body.replacingOccurrences(of: "\n", with: "")
        if let end = flat.firstIndex(where: { "。！？".contains($0) }) {
            return String(flat[...end])
        }
        return String(flat.prefix(40))
    }
}

#Preview {
    BookPanelView()
}
