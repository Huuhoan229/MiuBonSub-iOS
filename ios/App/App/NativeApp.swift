import Foundation
import SwiftUI
import UserNotifications

enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "Auto"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum MainTab: String, CaseIterable, Identifiable {
    case pipeline
    case running
    case scraper
    case projects
    case uploads
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pipeline: return "Pipeline"
        case .running: return "Running"
        case .scraper: return "Scrape"
        case .projects: return "Projects"
        case .uploads: return "Uploads"
        case .settings: return "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .pipeline: return "play.rectangle.fill"
        case .running: return "chart.line.uptrend.xyaxis"
        case .scraper: return "magnifyingglass.circle.fill"
        case .projects: return "rectangle.stack.fill"
        case .uploads: return "arrow.up.circle.fill"
        case .settings: return "slider.horizontal.3"
        }
    }
}

struct HealthSnapshot {
    var server = "Unknown"
    var youtube = "Unknown"
    var tiktok = "Unknown"
    var facebook = "Unknown"
    var drive = "Unknown"
}

struct QueueItem: Identifiable {
    let id = UUID()
    var index: Int
    var url: String
    var status: String
    var message: String
    var progress: Double
}

struct QueueSnapshot {
    var id = ""
    var status = ""
    var progress: Double = 0
    var message = ""
    var total = 0
    var completed = 0
    var items: [QueueItem] = []
}

struct ProjectRow: Identifiable {
    let id = UUID()
    var name: String
    var created: String
    var series: String
    var rendered: Bool
    var youtube: Bool
    var tiktok: Bool
    var facebook: Bool
}

struct UploadQueueRow: Identifiable {
    let id = UUID()
    var project: String
    var status: String
    var channel: String
    var message: String
}

struct ScrapeVideo: Identifiable {
    let id = UUID()
    var url: String
    var caption: String
    var duration: String
    var done: Bool
}

final class NotificationCenterBridge: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationCenterBridge()
    private var deliveredKeys = Set<String>()

    func configure() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    func notifyOnce(key: String, title: String, body: String) {
        guard deliveredKeys.insert(key).inserted else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: key, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }
}

final class MiuBonAPI {
    var baseURL: String

    init(baseURL: String) {
        self.baseURL = baseURL
    }

