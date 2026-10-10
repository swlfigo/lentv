import LenKit
import SwiftUI

/// 选集网格，集数多时按 30 集分页
struct EpisodeGrid: View {
    let line: SourceLine
    /// 正在播放或上次看到的集数
    let highlighted: Int?
    let onSelect: (Episode) -> Void

    @State private var pageIndex = 0

    var body: some View {
        let pages = line.episodePages(size: 30)

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("选集").font(.headline)
                    Text("共 \(line.episodes.count) 集").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                if pages.count > 1 {
                    Picker("分段", selection: $pageIndex) {
                        ForEach(pages.indices, id: \.self) { index in
                            Text(pages[index].label).tag(index)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: spacing), count: columns), spacing: spacing) {
                ForEach(pages.indices.contains(pageIndex) ? pages[pageIndex].episodes : [], id: \.number) { episode in
                    Button { onSelect(episode) } label: {
                        Text("\(episode.number)")
                            .monospacedDigit()
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(EpisodeButtonStyle(isHighlighted: episode.number == highlighted))
                    .disabled(!episode.isPlayable)
                }
            }
            #if os(tvOS)
            .focusSection()
            #endif
        }
        .onAppear { pageIndex = page(containing: highlighted, in: pages) }
        .onChange(of: line.key) { pageIndex = page(containing: highlighted, in: pages) }
    }

    private func page(containing episode: Int?, in pages: [EpisodePage]) -> Int {
        guard let episode else { return 0 }
        return pages.firstIndex { $0.episodes.contains { $0.number == episode } } ?? 0
    }

    #if os(tvOS)
    private let columns = 10
    private let spacing: CGFloat = 20
    #elseif os(macOS)
    private let columns = 12
    private let spacing: CGFloat = 8
    #else
    private let columns = 6
    private let spacing: CGFloat = 8
    #endif
}

struct EpisodeButtonStyle: ButtonStyle {
    var isHighlighted: Bool

    func makeBody(configuration: Configuration) -> some View {
        EpisodeButtonBody(configuration: configuration, isHighlighted: isHighlighted)
    }
}

private struct EpisodeButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let isHighlighted: Bool

    @Environment(\.isFocused) private var isFocused
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .font(.body.weight(.bold))
            .frame(height: height)
            .foregroundStyle(isFocused ? Color.black : .white)
            .background(isFocused ? Color.white : (isHighlighted ? .lenSelectedFill : .lenSurface), in: .rect(cornerRadius: height * 0.2))
            .scaleEffect(isFocused ? 1.12 : (configuration.isPressed ? 0.94 : 1))
            .shadow(color: .black.opacity(isFocused ? 0.55 : 0), radius: 14, y: 8)
            .opacity(isEnabled ? 1 : 0.3)
            .animation(.easeOut(duration: 0.12), value: isFocused)
            .contentShape(.rect)
    }

    #if os(tvOS)
    private let height: CGFloat = 72
    #elseif os(macOS)
    private let height: CGFloat = 32
    #else
    private let height: CGFloat = 44
    #endif
}
