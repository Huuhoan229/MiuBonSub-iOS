import SwiftUI
import UIKit
import UserNotifications
import AVFoundation

@main
struct MiuBonSubApp: App {
    init() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to set audio session category: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            MiuBonRootView()
        }
    }
}

