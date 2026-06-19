import SwiftUI
import AVKit

struct VideosView: View {
    @EnvironmentObject var appVM: AppViewModel
    @StateObject private var playerVM = VideoPlayerViewModel.shared
    
    let columns = [GridItem(.flexible()), GridItem(.flexible())]
    
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(appVM.projects.filter { $0.rendered }) { project in
                        videoCard(for: project)
                            .onTapGesture {
                                playVideo(project: project)
                            }
                    }
                }
                .padding()
            }
            .navigationTitle("Xem Phim")
            .sheet(item: $playerVM.selectedVideo) { video in
                videoPlayerSheet(video: video)
            }
        }
    }
    
    private func videoCard(for project: ProjectRow) -> some View {
        GlassCard {
            VStack {
                // Giả lập Image Loader từ API Thumbnail
                AsyncImage(url: URL(string: "\(NetworkManager.shared.backendURL)/api/project/\(project.folderName)/stream/thumbnail.jpg")) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color.gray.opacity(0.3)
                }
                .frame(height: 120)
                .clipped()
                .cornerRadius(8)
                
                Text(project.displayName)
                    .font(.caption)
                    .lineLimit(2)
                    .padding(.top, 4)
            }
        }
    }
    
    private func playVideo(project: ProjectRow) {
        let cleanBase = NetworkManager.shared.backendURL
        let previewPath = "\(cleanBase)/api/project/\(project.folderName)/stream/preview"
        
        if let url = URL(string: previewPath) {
            let selection = VideoSelection(
                title: project.displayName,
                subtitle: project.subtitle,
                folderName: project.folderName,
                url: url,
                previewURL: url,
                finalURL: url,
                watchFolder: project.seriesFolder,
                episodeIndex: project.episodeNo ?? 0,
                resumeTime: 0
            )
            playerVM.selectVideo(selection)
        }
    }
    
    private func videoPlayerSheet(video: VideoSelection) -> some View {
        VStack {
            HStack {
                Text(video.title).font(.headline).lineLimit(1)
                Spacer()
                Button("Đóng") { playerVM.clearSelection() }
            }
            .padding()
            
            AdvancedVideoPlayer(
                videoURL: video.url,
                startPosition: video.resumeTime,
                onTimeUpdate: { time in
                    // playerVM.saveProgress(for: video.episodeIndex, time: time)
                },
                onVideoEnded: {
                    playerVM.playNextVideo(currentList: appVM.projects)
                }
            )
            .edgesIgnoringSafeArea(.bottom)
        }
    }
}