    func request(_ path: String, method: String = "GET", body: Any? = nil) async throws -> [String: Any] {
        let cleanBase = baseURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !cleanBase.isEmpty, let url = URL(string: cleanBase + path) else {
            throw NSError(domain: "MiuBonAPI", code: 1, userInfo: [NSLocalizedDescriptionKey: "Backend URL chua hop le"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let body = body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw NSError(domain: "MiuBonAPI", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: message])
        }

        if data.isEmpty { return [:] }
        let object = try JSONSerialization.jsonObject(with: data)
        return object as? [String: Any] ?? ["value": object]
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var backendURL: String {
        didSet { UserDefaults.standard.set(backendURL, forKey: "miubon.backendURL") }
    }
    @Published var themeRaw: String {
        didSet { UserDefaults.standard.set(themeRaw, forKey: "miubon.theme") }
    }
    @Published var pollSeconds: Int {
        didSet { UserDefaults.standard.set(pollSeconds, forKey: "miubon.pollSeconds") }
    }
    @Published var selectedTab: MainTab = .pipeline
    @Published var health = HealthSnapshot()
    @Published var isOnline = false
    @Published var statusMessage = "Chua ket noi backend"
    @Published var urlInput = ""
    @Published var activeJobId = ""
    @Published var activeQueueId = ""
    @Published var pipelineStatus = "Idle"
    @Published var pipelineProgress: Double = 0
    @Published var pipelineMessage = "San sang"
    @Published var logLines: [String] = []
    @Published var queue = QueueSnapshot()
    @Published var runningQueues: [QueueSnapshot] = []
    @Published var projects: [ProjectRow] = []
    @Published var uploadRows: [UploadQueueRow] = []
    @Published var scrapeURL = ""
    @Published var scrapeMinDuration = "60"
    @Published var scrapeOldestFirst = true
    @Published var scrapeStatus = "Idle"
    @Published var scrapeVideos: [ScrapeVideo] = []
    @Published var selectedProject = ""
    @Published var uploadStatus = "Idle"

    private var pollTask: Task<Void, Never>?
    private var api: MiuBonAPI { MiuBonAPI(baseURL: backendURL) }

    init() {
        backendURL = UserDefaults.standard.string(forKey: "miubon.backendURL") ?? "http://192.168.1.10:2209"
        themeRaw = UserDefaults.standard.string(forKey: "miubon.theme") ?? AppTheme.system.rawValue
        let savedPoll = UserDefaults.standard.integer(forKey: "miubon.pollSeconds")
        pollSeconds = savedPoll == 0 ? 3 : savedPoll
    }

    var theme: AppTheme {
        get { AppTheme(rawValue: themeRaw) ?? .system }
        set { themeRaw = newValue.rawValue }
    }

    func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshAll(silent: true)
                let seconds = max(1, self?.pollSeconds ?? 3)
                try? await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    func refreshAll(silent: Bool = false) async {
        await refreshHealth(silent: silent)
        await refreshRunning()
        await refreshProjects()
        await refreshUploadQueue()
        if !activeQueueId.isEmpty { await pollQueue(activeQueueId) }
        if !activeJobId.isEmpty { await pollJob(activeJobId) }
    }

    func refreshHealth(silent: Bool = false) async {
        do {
            let result = try await api.request("/api/health")
            health = parseHealth(result)
            isOnline = true
            statusMessage = "Backend online"
        } catch {
            isOnline = false
            if !silent { statusMessage = error.localizedDescription }
        }
    }

    func startPipeline(single: Bool) async {
        let urls = extractURLs(urlInput)
        guard !urls.isEmpty else {
            statusMessage = "Hay nhap Douyin/TikTok URL"
            return
        }

        do {
            if single && urls.count == 1 {
                let result = try await api.request("/api/pipeline/start", method: "POST", body: ["url": urls[0]])
                activeJobId = string(result["job_id"])
                pipelineStatus = "Running"
                pipelineMessage = "Pipeline da bat dau"
                pipelineProgress = 0.02
            } else {
                let result = try await api.request("/api/pipeline/batch", method: "POST", body: ["urls": urls.joined(separator: "\n")])
                activeQueueId = string(result["queue_id"])
                queue.id = activeQueueId
                pipelineStatus = "Queue running"
                pipelineMessage = "Queue da bat dau: \(urls.count) URL"
                selectedTab = .running
            }
            await refreshAll(silent: true)
        } catch {
            statusMessage = error.localizedDescription
            pipelineStatus = "Error"
        }
    }

    func pollJob(_ jobId: String) async {
        do {
            let result = try await api.request("/api/job/\(jobId)")
            let status = string(result["status"])
            pipelineStatus = status.isEmpty ? "Running" : status.capitalized
            let rawProgress = double(result["progress"], fallback: double(result["pct"], fallback: pipelineProgress))
            pipelineProgress = rawProgress > 1 ? rawProgress / 100 : rawProgress
            pipelineMessage = string(result["message"], fallback: string(result["stage"], fallback: pipelineMessage))
            if let logs = result["logs"] as? [String] {
                logLines = Array(logs.suffix(180))
            } else if let logResult = try? await api.request("/api/pipeline/logs/\(jobId)?offset=0"),
                      let lines = logResult["lines"] as? [String] {
                logLines = Array(lines.suffix(180))
            }
            if status == "done" {
                NotificationCenterBridge.shared.notifyOnce(
                    key: "pipeline-\(jobId)-done",
                    title: "Pipeline hoan thanh",
                    body: pipelineMessage.isEmpty ? "Render/upload da hoan thanh." : pipelineMessage
                )
                activeJobId = ""
            } else if status == "error" || status == "failed" {
                NotificationCenterBridge.shared.notifyOnce(key: "pipeline-\(jobId)-error", title: "Pipeline loi", body: pipelineMessage)
                activeJobId = ""
            }
        } catch {
            if !activeJobId.isEmpty { statusMessage = error.localizedDescription }
        }
    }

    func pollQueue(_ queueId: String) async {
        do {
            let result = try await api.request("/api/pipeline/queue/\(queueId)")
            let snapshot = parseQueue(result, knownId: queueId)
            queue = snapshot
            pipelineStatus = snapshot.status.capitalized
            pipelineProgress = snapshot.progress
            pipelineMessage = snapshot.message

            if snapshot.status == "done" || snapshot.status == "finished" {
                NotificationCenterBridge.shared.notifyOnce(
                    key: "queue-\(queueId)-done",
                    title: "Queue hoan thanh",
                    body: "\(snapshot.completed)/\(snapshot.total) video da xu ly."
                )
                activeQueueId = ""
            } else if snapshot.status.contains("error") || snapshot.status.contains("failed") {
                NotificationCenterBridge.shared.notifyOnce(
                    key: "queue-\(queueId)-error",
                    title: "Queue co loi",
                    body: snapshot.message.isEmpty ? "Kiem tra log de xem chi tiet." : snapshot.message
                )
            }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func refreshRunning() async {
        do {
            let result = try await api.request("/api/pipeline/queues")
            let rawQueues = (result["queues"] as? [[String: Any]]) ?? []
            runningQueues = rawQueues.map { parseQueue($0, knownId: string($0["queue_id"], fallback: string($0["id"]))) }
        } catch {
            runningQueues = []
        }
    }

    func queueAction(_ action: String, id: String) async {
        guard !id.isEmpty else { return }
        do {
            _ = try await api.request("/api/pipeline/queue/\(id)/\(action)", method: "POST", body: [:])
            await refreshAll(silent: true)
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func refreshProjects() async {
        do {
            let result = try await api.request("/api/projects")
            let rows = (result["projects"] as? [[String: Any]]) ?? []
            projects = rows.map(parseProject)
            if selectedProject.isEmpty, let first = projects.first {
                selectedProject = first.name
            }
        } catch {
            projects = []
        }
    }

    func refreshUploadQueue() async {
        do {
            let result = try await api.request("/api/youtube/queue")
            let rows = (result["items"] as? [[String: Any]]) ?? []
            uploadRows = rows.map {
                UploadQueueRow(
                    project: string($0["project_name"], fallback: string($0["project"])),
                    status: string($0["status"], fallback: "pending"),
                    channel: string($0["channel_key"], fallback: string($0["channel"])),
                    message: string($0["message"], fallback: string($0["error"]))
                )
            }
        } catch {
            uploadRows = []
        }
    }

    func startScrape() async {
        guard !scrapeURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            statusMessage = "Hay nhap URL profile Douyin"
            return
        }
        scrapeStatus = "Starting"
        scrapeVideos = []
        do {
            let result = try await api.request(
                "/api/douyin/scrape",
                method: "POST",
                body: [
                    "url": scrapeURL,
                    "user_url": scrapeURL,
                    "min_duration_sec": Int(scrapeMinDuration) ?? 60,
                    "oldest_first": scrapeOldestFirst
                ]
            )
            let jobId = string(result["job_id"])
            scrapeStatus = "Scanning"
            await pollScrape(jobId: jobId)
        } catch {
            scrapeStatus = "Error"
            statusMessage = error.localizedDescription
        }
    }

    func pollScrape(jobId: String) async {
        for _ in 0..<720 {
            do {
                let result = try await api.request("/api/douyin/scrape/\(jobId)")
                let status = string(result["status"], fallback: "running")
                scrapeStatus = status.capitalized
                if status == "done" {
                    let payload = (result["result"] as? [String: Any]) ?? [:]
                    let videos = (payload["videos"] as? [[String: Any]]) ?? []
                    scrapeVideos = videos.map {
                        ScrapeVideo(
                            url: string($0["url"]),
                            caption: string($0["desc"], fallback: string($0["caption"], fallback: "No caption")),
                            duration: string($0["duration"], fallback: string($0["duration_sec"])),
                            done: bool($0["local_done"])
                        )
                    }
                    NotificationCenterBridge.shared.notifyOnce(
                        key: "scrape-\(jobId)-done",
                        title: "Scrape user xong",
                        body: "Tim thay \(scrapeVideos.count) video."
                    )
                    return
                }
                if status == "error" || status == "failed" {
                    scrapeStatus = "Error"
                    NotificationCenterBridge.shared.notifyOnce(
                        key: "scrape-\(jobId)-error",
                        title: "Scrape user loi",
                        body: string(result["error"], fallback: "Kiem tra backend log.")
                    )
                    return
                }
            } catch {
                statusMessage = error.localizedDescription
            }
            try? await Task.sleep(nanoseconds: UInt64(max(1, pollSeconds)) * 1_000_000_000)
        }
    }

    func addScrapedNewVideosToPipeline() {
        let urls = scrapeVideos.filter { !$0.done }.map(\.url).filter { !$0.isEmpty }
        urlInput = urls.joined(separator: "\n")
        selectedTab = .pipeline
    }

    func uploadSelected(to target: String) async {
        guard !selectedProject.isEmpty else {
            uploadStatus = "Hay chon project da render"
            return
        }

        let path: String
        switch target {
        case "tiktok": path = "/api/tiktok/upload/start"
        case "facebook": path = "/api/facebook/reels/upload/start"
        case "drive": path = "/api/project/\(selectedProject.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? selectedProject)/upload_gdrive"
        default: path = "/api/youtube/queue/reupload"
        }

        do {
            let result = try await api.request(path, method: "POST", body: ["project_name": selectedProject, "project": selectedProject])
            uploadStatus = string(result["message"], fallback: string(result["status"], fallback: "Started"))
            if let jobId = result["job_id"] as? String {
                Task { await self.pollUploadJob(jobId: jobId, target: target) }
            }
        } catch {
            uploadStatus = error.localizedDescription
        }
    }

    func pollUploadJob(jobId: String, target: String) async {
        let endpoint: String
        switch target {
        case "tiktok": endpoint = "/api/tiktok/upload/\(jobId)"
        case "facebook": endpoint = "/api/facebook/reels/upload/\(jobId)"
        case "drive": endpoint = "/api/gdrive/job/\(jobId)"
        default: endpoint = "/api/job/\(jobId)"
        }

        for _ in 0..<720 {
            do {
                let result = try await api.request(endpoint)
                let status = string(result["status"], fallback: string(result["state"], fallback: "running"))
                uploadStatus = "\(target): \(status)"
                if status == "done" || status == "success" {
                    NotificationCenterBridge.shared.notifyOnce(
                        key: "\(target)-\(jobId)-done",
                        title: "\(target.uppercased()) upload thanh cong",
                        body: selectedProject
                    )
                    await refreshUploadQueue()
                    return
                }
                if status == "error" || status == "failed" {
                    NotificationCenterBridge.shared.notifyOnce(
                        key: "\(target)-\(jobId)-error",
                        title: "\(target.uppercased()) upload loi",
                        body: string(result["error"], fallback: selectedProject)
                    )
                    return
                }
            } catch {
                uploadStatus = error.localizedDescription
            }
            try? await Task.sleep(nanoseconds: UInt64(max(1, pollSeconds)) * 1_000_000_000)
        }
    }
}

struct MiuBonRootView: View {
    @StateObject private var model = AppModel()

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 0) {
                HeaderView()
                    .environmentObject(model)
                TabView(selection: $model.selectedTab) {
                    PipelineView().tag(MainTab.pipeline)
                    RunningView().tag(MainTab.running)
                    ScraperView().tag(MainTab.scraper)
                    ProjectsView().tag(MainTab.projects)
                    UploadsView().tag(MainTab.uploads)
                    SettingsView().tag(MainTab.settings)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.24), value: model.selectedTab)
                BottomTabs()
                    .environmentObject(model)
            }
        }
        .environmentObject(model)
        .preferredColorScheme(model.theme.colorScheme)
        .task {
            await model.refreshAll()
            model.startPolling()
        }
        .onDisappear { model.stopPolling() }
    }
}

struct AppBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        LinearGradient(
            colors: scheme == .dark
                ? [Color(red: 0.05, green: 0.06, blue: 0.07), Color(red: 0.09, green: 0.11, blue: 0.12), Color(red: 0.05, green: 0.09, blue: 0.09)]
                : [Color(red: 0.96, green: 0.98, blue: 0.97), Color(red: 0.91, green: 0.96, blue: 0.94), Color(red: 0.98, green: 0.97, blue: 0.93)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
        .overlay {
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(scheme == .dark ? 0.24 : 0.34)
                .ignoresSafeArea()
        }
    }
}

struct HeaderView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("MiuBon Vietsub")
                    .font(.system(.title3, design: .rounded).weight(.black))
                Text(model.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            StatusPill(text: model.isOnline ? "Online" : "Offline", tone: model.isOnline ? .green : .red)
            ThemeToggle()
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(.ultraThinMaterial)
    }
}

