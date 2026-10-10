#if os(tvOS)
import SwiftUI
import UIKit

/// 接收首页的遥控器按键，不占用内容焦点。
struct TVHomeRefreshGesture: UIViewRepresentable {
    let isEnabled: Bool
    let action: () -> Void

    func makeUIView(context: Context) -> RemoteGestureView {
        RemoteGestureView()
    }

    func updateUIView(_ view: RemoteGestureView, context: Context) {
        view.action = action
        view.recognizer.isEnabled = isEnabled
    }

    static func dismantleUIView(_ view: RemoteGestureView, coordinator: ()) {
        view.detach()
    }

    final class RemoteGestureView: UIView, UIGestureRecognizerDelegate {
        var action: (() -> Void)?
        private weak var attachedWindow: UIWindow?
        lazy var recognizer: UILongPressGestureRecognizer = {
            let gesture = UILongPressGestureRecognizer(target: self, action: #selector(handlePress))
            gesture.allowedPressTypes = [NSNumber(value: UIPress.PressType.playPause.rawValue)]
            gesture.minimumPressDuration = 1
            gesture.cancelsTouchesInView = false
            gesture.delegate = self
            return gesture
        }()

        override func didMoveToWindow() {
            super.didMoveToWindow()
            detach()
            attachedWindow = window
            window?.addGestureRecognizer(recognizer)
        }

        func detach() {
            attachedWindow?.removeGestureRecognizer(recognizer)
            attachedWindow = nil
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            false
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }

        @objc private func handlePress(_ gesture: UILongPressGestureRecognizer) {
            // 连续长按只在达到时长时触发一次，松开与后续 changed 不重复刷新。
            guard gesture.state == .began else { return }
            action?()
        }
    }
}
#endif
