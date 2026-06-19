import re

with open('ios/App/App/NativeApp.swift', 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Extract Account Section
# Wait, we know the account section is exactly:
account_section = """            SectionCard(title: "Tài khoản xem phim", symbol: "person.crop.circle.fill") {
                if model.authToken.isEmpty {
                    TextField("Tên đăng nhập", text: $model.authUsername)
                        .textInputAutocapitalization(.never)
                        .inputShell()
                    SecureField("Mật khẩu", text: $model.authPassword)
                        .inputShell()
                    HStack(spacing: 10) {
                        SmallButton(title: "Đăng nhập", symbol: "person.fill.checkmark") {
                            Task { await model.login() }
                        }
                        SmallButton(title: "Đăng ký", symbol: "person.badge.plus") {
                            Task { await model.login(register: true) }
                        }
                    }
                } else {
                    HStack {
                        StatusPill(text: "Đã đăng nhập", tone: .green)
                        Spacer()
                        SmallButton(title: "Đăng xuất", symbol: "rectangle.portrait.and.arrow.right") {
                            model.logout()
                        }
                        .frame(width: 120)
                    }
                }
                Text(model.authMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
"""

videos_view_new = """struct VideosView: View {
    @EnvironmentObject private var model: AppModel
    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "play.rectangle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("MiuBon")
                            .font(.system(.title3, design: .rounded).weight(.black))
                        Text("PREMIUM WATCH")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.cyan)
                    }
                }
                Spacer()
                Circle()
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 36, height: 36)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            // Controls
            HStack {
                Picker("Loai", selection: $model.videoLibraryMode) {
                    Text("Series").tag("series")
                    Text("Lẻ").tag("standalone")
                }
                .pickerStyle(.segmented)
                .frame(width: 140)

                Spacer()

                Button {
                    Task {
                        await model.refreshSeries()
                        await model.refreshProjects()
                        await model.loadWatchProgress()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                        Text("Làm mới")
                    }
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.1), in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)

            ScrollView {
                VStack(spacing: 16) {
                    // Status
                    HStack {
                        Text("\\(model.videoLibraryMode == "series" ? model.effectiveSeriesRows.count : model.standaloneProjects.count) mục đã sẵn sàng.")
                            .font(.caption)
                            .foregroundStyle(.cyan)
                        Spacer()
                    }
                    .padding(12)
                    .background(Color.cyan.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.cyan.opacity(0.3), lineWidth: 1))
                    .padding(.horizontal, 16)

                    if model.videoLibraryMode == "series" {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(model.effectiveSeriesRows) { series in
                                ModernSeriesCard(series: series)
                                    .environmentObject(model)
                            }
                        }
                        .padding(.horizontal, 16)
                    } else {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(model.standaloneProjects) { project in
                                ModernStandaloneCard(project: project)
                                    .environmentObject(model)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.bottom, 120)
            }
        }
        .fullScreenCover(item: $model.selectedVideo) { selection in
            VideoPlayerSheet(selection: selection)
                .environmentObject(model)
        }
        .task {
            if !model.authToken.isEmpty {
                await model.loadWatchProgress()
            }
        }
    }
}"""

video_player_sheet = """struct ModernSeriesCard: View {
    var series: SeriesRow
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Button {
            model.selectSeriesForWatching(series)
        } label: {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.black)
                
                if let first = model.renderedEpisodes(in: series).first,
                   let url = model.projectMediaURL(projectName: first.projectName, file: "thumbnail.jpg") {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            Color.gray.opacity(0.3)
                        }
                    }
                }
                
                LinearGradient(colors: [.clear, .black.opacity(0.9)], startPoint: .top, endPoint: .bottom)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(series.name)
                        .font(.system(.subheadline, design: .rounded).weight(.black))
                        .foregroundStyle(.cyan)
                        .lineLimit(2)
                    
                    Text("\\(series.rendered)/\\(series.total) Rendered")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    
                    if let progress = model.watchProgress[series.folder] {
                        Text("Đã xem: tập \\(progress.episodeIndex + 1)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.blue)
                    }
                }
                .padding(12)
                
                VStack {
                    HStack {
                        Spacer()
                        Text("\\(series.total) Tập")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.6), in: Capsule())
                    }
                    Spacer()
                }
                .padding(8)
            }
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct ModernStandaloneCard: View {
    var project: ProjectRow
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Button {
            model.playProject(project)
        } label: {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.black)
                
                if let url = model.projectMediaURL(project, file: "thumbnail.jpg") {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            Color.gray.opacity(0.3)
                        }
                    }
                }
                
                LinearGradient(colors: [.clear, .black.opacity(0.9)], startPoint: .top, endPoint: .bottom)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(project.displayName)
                        .font(.system(.subheadline, design: .rounded).weight(.black))
                        .foregroundStyle(.cyan)
                        .lineLimit(2)
                }
                .padding(12)
            }
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct VideoPlayerSheet: View {
    var selection: VideoSelection
    @EnvironmentObject private var model: AppModel
    @Environment(\\ .dismiss) private var dismiss
    
    @State private var player = AVPlayer()
    @State private var currentSource: String = "Cloudflare"
    @State private var endObserver: NSObjectProtocol?
    @State private var searchEpisode: String = ""

    var series: SeriesRow? {
        model.selectedVideoSeries()
    }
    
    var renderedEpisodes: [SeriesEpisode] {
        guard let s = series else { return [] }
        return model.renderedEpisodes(in: s)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("SERIES")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.pink)
                        Text(series?.name ?? selection.title)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.white)
                        Text("Tập \\(selection.episodeIndex + 1) | \\(selection.title) | vị trí \\(selection.episodeIndex + 1)/\\(series?.total ?? 1)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        player.pause()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(Color.white.opacity(0.3))
                    }
                }
                .padding(16)
                
                HStack(spacing: 12) {
                    Button("Cloudflare") { switchSource("Cloudflare") }
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(currentSource == "Cloudflare" ? Color.clear : Color.white.opacity(0.1), in: Capsule())
                        .overlay(Capsule().stroke(currentSource == "Cloudflare" ? Color.cyan : Color.clear, lineWidth: 1))
                        .foregroundStyle(currentSource == "Cloudflare" ? Color.cyan : Color.white)
                    
                    Button("Drive") { switchSource("Drive") }
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(currentSource == "Drive" ? Color.clear : Color.white.opacity(0.1), in: Capsule())
                        .overlay(Capsule().stroke(currentSource == "Drive" ? Color.cyan : Color.clear, lineWidth: 1))
                        .foregroundStyle(currentSource == "Drive" ? Color.cyan : Color.white)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                
                VideoPlayer(player: player)
                    .frame(height: UIScreen.main.bounds.width * 9/16)
                    .background(Color.black)
                
                HStack(spacing: 16) {
                    Button {
                        if let s = series, selection.episodeIndex > 0, let ep = renderedEpisodes.first(where: { $0.episodeNo == selection.episodeIndex }) {
                            Task {
                                await saveCurrentProgress()
                                model.playEpisode(ep, in: s, index: selection.episodeIndex - 1)
                            }
                        }
                    } label: {
                        HStack {
                            Image(systemName: "chevron.left")
                            Text("Tập trước")
                        }
                        .font(.caption.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.white)
                    }
                    
                    Button {
                        Task {
                            await saveCurrentProgress()
                            await model.playNextVideo(after: selection)
                        }
                    } label: {
                        HStack {
                            Text("Tập tiếp")
                            Image(systemName: "chevron.right")
                        }
                        .font(.caption.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.white)
                    }
                }
                .padding(16)
                
                if let s = series {
                    VStack(spacing: 16) {
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(.secondary)
                            TextField("Tìm kiếm tập...", text: $searchEpisode)
                                .textInputAutocapitalization(.never)
                        }
                        .padding(12)
                        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal, 16)
                        
                        ScrollView {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                                ForEach(renderedEpisodes) { ep in
                                    let idx = renderedEpisodes.firstIndex(where: { $0.id == ep.id }) ?? 0
                                    let isCurrent = idx == selection.episodeIndex
                                    Button {
                                        Task {
                                            await saveCurrentProgress()
                                            model.playEpisode(ep, in: s, index: idx)
                                        }
                                    } label: {
                                        Text("\\(ep.episodeNo)")
                                            .font(.callout.weight(.bold))
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 16)
                                            .background(isCurrent ? Color.cyan : Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                                            .foregroundStyle(isCurrent ? .black : .white)
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 32)
                        }
                    }
                } else {
                    Spacer()
                }
            }
        }
        .onAppear {
            configurePlayer(autoplay: true)
        }
        .onChange(of: selection.id) { _ in
            Task { await saveCurrentProgress() }
            configurePlayer(autoplay: true)
        }
        .onDisappear {
            Task { await saveCurrentProgress() }
            player.pause()
            removeEndObserver()
        }
    }
    
    private func switchSource(_ source: String) {
        currentSource = source
        let url = source == "Drive" ? selection.previewURL : selection.finalURL
        let item = AVPlayerItem(url: url)
        
        let currentTime = player.currentTime()
        player.replaceCurrentItem(with: item)
        player.seek(to: currentTime)
        player.play()
    }

    private func configurePlayer(autoplay: Bool) {
        removeEndObserver()
        let url = currentSource == "Drive" ? selection.previewURL : selection.finalURL
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        
        if selection.resumeTime > 2 {
            player.seek(to: CMTime(seconds: selection.resumeTime, preferredTimescale: 600))
        }
        
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { _ in
            Task {
                await saveCurrentProgress()
                await model.playNextVideo(after: selection)
            }
        }
        if autoplay { player.play() }
    }

    private func removeEndObserver() {
        if let observer = endObserver {
            NotificationCenter.default.removeObserver(observer)
            endObserver = nil
        }
    }

    private func saveCurrentProgress() async {
        let seconds = player.currentTime().seconds
        guard seconds.isFinite else { return }
        await model.saveWatchProgress(folder: selection.watchFolder, episodeIndex: selection.episodeIndex, time: seconds)
    }
}
"""

# Replace VideosView to EpisodeListPanel
v_start = content.find("struct VideosView: View {")
v_end_token = "struct DictionaryView: View {"
v_end = content.find(v_end_token)

if v_start != -1 and v_end != -1:
    content = content[:v_start] + videos_view_new + "\n\n" + content[v_end:]

# Replace SeriesPosterCard to InlineVideoPlayer
p_start = content.find("struct SeriesPosterCard: View {")
p_end_token = "struct VideoPlayerSheet: View {"
p_end = content.find(p_end_token)
if p_end == -1: # Just in case it's not there, fallback to SeriesCard
    p_end = content.find("struct SeriesCard: View {")

if p_start != -1 and p_end != -1:
    content = content[:p_start] + video_player_sheet + "\n\n" + content[p_end:]

# Inject account section into SettingsView
s_start_token = "struct SettingsView: View {"
s_start = content.find(s_start_token)
if s_start != -1:
    scroll_idx = content.find("ScreenScroll {", s_start)
    if scroll_idx != -1:
        insert_idx = scroll_idx + len("ScreenScroll {") + 1
        content = content[:insert_idx] + "\\n" + account_section + content[insert_idx:]

with open('ios/App/App/NativeApp.swift', 'w', encoding='utf-8') as f:
    f.write(content)

print("Updated perfectly.")
