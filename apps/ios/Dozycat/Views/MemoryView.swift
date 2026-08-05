import SwiftUI

struct MemoryView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            searchField
            filterTabs
            memoryList
        }
        .padding(.horizontal, 32)
        .padding(.top, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DS.paper)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("小传")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(DS.ink)
            Text("\(model.memoryTotalLabel) 件小事 · 只存在你自己的设备里")
                .font(.system(size: 13))
                .foregroundStyle(DS.muted)
        }
    }

    private var searchField: some View {
        HStack {
            TextField("搜搜看「上次牙疼是什么时候」", text: $model.memorySearch)
                .font(.system(size: 14))
                .foregroundStyle(DS.ink)
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(DS.inkSoft)
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) { DS.lineStrong.frame(height: 1) }
    }

    private var filterTabs: some View {
        HStack(spacing: 20) {
            filterTab(nil, label: "全部")
            ForEach(Memory.Category.allCases, id: \.self) { category in
                filterTab(category, label: category.label)
            }
            Spacer()
        }
    }

    private func filterTab(_ category: Memory.Category?, label: LocalizedStringKey) -> some View {
        let active = model.memoryFilter == category
        return Button {
            withAnimation(.easeOut(duration: 0.2)) { model.memoryFilter = category }
        } label: {
            Text(label)
                .font(.system(size: 13, weight: active ? .medium : .regular))
                .foregroundStyle(active ? DS.ink : DS.muted)
                .padding(.bottom, 6)
                .overlay(alignment: .bottom) {
                    (active ? DS.coral : Color.clear).frame(height: 2)
                }
        }
        .buttonStyle(.plain)
    }

    private var memoryList: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                let items = model.filteredMemories
                ForEach(items) { memory in
                    memoryRow(memory)
                    if memory.id != items.last?.id {
                        DS.lineSoft.frame(height: 1)
                    }
                }
                if items.isEmpty {
                    Text("没找到。要不换个说法试试？")
                        .font(.system(size: 13))
                        .foregroundStyle(DS.faint)
                        .padding(.top, 48)
                }
            }
            .padding(.bottom, 24)
        }
    }

    private func memoryRow(_ memory: Memory) -> some View {
        HStack(alignment: .top, spacing: 18) {
            Text(memory.dateLabel)
                .font(.system(size: 12))
                .foregroundStyle(DS.faint)
                .frame(width: 48, alignment: .leading)
                .padding(.top, 3)
            VStack(alignment: .leading, spacing: 6) {
                Text(memory.text)
                    .font(.system(size: 15))
                    .lineSpacing(6)
                    .foregroundStyle(DS.ink)
                if let note = memory.note {
                    Text(note)
                        .font(.system(size: 12))
                        .foregroundStyle(memory.noteKind.color)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 16)
    }
}

#Preview {
    RootView()
}
