import SwiftUI

struct HomeRefreshHelp: View {
    @Binding var doNotRemindAgain: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        #if os(iOS)
        ScrollView {
            content
                .frame(maxWidth: .infinity)
        }
        .presentationDetents([.height(560), .large])
        #else
        content
        #endif
    }

    private var content: some View {
        VStack(spacing: 24) {
            Image(systemName: "arrow.clockwise.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            Text("首页内容，随时刷新")
                .font(.title2.bold())
                .accessibilityIdentifier("home.refreshHelp")
            Text(instructions)
                .font(.body)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text("更新今日推荐、热门电影和热门剧集。继续观看会随播放进度自动更新。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            #if os(tvOS)
            Button {
                doNotRemindAgain.toggle()
            } label: {
                Label("不再提醒", systemImage: doNotRemindAgain ? "checkmark.square.fill" : "square")
            }
            .accessibilityValue(doNotRemindAgain ? "已勾选" : "未勾选")
            .accessibilityIdentifier("home.suppressRefreshHelp")
            #else
            Toggle("不再提醒", isOn: $doNotRemindAgain)
                .accessibilityIdentifier("home.suppressRefreshHelp")
            #endif
            Text("不勾选，下次启动应用时仍会提示。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("知道了") { dismiss() }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("home.dismissRefreshHelp")
                #if os(macOS)
                .keyboardShortcut(.defaultAction)
                #endif
        }
        .padding(32)
        #if os(tvOS)
        .frame(maxWidth: 900)
        #elseif os(macOS)
        .frame(width: 460)
        #else
        .frame(maxWidth: 480)
        #endif
    }

    private var instructions: String {
        #if os(tvOS)
        "在首页长按遥控器的播放／暂停键约 1 秒，即可刷新。"
        #elseif os(macOS)
        "在首页点击右上角的刷新按钮，或按 ⌘R，即可刷新。"
        #else
        "在首页向下拉动，即可刷新。"
        #endif
    }
}
