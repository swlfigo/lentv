import LenKit
import SwiftUI
#if os(iOS)
import UIKit
#endif

struct BrowseView: View {
    @State private var model: BrowseModel
    @State private var filtersHeight: CGFloat = 0

    @PlatformMetrics private var metrics

    init(kind: MediaKind) {
        _model = State(initialValue: BrowseModel(kind: kind))
    }

    var body: some View {
        GeometryReader { viewport in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 18) {
                        ChipRow(
                            items: [nil] + model.categories.map(Optional.some),
                            selection: model.category,
                            title: { $0?.name ?? "全部" },
                            showsOverflowHint: true,
                            onSelect: { model.category = $0 })

                        FilterBar(model: model)
                            .padding(.horizontal, metrics.horizontalPadding)
                    }
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                        filtersHeight = $0
                    }

                    results
                        // 占位视图填满筛选栏下的可用区域，避免被 leading 对齐的容器挤到左上角。
                        .frame(maxWidth: .infinity,
                               minHeight: showsPlaceholder ? max(0, viewport.size.height - filtersHeight - 18 - 32) : nil)
                        .padding(.horizontal, metrics.horizontalPadding)
                }
                .padding(.bottom, 32)
            }
        }
        .background(Color.lenBackground)
        .task { await model.loadFilters() }
        .task(id: model.query) { await model.reload() }
        #if !os(tvOS)
        .navigationTitle(model.kind == .movie ? "电影" : "剧集")
        #endif
    }

    private var showsPlaceholder: Bool {
        switch model.phase {
        case .loading: true
        case .failed, .exhausted: model.items.isEmpty
        default: false
        }
    }

    @ViewBuilder
    private var results: some View {
        switch model.phase {
        case .loading:
            LoadingView()
        case .failed(let message) where model.items.isEmpty:
            FailureView(message: message) { Task { await model.reload() } }
        default:
            if model.items.isEmpty, model.phase == .exhausted {
                ContentUnavailableView("没有符合条件的\(model.kind.displayName)", systemImage: "film.stack", description: Text("换个筛选条件试试"))
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: metrics.gridMinWidth), spacing: metrics.itemSpacing, alignment: .top)],
                          spacing: metrics.itemSpacing * 1.4) {
                    ForEach(model.items) { item in
                        PosterLink(item: item)
                            .task { await model.loadMoreIfNeeded(after: item) }
                    }
                }
                #if os(tvOS)
                .focusSection()
                #endif
                if model.phase == .loadingMore {
                    ProgressView().frame(maxWidth: .infinity).padding()
                }
            }
        }
    }
}

/// iPhone 固定两行并使用选择面板；其他平台按宽度排列系统菜单。
private struct FilterBar: View {
    @Bindable var model: BrowseModel
    #if os(iOS)
    private enum PhoneFilter: String, Identifiable {
        case region, year, status
        var id: String { rawValue }
    }
    @State private var presentedFilter: PhoneFilter?
    #endif

    var body: some View {
        Group {
            #if os(iOS)
            if UIDevice.current.userInterfaceIdiom == .phone {
                phoneLayout
            } else {
                adaptiveLayout
            }
            #else
            adaptiveLayout
            #endif
        }
        #if os(tvOS)
        .focusSection()
        #elseif os(iOS)
        .sheet(item: $presentedFilter) { filter in
            switch filter {
            case .region:
                FilterSelectionSheet(title: "选择地区", allTitle: "全部地区", options: model.regions,
                                     selection: $model.region, label: { $0 })
            case .year:
                FilterSelectionSheet(title: "选择年份", allTitle: "全部年份", options: model.years,
                                     selection: $model.year, label: { $0.label })
            case .status:
                FilterSelectionSheet(title: "选择状态", allTitle: "全部状态", options: SeriesStatus.allCases,
                                     selection: $model.status, label: { $0.displayName })
            }
        }
        #endif
    }