struct ThemeToggle: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                model.theme = model.theme == .dark ? .light : .dark
            }
        } label: {
            Image(systemName: model.theme == .dark ? "moon.fill" : "sun.max.fill")
                .font(.system(size: 15, weight: .bold))
                .frame(width: 36, height: 36)
                .background(.regularMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Chuyen Light Dark")
    }
}

struct BottomTabs: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 6) {
            ForEach(MainTab.allCases) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.22)) { model.selectedTab = tab }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.symbol).font(.system(size: 18, weight: .semibold))
                        Text(tab.title).font(.system(size: 10, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .foregroundStyle(model.selectedTab == tab ? Color.accentColor : .secondary)
                    .background {
                        if model.selectedTab == tab {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(.regularMaterial)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
    }
}

struct PipelineView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScreenScroll {
            SectionCard(title: "System", symbol: "server.rack") {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    MetricTile(title: "Backend", value: model.health.server, tone: model.isOnline ? .green : .red)
                    MetricTile(title: "YouTube", value: model.health.youtube, tone: .blue)
                    MetricTile(title: "TikTok", value: model.health.tiktok, tone: .pink)
                    MetricTile(title: "Facebook", value: model.health.facebook, tone: .indigo)
                }
            }

            SectionCard(title: "Tao pipeline", symbol: "link") {
                TextEditor(text: $model.urlInput)
                    .frame(minHeight: 150)
                    .padding(10)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(alignment: .topLeading) {
                        if model.urlInput.isEmpty {
                            Text("Paste Douyin/TikTok URL, moi link mot dong...")
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 18)
                        }
                    }

                HStack(spacing: 10) {
                    PrimaryAction(title: "Start 1", symbol: "play.fill") {
                        Task { await model.startPipeline(single: true) }
                    }
                    PrimaryAction(title: "Start Queue", symbol: "list.bullet.rectangle") {
                        Task { await model.startPipeline(single: false) }
                    }
                }
            }

            ProgressCard(
                title: model.pipelineStatus,
                message: model.pipelineMessage,
                progress: model.pipelineProgress
            )

            if !model.logLines.isEmpty {
                LogCard(lines: model.logLines)
            }
        }
    }
}

