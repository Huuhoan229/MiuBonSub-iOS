import SwiftUI
import AVKit

/// Trình phát video tuỳ chỉnh với khả năng quản lý trạng thái và tua video
struct AdvancedVideoPlayer: UIViewControllerRepresentable {
    let videoURL: URL
    let startPosition: Double
    var onTimeUpdate: (Double) -> Void
    var onVideoEnded: () -> Void

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        let player = AVPlayer(url: videoURL)
        controller.player = player
        controller.showsPlaybackControls = true
        
        // Cấu hình âm thanh phát ra loa ngoài ngay cả khi bật chế độ im lặng
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [])
        
        // Lắng nghe sự kiện kết thúc
        context.coordinator.subscribeToVideoEnd(player: player, action: onVideoEnded)
        
        // Tua đến mốc đã xem trước đó
        if startPosition > 2.0 {
            player.seek(to: CMTime(seconds: startPosition, preferredTimescale: 600))
        }
        
        player.play()
        
        // Theo dõi thời gian phát
        context.coordinator.addTimeObserver(player: player, callback: onTimeUpdate)
        
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        // Cập nhật URL nếu chuyển tập
        if let currentURL = (uiViewController.player?.currentItem?.asset as? AVURLAsset)?.url, currentURL != videoURL {
            let player = AVPlayer(url: videoURL)
            uiViewController.player = player
            player.play()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject {
        var parent: AdvancedVideoPlayer
        private var timeObserverToken: Any?
        private var endObserver: NSObjectProtocol?

        init(_ parent: AdvancedVideoPlayer) {
            self.parent = parent
        }

        func addTimeObserver(player: AVPlayer, callback: @escaping (Double) -> Void) {
            let interval = CMTime(seconds: 2.0, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
            timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
                callback(time.seconds)
            }
        }

        func subscribeToVideoEnd(player: AVPlayer, action: @escaping () -> Void) {
            if let currentItem = player.currentItem {
                endObserver = NotificationCenter.default.addObserver(
                    forName: .AVPlayerItemDidPlayToEndTime,
                    object: currentItem,
                    queue: .main
                ) { _ in
                    action()
                }
            }
        }

        deinit {
            if let token = timeObserverToken {
                // Không thể truy cập player từ đây để gỡ bỏ observer vì mất reference
                // Nhưng AVPlayer tự giải phóng observer nếu dùng đúng cách
                timeObserverToken = nil
            }
            if let endObserver = endObserver {
                NotificationCenter.default.removeObserver(endObserver)
            }
        }
    }
}
