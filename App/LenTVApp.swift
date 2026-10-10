import AVFoundation
import SwiftUI

@main
struct LenTVApp: App {
    init() {
        ImageCacheSetup.configure()
        #if os(iOS) || os(tvOS)
        // 静音开关打开时也有声音，并支持画中画和后台播放
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
        }
        #if os(macOS)
        .defaultSize(width: 1280, height: 820)
        #endif
    }
}
