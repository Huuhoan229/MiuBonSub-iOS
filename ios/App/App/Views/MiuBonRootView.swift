import SwiftUI

struct MiuBonRootView: View {
    @StateObject private var appVM = AppViewModel.shared
    
    var body: some View {
        TabView(selection: $appVM.selectedTab) {
            PipelineView()
                .tabItem {
                    Label(MainTab.pipeline.title, systemImage: MainTab.pipeline.symbol)
                }
                .tag(MainTab.pipeline)
            
            RunningView()
                .tabItem {
                    Label(MainTab.running.title, systemImage: MainTab.running.symbol)
                }
                .tag(MainTab.running)
                
            ScraperView()
                .tabItem {
                    Label(MainTab.scraper.title, systemImage: MainTab.scraper.symbol)
                }
                .tag(MainTab.scraper)
                
            ProjectsView()
                .tabItem {
                    Label(MainTab.projects.title, systemImage: MainTab.projects.symbol)
                }
                .tag(MainTab.projects)
                
            VideosView()
                .tabItem {
                    Label(MainTab.videos.title, systemImage: MainTab.videos.symbol)
                }
                .tag(MainTab.videos)
                
            UploadsView()
                .tabItem {
                    Label(MainTab.uploads.title, systemImage: MainTab.uploads.symbol)
                }
                .tag(MainTab.uploads)
                
            DictionaryView()
                .tabItem {
                    Label(MainTab.dictionary.title, systemImage: MainTab.dictionary.symbol)
                }
                .tag(MainTab.dictionary)
                
            SettingsView()
                .tabItem {
                    Label(MainTab.settings.title, systemImage: MainTab.settings.symbol)
                }
                .tag(MainTab.settings)
        }
        .environmentObject(appVM)
        .preferredColorScheme(appVM.themeRaw == "dark" ? .dark : (appVM.themeRaw == "light" ? .light : nil))
        .onAppear {
            appVM.startPolling()
            // Đăng ký nhận thông báo Notification
            NotificationCenterBridge.shared.configure()
        }
    }
}