    #if os(iOS)
    private var phoneLayout: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 筛选值较长时横向滚动，避免挤走按钮或改变排序栏的位置。
            ScrollView(.horizontal) {
                HStack(spacing: 16) {
                    phoneFilter(.region, title: "地区", value: model.region ?? "全部")
                    phoneFilter(.year, title: "年份", value: model.year?.label ?? "全部")
                    if model.kind == .tv {
                        phoneFilter(.status, title: "状态", value: model.status?.displayName ?? "全部")
                    }
                }
            }
            .scrollIndicators(.hidden)
            .fixedSize(horizontal: false, vertical: true)
            HStack {
                sortControls
                Spacer(minLength: 0)
            }
        }
    }

    private func phoneFilter(_ filter: PhoneFilter, title: String, value: String) -> some View {
        Button { presentedFilter = filter } label: {
            FilterLabel(title: title, value: value)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.accentColor)
    }
    #endif

    private var adaptiveLayout: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                menus
                Spacer(minLength: 12)
                sortControls
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 16) { menus }
                HStack {
                    sortControls
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var menus: some View {
        Group { menuItems }
            #if os(tvOS)
            // tvOS 的 Menu 默认用强调色填充，文字看不见；改用和分类标签一致的样式
            .menuStyle(.button)
            .buttonStyle(ChipButtonStyle(isSelected: false))
            #elseif os(macOS)
            // 去掉 macOS 自带的边框和下拉箭头，只保留自定义标签
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            #endif
    }

    @ViewBuilder
    private var menuItems: some View {
        Menu {
            Picker("地区", selection: $model.region) {
                Text("全部").tag(String?.none)
                ForEach(model.regions, id: \.self) { Text($0).tag(Optional($0)) }
            }
        } label: {
            FilterLabel(title: "地区", value: model.region ?? "全部")
        }

        yearMenu

        if model.kind == .tv {
            Menu {
                Picker("状态", selection: $model.status) {
                    Text("全部").tag(SeriesStatus?.none)
                    ForEach(SeriesStatus.allCases) { Text($0.displayName).tag(Optional($0)) }
                }
            } label: {
                FilterLabel(title: "状态", value: model.status?.displayName ?? "全部")
            }
        }
    }

    private var yearMenu: some View {
        Menu {
            Picker("年份", selection: $model.year) {
                Text("全部").tag(YearOption?.none)
                ForEach(model.years) { Text($0.label).tag(Optional($0)) }
            }
        } label: {
            FilterLabel(title: "年份", value: model.year?.label ?? "全部")
        }
    }

    @ViewBuilder
    private var sortControls: some View {
        // 数量变化或加载时都保留同样的宽度，否则 ViewThatFits 会在一行 / 两行间跳动，
        // 排序控件也会跟着移动。占位文本只参与布局，不向辅助功能暴露。
        Text("\(999_999) 部")
            .hidden()
            .accessibilityHidden(true)
            .overlay(alignment: .leading) {
                Text(model.total.map { "\($0.formatted()) 部" } ?? "— 部")
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .font(.subheadline.monospacedDigit())
            .foregroundStyle(.secondary)
            .fixedSize()
        Picker("排序", selection: $model.sort) {
            ForEach(ListSort.allCases) { Text($0.displayName(for: model.kind)).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
    }
}

#if os(iOS)
private struct FilterSelectionSheet<Value: Hashable>: View {
    let title: String
    let allTitle: String
    let options: [Value]
    @Binding var selection: Value?
    let label: (Value) -> String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                row(nil)
                ForEach(options, id: \.self) { row($0) }
            }
            .scrollContentBackground(.hidden)
            .background(Color.lenBackground)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func row(_ value: Value?) -> some View {
        Button {
            selection = value
            dismiss()
        } label: {
            HStack {
                Text(value.map(label) ?? allTitle)
                Spacer()
                if selection == value {
                    Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                }
            }
            .foregroundStyle(Color.primary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.lenSurface)
        .accessibilityAddTraits(selection == value ? .isSelected : [])
    }
}
#endif

private struct FilterLabel: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 6) {
            Text(title).foregroundStyle(.secondary)
            Text(value).fontWeight(.semibold)
            Image(systemName: "chevron.down").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
        }
        .font(.subheadline)
        .fixedSize()
    }
}
