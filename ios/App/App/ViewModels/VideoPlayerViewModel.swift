import Foundation
import Combine
import AVKit

@MainActor
final class VideoPlayerViewModel: ObservableObject {
    static let shared = VideoPlayerViewModel()
    
    @Published var selectedVideo: VideoSelection?
    @Published var watchProgress: [String: WatchProgress] = [:]
    
    private init() {
        // Load watch progress from UserDefaults if needed
    }
    
    func selectVideo(_ video: VideoSelection) {
        self.selectedVideo = video
    }
    
    func clearSelection() {
        self.selectedVideo = nil
    }
    
    func saveProgress(for episodeIndex: Int, time: Double) {
        if let video = selectedVideo {
            watchProgress[video.folderName] = WatchProgress(episodeIndex: episodeIndex, time: time)
            
            // Gửi API lưu tiến trình lên server
            Task {
                do {
                    _ = try await NetworkManager.shared.request(
                        "/api/user/progress",
                        method: "POST",
                        body: ["folder": video.folderName, "time": time]
                    )
                } catch {
                    print("Lỗi lưu tiến trình: \(error.localizedDescription)")
                }
            }
        }
    }
    
    func playNextVideo(currentList: [ProjectRow]) {
        guard let current = selectedVideo else { return }
        // Logic tìm tập tiếp theo trong danh sách và auto play
    }
}
