import SwiftUI

struct LoadingView: View {
    var body: some View {
        ProgressView()
            .controlSize(.large)
            .frame(maxWidth: .infinity, minHeight: 240)
    }
}

struct FailureView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("加载失败", systemImage: "wifi.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            Button("重试", action: retry)
        }
    }
}

/// 播放时的提示，例如“已切换到 速博 线路”
struct NoticeToast: View {
    let text: String
    var isWarning = false

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: isWarning ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(isWarning ? Color.orange : .white)
        }
        .font(.callout.weight(.medium))
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: .capsule)
        .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