struct RunningView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScreenScroll {
            SectionCard(title: "Queue dang chay", symbol: "waveform.path.ecg") {
                if !model.queue.id.isEmpty {
                    QueueCard(queue: model.queue)
                }
                if model.runningQueues.isEmpty && model.queue.id.isEmpty {
                    EmptyState(text: "Chua co queue dang chay")
                }
                ForEach(model.runningQueues, id: \.id) { queue in
                    QueueCard(queue: queue)
                    HStack {
                        SmallButton(title: "Pause", symbol: "pause.fill") {
                            Task { await model.queueAction("pause", id: queue.id) }
                        }
                        SmallButton(title: "Resume", symbol: "play.fill") {
                            Task { await model.queueAction("resume", id: queue.id) }
                        }
                        SmallButton(title: "Skip", symbol: "forward.fill") {
                            Task { await model.queueAction("skip", id: queue.id) }
                        }
                    }
                }
            }
        }
    }
}

struct ScraperView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScreenScroll {
            SectionCard(title: "Douyin user scraper", symbol: "person.crop.circle.badge.plus") {
                TextField("https://www.douyin.com/user/...", text: $model.scrapeURL)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .inputShell()

                HStack {
                    TextField("Min duration", text: $model.scrapeMinDuration)
                        .keyboardType(.numberPad)
                        .inputShell()
                    Toggle("Oldest", isOn: $model.scrapeOldestFirst)
                        .toggleStyle(.switch)
                }

                PrimaryAction(title: "Scan videos", symbol: "magnifyingglass") {
                    Task { await model.startScrape() }
                }
            }

