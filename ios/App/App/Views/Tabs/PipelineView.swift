import SwiftUI

struct PipelineView: View {
    @EnvironmentObject var appVM: AppViewModel
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Health Status Grid
                    healthGrid
                    
                    // Input Section
                    GlassCard {
                        VStack(alignment: .leading) {
                            Text("Nhập URL Douyin/TikTok:")
                                .font(.headline)
                            TextEditor(text: $appVM.urlInput)
                                .frame(height: 120)
                                .padding(4)
                                .background(Color(UIColor.secondarySystemBackground))
                                .cornerRadius(8)
                            
                            HStack {
                                GradientButton(title: "Chạy 1 link", icon: "play.fill") {
                                    Task { await appVM.startPipeline(single: true) }
                                }
                                GradientButton(title: "Chạy Queue", icon: "list.bullet.rectangle.fill") {
                                    Task { await appVM.startPipeline(single: false) }
                                }
                            }
                        }
                    }
                    
                    // Progress Section
                    if appVM.pipelineProgress > 0 {
                        GlassCard {
                            VStack(spacing: 10) {
                                Text(appVM.pipelineStatus)
                                    .font(.headline)
                                    .foregroundColor(.blue)
                                ProgressView(value: appVM.pipelineProgress, total: 1.0)
                                    .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                                Text(appVM.pipelineMessage)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Pipeline")
            .background(Color(UIColor.systemGroupedBackground).edgesIgnoringSafeArea(.all))
        }
    }
    
    private var healthGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
            healthCard(title: "Server", status: appVM.health.server, icon: "server.rack")
            healthCard(title: "YouTube", status: appVM.health.youtube, icon: "play.rectangle.fill")
            healthCard(title: "TikTok", status: appVM.health.tiktok, icon: "music.note")
            healthCard(title: "Facebook", status: appVM.health.facebook, icon: "f.square.fill")
        }
    }
    
    private func healthCard(title: String, status: String, icon: String) -> some View {
        GlassCard {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(.blue)
                VStack(alignment: .leading) {
                    Text(title).font(.caption).foregroundColor(.secondary)
                    Text(status).font(.subheadline).bold()
                }
                Spacer()
            }
        }
    }
}
