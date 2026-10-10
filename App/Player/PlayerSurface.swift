import AVKit
import LenKit
import SwiftUI

#if os(tvOS)
/// tvOS 全屏播放器：系统 AVPlayerViewController，在播放控制栏上加“线路”和“选集”菜单
struct TVPlayerView: UIViewControllerRepresentable {
    let controller: PlaybackController
    /// 由外部传入，变化时 SwiftUI 会调用 update 重建菜单
    let cursor: PlaybackCursor

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let viewController = AVPlayerViewController()
        viewController.player = controller.player
        viewController.transportBarCustomMenuItems = menus()
        return viewController
    }

    func updateUIViewController(_ viewController: AVPlayerViewController, context: Context) {
        if viewController.player !== controller.player { viewController.player = controller.player }
        viewController.transportBarCustomMenuItems = menus()
    }

    private func menus() -> [UIMenuElement] {
        let detail = controller.detail
        let available = Set(detail.lineIndices(containing: cursor.episodeNumber))

        let lineActions = detail.lines.enumerated().map { index, line in
            UIAction(
                title: line.name,
                subtitle: available.contains(index) ? nil : "没有这一集",
                attributes: available.contains(index) ? [] : .disabled,
                state: index == cursor.lineIndex ? .on : .off
            ) { [controller] _ in controller.selectLine(index) }
        }
        var menus: [UIMenuElement] = [
            UIMenu(title: "线路", image: UIImage(systemName: "antenna.radiowaves.left.and.right"), children: lineActions),
        ]

        if controller.hasEpisodes, let line = detail.line(at: cursor) {
            let episodeActions = line.episodes.map { episode in
                UIAction(
                    title: episode.title,
                    attributes: episode.isPlayable ? [] : .disabled,
                    state: episode.number == cursor.episodeNumber ? .on : .off
                ) { [controller] _ in controller.selectEpisode(episode.number) }
            }
            menus.append(UIMenu(title: "选集", image: UIImage(systemName: "list.number"), children: episodeActions))
        }
        return menus
    }
}

/// tvOS 播放页：全屏播放器 + 提示 + 全部失败时的弹窗
struct TVPlayerScreen: View {
    let controller: PlaybackController

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        TVPlayerView(controller: controller, cursor: controller.cursor)
            .ignoresSafeArea()
            .overlay(alignment: .topTrailing) { PlaybackNoticeOverlay(controller: controller) }
            .alert("无法播放", isPresented: isFailed) {
                Button("重试") { controller.retry() }
                Button("返回", role: .cancel) { dismiss() }
            } message: {
                if case .failed(let message) = controller.phase { Text(message) }
            }
            .onDisappear { controller.stop() }
    }

    private var isFailed: Binding<Bool> {
        Binding(
            get: { if case .failed = controller.phase { true } else { false } },
            set: { _ in })
    }
}

#elseif os(iOS)
/// iPhone / iPad 内嵌播放器：系统控件，支持全屏和画中画
struct PlayerSurface: UIViewControllerRepresentable {
    let controller: PlaybackController

    func makeCoordinator() -> Coordinator { Coordinator(controller: controller) }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let viewController = AVPlayerViewController()
        viewController.delegate = context.coordinator
        viewController.player = controller.player
        viewController.allowsPictureInPicturePlayback = true
        viewController.canStartPictureInPictureAutomaticallyFromInline = true
        viewController.entersFullScreenWhenPlaybackBegins = false
        viewController.exitsFullScreenWhenPlaybackEnds = false
        return viewController
    }

    func updateUIViewController(_ viewController: AVPlayerViewController, context: Context) {
        context.coordinator.controller = controller
        if viewController.player !== controller.player { viewController.player = controller.player }
    }

    /// 记录全屏 / 画中画状态。进入全屏时系统会盖住整个 App，SwiftUI 会触发详情页的 onDisappear，
    /// 详情页据此判断是不是真的离开了
    final class Coordinator: NSObject, AVPlayerViewControllerDelegate {
        weak var controller: PlaybackController?

        init(controller: PlaybackController) {
            self.controller = controller
        }

        func playerViewController(
            _ playerViewController: AVPlayerViewController,
            willBeginFullScreenPresentationWithAnimationCoordinator coordinator: any UIViewControllerTransitionCoordinator
        ) {
            controller?.isPresentingFullScreen = true
        }

        func playerViewController(
            _ playerViewController: AVPlayerViewController,
            willEndFullScreenPresentationWithAnimationCoordinator coordinator: any UIViewControllerTransitionCoordinator
        ) {
            // 用户中途取消退出全屏（手势拖回去）时保持全屏状态
            coordinator.animate(alongsideTransition: nil) { [weak self] context in
                if !context.isCancelled { self?.controller?.isPresentingFullScreen = false }
            }
        }

        func playerViewControllerWillStartPictureInPicture(_ playerViewController: AVPlayerViewController) {
            controller?.isInPictureInPicture = true
        }

        func playerViewControllerDidStopPictureInPicture(_ playerViewController: AVPlayerViewController) {
            controller?.isInPictureInPicture = false
        }

        func playerViewController(
            _ playerViewController: AVPlayerViewController,
            failedToStartPictureInPictureWithError error: any Error
        ) {
            controller?.pictureInPictureFailed(error)
        }

        func playerViewControllerShouldAutomaticallyDismissAtPictureInPictureStart(
            _ playerViewController: AVPlayerViewController
        ) -> Bool {
            // 保留内嵌 / 全屏播放器所在的界面，切回 App 时继续使用同一个播放会话。
            false
        }

        func playerViewController(
            _ playerViewController: AVPlayerViewController,
            restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
        ) {
            // AVKit 将 App 带回前台；播放器未被自动 dismiss，无需再 present 一份。
            // 仅在确实仍挂在窗口中时报告恢复成功。
            completionHandler(playerViewController.viewIfLoaded?.window != nil)
        }
    }
}

#elseif os(macOS)
/// Mac 内嵌播放器：浮动控制条，支持全屏和画中画
struct PlayerSurface: NSViewRepresentable {
    let controller: PlaybackController

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = controller.player
        view.controlsStyle = .floating
        view.showsFullScreenToggleButton = true
        view.allowsPictureInPicturePlayback = true
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        if view.player !== controller.player { view.player = controller.player }
    }
}
#endif

/// 播放提示，4 秒后自动消失
struct PlaybackNoticeOverlay: View {
    let controller: PlaybackController

    var body: some View {
        ZStack {
            if let notice = controller.notice {
                NoticeToast(text: notice.text, isWarning: notice.isWarning)
                    .id(notice.id)
            }
        }
        .padding(24)
        .animation(.spring(duration: 0.35), value: controller.notice)
        .task(id: controller.notice?.id) {
            guard let id = controller.notice?.id else { return }
            try? await Task.sleep(for: .seconds(4))
            controller.dismissNotice(id)
        }
    }
}