            ProgressCard(title: model.scrapeStatus, message: "\(model.scrapeVideos.count) video", progress: model.scrapeStatus == "Done" ? 1 : 0.15)

            if !model.scrapeVideos.isEmpty {
                SectionCard(title: "Ket qua scrape", symbol: "film.stack") {
                    PrimaryAction(title: "Add video moi vao Pipeline", symbol: "plus.circle.fill") {
                        model.addScrapedNewVideosToPipeline()
                    }
                    ForEach(model.scrapeVideos) { video in
                        ScrapeVideoCard(video: video)
                    }
                }
            }
        }
    }
}

struct ProjectsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScreenScroll {
            SectionCard(title: "Projects", symbol: "rectangle.stack") {
                if model.projects.isEmpty {
                    EmptyState(text: "Chua load duoc project tu backend")
                }
                ForEach(model.projects) { project in
                    ProjectCard(project: project)
                }
            }
        }
    }
}

struct UploadsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScreenScroll {
            SectionCard(title: "Upload nhanh", symbol: "arrow.up.circle") {
                Picker("Project", selection: $model.selectedProject) {
                    ForEach(model.projects) { project in
                        Text(project.name).tag(project.name)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    SmallButton(title: "TikTok", symbol: "music.note") { Task { await model.uploadSelected(to: "tiktok") } }
                    SmallButton(title: "Facebook", symbol: "f.circle.fill") { Task { await model.uploadSelected(to: "facebook") } }
                    SmallButton(title: "Drive", symbol: "externaldrive.fill") { Task { await model.uploadSelected(to: "drive") } }
                    SmallButton(title: "YouTube queue", symbol: "play.tv.fill") { Task { await model.refreshUploadQueue() } }
                }
                Text(model.uploadStatus)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            SectionCard(title: "YouTube queue", symbol: "list.bullet.clipboard") {
                if model.uploadRows.isEmpty {
                    EmptyState(text: "Queue upload YouTube dang trong")
                }
                ForEach(model.uploadRows) { row in
                    UploadRowView(row: row)
                }
            }
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScreenScroll {
            SectionCard(title: "Backend", symbol: "network") {
                TextField("http://IP-PC:2209", text: $model.backendURL)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .inputShell()
                PrimaryAction(title: "Test ket noi", symbol: "bolt.horizontal.circle.fill") {
                    Task { await model.refreshAll() }
                }
            }

            SectionCard(title: "Giao dien", symbol: "paintpalette.fill") {
                Picker("Theme", selection: Binding(get: { model.theme }, set: { model.theme = $0 })) {
                    ForEach(AppTheme.allCases) { theme in
                        Text(theme.label).tag(theme)
                    }
                }
                .pickerStyle(.segmented)

                Stepper("Polling \(model.pollSeconds)s", value: $model.pollSeconds, in: 1...15)
                    .padding(.top, 6)
            }

            SectionCard(title: "Ghi chu build", symbol: "shippingbox.fill") {
                Text("App native nay goi backend MBVietSub qua API. Render, Playwright scrape, ffmpeg va upload van chay tren PC/server; iPhone dung de dieu khien va nhan thong bao.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct ScreenScroll<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(spacing: 14) { content }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 24)
        }
    }
}

struct SectionCard<Content: View>: View {
    var title: String
    var symbol: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(title, systemImage: symbol)
                    .font(.system(.headline, design: .rounded).weight(.bold))
                Spacer()
            }
            content
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(.white.opacity(0.18)))
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }
}

