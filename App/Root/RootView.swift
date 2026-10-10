import LenKit
import SwiftUI

enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case home
    case trending
    case movies
    case series
    case search

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "首页"
        case .trending: "热播"
        case .movies: "电影"
        case .series: "剧集"
        case .search: "搜索"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house"
        case .trending: "flame"
        case .movies: "film"
        case .series: "tv"
        case .search: "magnifyingglass"
        }
    }
}

/// tvOS / iPhone / iPad 用标签栏，Mac 用侧边栏
struct RootView: View {
    @AppStorage("homeRefreshHelpSuppressed") private var refreshHelpSuppressed = false
    @State private var hasOfferedRefreshHelp = false
    @State private var showingRefreshHelp = false
    #if os(macOS)
    @State private var selection: AppSection? = .home
    #else
    @State private var selection: AppSection = .home
    #endif
    /// 每个标签各自的导航栈
    @State private var paths: [AppSection: [DetailRoute]] = [:]

    var body: some View {
        navigation
            .task(id: isHomeVisible) {
                guard isHomeVisible, !hasOfferedRefreshHelp else { return }
                hasOfferedRefreshHelp = true
                showingRefreshHelp = !refreshHelpSuppressed
            }
            .sheet(isPresented: $showingRefreshHelp) {
                HomeRefreshHelp(doNotRemindAgain: $refreshHelpSuppressed)
            }
    }

    private var isHomeVisible: Bool {
        selection == .home && (paths[.home] ?? []).isEmpty
    }

    private var navigation: some View {
        #if os(macOS)
        NavigationSplitView {
            List(AppSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.systemImage).tag(section)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 210)
        } detail: {
            if let selection {
                NavigationStack(path: path(for: selection)) { page(selection).mediaDestinations() }
                    .id(selection)
            }
        }
        .tint(.accentColor)
        .task { applyLaunchOptions() }
        #else
        TabView(selection: tabSelection) {
            ForEach(AppSection.allCases) { section in
                NavigationStack(path: path(for: section)) { page(section).mediaDestinations() }
                    .tabItem { Label(section.title, systemImage: section.systemImage) }
                    .tag(section)
            }
        }
        .tint(.accentColor)
        .task { applyLaunchOptions() }
        #endif
    }

    #if !os(macOS)
    /// iPhone / iPad 上再点一次当前标签回到首屏。tvOS 的标签选中会跟随焦点移动，不做这个处理，
    /// 否则焦点移回标签栏时会意外清空导航栈。
    private var tabSelection: Binding<AppSection> {
        Binding(
            get: { selection },
            set: { newValue in
                #if os(iOS)
                if newValue == selection { paths[newValue] = [] }
                #endif
                selection = newValue
            })
    }
    #endif

    private func path(for section: AppSection) -> Binding<[DetailRoute]> {
        Binding(get: { paths[section] ?? [] }, set: { paths[section] = $0 })
    }

    private func applyLaunchOptions() {
        #if DEBUG
        let section = LaunchOptions.tab ?? .home
        selection = section
        if let route = LaunchOptions.detailRoute { paths[section] = [route] }
        #endif
    }

    @ViewBuilder
    private func page(_ section: AppSection) -> some View {
        switch section {
        case .home: HomeView(isActive: isHomeVisible && !showingRefreshHelp)
        case .trending: TrendingView()
        case .movies: BrowseView(kind: .movie)
        case .series: BrowseView(kind: .tv)
        case .search: SearchView()
        }
    }
}