struct ProgressCard: View {
    var title: String
    var message: String
    var progress: Double

    var body: some View {
        SectionCard(title: "Trang thai", symbol: "gauge.with.dots.needle.bottom.50percent") {
            HStack {
                Text(title)
                    .font(.system(.headline, design: .rounded).weight(.bold))
                Spacer()
                Text("\(Int(max(0, min(progress, 1)) * 100))%")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: max(0, min(progress, 1)))
                .tint(.accentColor)
            Text(message.isEmpty ? "Dang cho backend cap nhat..." : message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
    }
}

struct QueueCard: View {
    var queue: QueueSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(queue.id.isEmpty ? "Queue" : queue.id)
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .lineLimit(1)
                Spacer()
                StatusPill(text: queue.status.isEmpty ? "running" : queue.status, tone: queue.status.contains("done") ? .green : .blue)
            }
            ProgressView(value: queue.progress)
            Text(queue.message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            ForEach(queue.items.prefix(12)) { item in
                HStack(alignment: .top, spacing: 8) {
                    Text("#\(item.index + 1)")
                        .font(.caption.monospacedDigit().weight(.bold))
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.url)
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(item.message.isEmpty ? item.status : item.message)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer()
                    StatusPill(text: item.status, tone: item.status.contains("done") ? .green : item.status.contains("error") || item.status.contains("failed") ? .red : .orange)
                }
            }
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct LogCard: View {
    var lines: [String]

    var body: some View {
        SectionCard(title: "Logs", symbol: "terminal.fill") {
            ScrollView(.horizontal, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .foregroundStyle(.green.opacity(0.9))
                            .lineLimit(1)
                    }
                }
                .padding(12)
                .frame(minWidth: UIScreen.main.bounds.width - 64, alignment: .leading)
            }
            .frame(maxHeight: 280)
            .background(Color.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

struct ProjectCard: View {
    var project: ProjectRow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(project.name)
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .lineLimit(2)
            Text([project.series, project.created].filter { !$0.isEmpty }.joined(separator: " - "))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            HStack {
                StatusPill(text: project.rendered ? "Render" : "No render", tone: project.rendered ? .green : .orange)
                StatusPill(text: project.youtube ? "YT" : "YT wait", tone: project.youtube ? .green : .gray)
                StatusPill(text: project.tiktok ? "TT" : "TT wait", tone: project.tiktok ? .pink : .gray)
                StatusPill(text: project.facebook ? "FB" : "FB wait", tone: project.facebook ? .blue : .gray)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct ScrapeVideoCard: View {
    var video: ScrapeVideo

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                StatusPill(text: video.done ? "Done" : "New", tone: video.done ? .green : .orange)
                Spacer()
                Text(video.duration)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text(video.caption)
                .font(.subheadline)
                .lineLimit(3)
            Text(video.url)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct UploadRowView: View {
    var row: UploadQueueRow

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(row.project)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Text([row.channel, row.message].filter { !$0.isEmpty }.joined(separator: " - "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            StatusPill(text: row.status, tone: row.status.contains("done") ? .green : row.status.contains("fail") ? .red : .blue)
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct MetricTile: View {
    var title: String
    var value: String
    var tone: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value.isEmpty ? "Unknown" : value)
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
        .padding(12)
        .background(tone.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct StatusPill: View {
    var text: String
    var tone: Color

    var body: some View {
        Text(text.isEmpty ? "unknown" : text)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(tone.opacity(0.16), in: Capsule())
            .foregroundStyle(tone)
    }
}

struct PrimaryAction: View {
    var title: String
    var symbol: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }
}

struct SmallButton: View {
    var title: String
    var symbol: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct EmptyState: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
    }
}

extension View {
    func inputShell() -> some View {
        self
            .padding(12)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .autocorrectionDisabled()
    }
}

func extractURLs(_ text: String) -> [String] {
    let pattern = #"https?://[^\s"'<>)\]]+"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    return regex.matches(in: text, range: range).compactMap {
        guard let swiftRange = Range($0.range, in: text) else { return nil }
        return String(text[swiftRange]).trimmingCharacters(in: CharacterSet(charactersIn: ".,;"))
    }
}

func parseHealth(_ data: [String: Any]) -> HealthSnapshot {
    let youtube = data["youtube"] as? [String: Any]
    let tiktok = data["tiktok"] as? [String: Any]
    let facebook = data["facebook"] as? [String: Any]
    let drive = data["gdrive"] as? [String: Any]

    return HealthSnapshot(
        server: "OK",
        youtube: bool(youtube?["ok"]) ? "OK" : "\(int(youtube?["enabled_count"])) channel",
        tiktok: bool(tiktok?["ok"]) || bool(tiktok?["connected"]) ? "OK" : "Need auth",
        facebook: bool(facebook?["ok"]) || bool(facebook?["configured"]) ? "OK" : "Need token",
        drive: bool(drive?["ok"]) ? "OK" : "Optional"
    )
}

func parseQueue(_ data: [String: Any], knownId: String) -> QueueSnapshot {
    let summary = (data["summary"] as? [String: Any]) ?? data
    let nestedQueue = (data["queue"] as? [String: Any]) ?? [:]
    let runtimeItems = (nestedQueue["runtime_items"] as? [[String: Any]]) ?? []
    let itemsRaw = (summary["items"] as? [[String: Any]]) ?? runtimeItems
    let fallbackUrls = (nestedQueue["urls"] as? [String]) ?? []
    let total = int(data["total"], fallback: itemsRaw.count)
    let resolvedTotal = int(summary["total"], fallback: int(nestedQueue["total"], fallback: total > 0 ? total : max(itemsRaw.count, fallbackUrls.count)))
    let completed = int(summary["completed"], fallback: int(nestedQueue["completed"], fallback: itemsRaw.filter { string($0["status"]).contains("done") }.count))
    let pct = double(summary["progress"], fallback: double(data["progress"], fallback: resolvedTotal > 0 ? Double(completed) / Double(resolvedTotal) : 0))
    let items: [QueueItem]
    if itemsRaw.isEmpty && !fallbackUrls.isEmpty {
        items = fallbackUrls.enumerated().map { offset, url in
            QueueItem(
                index: offset,
                url: url,
                status: offset < completed ? "done" : "waiting",
                message: offset < completed ? "Done" : "Waiting",
                progress: offset < completed ? 1 : 0
            )
        }
    } else {
        items = itemsRaw.enumerated().map { offset, item in
            QueueItem(
                index: int(item["index"], fallback: offset),
                url: string(item["url"], fallback: string(item["project"])),
                status: string(item["status"], fallback: "waiting"),
                message: string(item["status_text"], fallback: string(item["message"], fallback: string(item["error"]))),
                progress: double(item["progress"])
            )
        }
    }

    return QueueSnapshot(
        id: knownId.isEmpty ? string(summary["queue_id"], fallback: string(summary["id"], fallback: string(data["queue_id"], fallback: string(data["id"])))) : knownId,
        status: string(summary["status"], fallback: string(data["status"], fallback: "running")),
        progress: pct > 1 ? pct / 100 : pct,
        message: string(summary["message"], fallback: string(data["message"], fallback: "\(completed)/\(resolvedTotal) complete")),
        total: resolvedTotal,
        completed: completed,
        items: items
    )
}

func parseProject(_ data: [String: Any]) -> ProjectRow {
    let steps = data["steps_completed"] as? [String] ?? []
    let youtube = data["youtube"] as? [String: Any]
    let tiktok = data["tiktok"] as? [String: Any]
    let facebook = data["facebook_reels"] as? [String: Any]

    return ProjectRow(
        name: string(data["project_name"], fallback: string(data["name"], fallback: string(data["folder"]))),
        created: string(data["created_at"], fallback: string(data["updated_at"])),
        series: string(data["series"], fallback: string(data["series_name"])),
        rendered: steps.contains("render") || !string(data["final_video"]).isEmpty,
        youtube: !(string(youtube?["videoId"]).isEmpty && string(youtube?["url"]).isEmpty),
        tiktok: !(tiktok?.isEmpty ?? true),
        facebook: !(facebook?.isEmpty ?? true)
    )
}

func string(_ value: Any?, fallback: String = "") -> String {
    if let value = value as? String { return value }
    if let value = value { return String(describing: value) }
    return fallback
}

func int(_ value: Any?, fallback: Int = 0) -> Int {
    if let value = value as? Int { return value }
    if let value = value as? Double { return Int(value) }
    if let value = value as? String, let parsed = Int(value) { return parsed }
    return fallback
}

func double(_ value: Any?, fallback: Double = 0) -> Double {
    if let value = value as? Double { return value }
    if let value = value as? Int { return Double(value) }
    if let value = value as? String, let parsed = Double(value) { return parsed }
    return fallback
}

func bool(_ value: Any?) -> Bool {
    if let value = value as? Bool { return value }
    if let value = value as? Int { return value != 0 }
    if let value = value as? String { return ["true", "1", "yes", "ok"].contains(value.lowercased()) }
    return false
}
