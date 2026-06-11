import Foundation
import AVKit
import SwiftUI
import UIKit
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
    case videos
    case uploads
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pipeline: return "Pipeline"
        case .running: return "Running"
        case .scraper: return "Scrape"
        case .projects: return "Projects"
        case .videos: return "Videos"
        case .uploads: return "Tools"
        case .settings: return "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .pipeline: return "play.rectangle.fill"
        case .running: return "chart.line.uptrend.xyaxis"
        case .scraper: return "magnifyingglass.circle.fill"
        case .projects: return "rectangle.stack.fill"
        case .videos: return "play.square.fill"
        case .uploads: return "wrench.and.screwdriver.fill"
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
    var folderName: String
    var displayName: String
    var subtitle: String
    var created: String
    var series: String
    var episodeNo: Int?
    var progress: Int
    var steps: [String]
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

struct SeriesRow: Identifiable {
    let id = UUID()
    var folder: String
    var name: String
    var episodeRange: String
    var total: Int
    var rendered: Int
    var uploaded: Int
}

struct VideoSelection: Identifiable {
    let id = UUID()
    var title: String
    var subtitle: String
    var folderName: String
    var url: URL
    var previewURL: URL
    var finalURL: URL
}

struct StatusLine: Identifiable {
    let id = UUID()
    var title: String
    var value: String
    var tone: Color
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
    @Published var seriesRows: [SeriesRow] = []
    @Published var uploadRows: [UploadQueueRow] = []
    @Published var scrapeURL = ""
    @Published var scrapeMinDuration = "60"
    @Published var scrapeOldestFirst = true
    @Published var scrapeStatus = "Idle"
    @Published var scrapeLogLines: [String] = []
    @Published var scrapeVideos: [ScrapeVideo] = []
    @Published var selectedProject = ""
    @Published var uploadStatus = "Idle"
    @Published var runtimeLogLines: [String] = []
    @Published var runtimeLogTitle = "Chon item dang chay de xem log runtime"
    @Published var selectedRuntimeQueueId = ""
    @Published var selectedRuntimeItemIndex: Int?
    @Published var toolStatuses: [StatusLine] = []
    @Published var toolMessage = "San sang"
    @Published var selectedVideo: VideoSelection?

    private var pollTask: Task<Void, Never>?
    private var runtimeLogOffset = 0
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
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

    var renderedProjects: [ProjectRow] {
        projects.filter { $0.rendered }
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

    func enterBackgroundMode() {
        startPolling()
        guard backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "MiuBonRuntimeMonitor") { [weak self] in
            Task { @MainActor in
                self?.endBackgroundMode()
            }
        }
    }

    func endBackgroundMode() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    func refreshAll(silent: Bool = false) async {
        await refreshHealth(silent: silent)
        await refreshRunning()
        await refreshProjects()
        await refreshSeries()
        await refreshUploadQueue()
        if !activeQueueId.isEmpty { await pollQueue(activeQueueId) }
        if !activeJobId.isEmpty { await pollJob(activeJobId) }
        await pollSelectedRuntimeLogs()
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

    func selectRuntimeItem(queueId: String, itemIndex: Int) async {
        selectedRuntimeQueueId = queueId
        selectedRuntimeItemIndex = itemIndex
        runtimeLogOffset = 0
        runtimeLogLines = []
        runtimeLogTitle = "Queue \(queueId) | item #\(itemIndex + 1)"
        await pollSelectedRuntimeLogs()
    }

    func pollSelectedRuntimeLogs() async {
        guard !selectedRuntimeQueueId.isEmpty, let itemIndex = selectedRuntimeItemIndex else { return }
        do {
            let path = "/api/pipeline/queue/\(selectedRuntimeQueueId)/item/\(itemIndex)/logs?offset=\(runtimeLogOffset)"
            let result = try await api.request(path)
            let status = string(result["status"])
            let jobId = string(result["job_id"])
            runtimeLogTitle = "Queue \(selectedRuntimeQueueId) | item #\(itemIndex + 1)" + (status.isEmpty ? "" : " | \(status)") + (jobId.isEmpty ? "" : " | job \(jobId)")
            if let lines = result["lines"] as? [String], !lines.isEmpty {
                runtimeLogLines.append(contentsOf: lines)
                runtimeLogLines = Array(runtimeLogLines.suffix(400))
            }
            runtimeLogOffset = int(result["total"], fallback: runtimeLogOffset)
        } catch {
            runtimeLogTitle = "Runtime log error: \(error.localizedDescription)"
        }
    }

    func refreshProjects() async {
        do {
            let result = try await api.request("/api/projects")
            let rows = (result["projects"] as? [[String: Any]]) ?? []
            projects = rows.map(parseProject)
            if selectedProject.isEmpty, let first = projects.first {
                selectedProject = first.folderName
            }
        } catch {
            projects = []
        }
    }

    func refreshSeries() async {
        do {
            let result = try await api.request("/api/series")
            let rows = (result["series"] as? [[String: Any]]) ?? []
            seriesRows = rows.map(parseSeries)
        } catch {
            seriesRows = []
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
        scrapeLogLines = []
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
                if let logs = result["logs"] as? [String] {
                    scrapeLogLines = Array(logs.suffix(220))
                }
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

    func refreshToolStatuses() async {
        var rows: [StatusLine] = []
        if let youtube = try? await api.request("/api/youtube/auth") {
            rows.append(StatusLine(title: "YouTube", value: bool(youtube["ok"]) ? "OK" : string(youtube["status"], fallback: "Need login"), tone: bool(youtube["ok"]) ? .green : .orange))
        }
        if let tiktok = try? await api.request("/api/tiktok/api/status") {
            rows.append(StatusLine(title: "TikTok API", value: bool(tiktok["ok"]) ? "OK" : string(tiktok["error"], fallback: "Need auth"), tone: bool(tiktok["ok"]) ? .green : .orange))
        }
        if let facebook = try? await api.request("/api/facebook/reels/status") {
            rows.append(StatusLine(title: "Facebook", value: bool(facebook["ok"]) || bool(facebook["configured"]) ? "Configured" : "Need token", tone: bool(facebook["ok"]) ? .green : .orange))
        }
        if let drive = try? await api.request("/api/gdrive/status") {
            rows.append(StatusLine(title: "Google Drive", value: bool(drive["ok"]) || bool(drive["logged_in"]) ? "OK" : "Need login", tone: bool(drive["ok"]) || bool(drive["logged_in"]) ? .green : .orange))
        }
        if let douyin = try? await api.request("/api/douyin/watchdog/state") {
            rows.append(StatusLine(title: "Douyin Watchdog", value: bool(douyin["enabled"]) ? "ON" : "OFF", tone: bool(douyin["enabled"]) ? .green : .gray))
        }
        toolStatuses = rows
    }

    func runToolAction(title: String, path: String, method: String = "POST", body: [String: Any]? = nil) async {
        do {
            let result = try await api.request(path, method: method, body: body)
            toolMessage = string(result["message"], fallback: string(result["status"], fallback: string(result["ok"], fallback: "\(title) done")))
            NotificationCenterBridge.shared.notifyOnce(key: "tool-\(title)-\(Date().timeIntervalSince1970)", title: title, body: toolMessage)
            await refreshAll(silent: true)
            await refreshToolStatuses()
        } catch {
            toolMessage = "\(title): \(error.localizedDescription)"
        }
    }

    func openBackendPath(_ path: String) {
        guard let url = backendURLFor(path) else { return }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }

    func backendURLFor(_ path: String) -> URL? {
        let cleanBase = backendURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !cleanBase.isEmpty else { return nil }
        return URL(string: cleanBase + path)
    }

    func projectMediaURL(_ project: ProjectRow, file: String = "preview") -> URL? {
        guard !project.folderName.isEmpty else { return nil }
        let encodedProject = project.folderName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? project.folderName
        let encodedFile = file.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? file
        return backendURLFor("/api/project/\(encodedProject)/stream/\(encodedFile)")
    }

    func playProject(_ project: ProjectRow, file: String = "preview") {
        guard project.rendered else {
            statusMessage = "Project chua render xong nen chua xem duoc video"
            return
        }
        guard
            let previewURL = projectMediaURL(project, file: "preview"),
            let finalURL = projectMediaURL(project, file: "final_video.mp4"),
            let url = projectMediaURL(project, file: file)
        else {
            statusMessage = "Khong tao duoc URL video"
            return
        }
        selectedVideo = VideoSelection(
            title: project.displayName,
            subtitle: project.subtitle,
            folderName: project.folderName,
            url: url,
            previewURL: previewURL,
            finalURL: finalURL
        )
    }

    func openProjectVideo(_ project: ProjectRow, file: String = "preview") {
        guard let url = projectMediaURL(project, file: file) else {
            statusMessage = "Khong tao duoc URL video"
            return
        }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }

    func openURLFromEndpoint(title: String, path: String, key: String = "auth_url") async {
        do {
            let result = try await api.request(path)
            let raw = string(result[key], fallback: string(result["url"], fallback: string(result["login_url"])))
            guard let url = URL(string: raw) else {
                toolMessage = "\(title): backend khong tra URL"
                return
            }
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
            toolMessage = "\(title): opened auth URL"
        } catch {
            toolMessage = "\(title): \(error.localizedDescription)"
        }
    }

    func resumeProject(_ folderName: String) async {
        guard !folderName.isEmpty else { return }
        let encoded = folderName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? folderName
        await runToolAction(title: "Resume project", path: "/api/project/\(encoded)/resume")
    }
}

struct MiuBonRootView: View {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

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
                    VideosView().tag(MainTab.videos)
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
        .sheet(item: $model.selectedVideo) { selection in
            VideoPlayerSheet(selection: selection)
        }
        .task {
            await model.refreshAll()
            await model.refreshToolStatuses()
            model.startPolling()
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .active:
                model.endBackgroundMode()
                model.startPolling()
                Task { await model.refreshAll() }
            case .background:
                model.enterBackgroundMode()
            default:
                break
            }
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
                    QueueCard(queue: model.queue) { item in
                        Task { await model.selectRuntimeItem(queueId: model.queue.id, itemIndex: item.index) }
                    }
                }
                if model.runningQueues.isEmpty && model.queue.id.isEmpty {
                    EmptyState(text: "Chua co queue dang chay")
                }
                ForEach(model.runningQueues, id: \.id) { queue in
                    QueueCard(queue: queue) { item in
                        Task { await model.selectRuntimeItem(queueId: queue.id, itemIndex: item.index) }
                    }
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

            SectionCard(title: "Runtime logs", symbol: "terminal.fill") {
                Text(model.runtimeLogTitle)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if model.runtimeLogLines.isEmpty {
                    EmptyState(text: "Cham vao mot item dang chay de xem log truc tiep.")
                } else {
                    LogConsole(lines: model.runtimeLogLines, maxHeight: 360)
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

            if !model.scrapeLogLines.isEmpty {
                SectionCard(title: "Scrape logs", symbol: "terminal") {
                    LogConsole(lines: model.scrapeLogLines, maxHeight: 220)
                }
            }

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
            SectionCard(title: "Series library", symbol: "play.square.stack.fill") {
                if model.seriesRows.isEmpty {
                    EmptyState(text: "Chua co series hoac backend chua tra /api/series")
                }
                ForEach(model.seriesRows) { series in
                    SeriesCard(series: series)
                }
            }

            SectionCard(title: "Projects", symbol: "rectangle.stack") {
                if model.projects.isEmpty {
                    EmptyState(text: "Chua load duoc project tu backend")
                }
                ForEach(model.projects) { project in
                    ProjectCard(
                        project: project,
                        onResume: { Task { await model.resumeProject(project.folderName) } },
                        onPlay: { model.playProject(project) }
                    )
                }
            }
        }
    }
}

struct VideosView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScreenScroll {
            SectionCard(title: "Video da render", symbol: "play.square.stack.fill") {
                HStack {
                    Text("\(model.renderedProjects.count) video san sang")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    SmallButton(title: "Refresh", symbol: "arrow.clockwise") {
                        Task { await model.refreshProjects() }
                    }
                    .frame(width: 120)
                }

                if model.renderedProjects.isEmpty {
                    EmptyState(text: "Chua co project nao render xong de xem video.")
                }

                ForEach(model.renderedProjects) { project in
                    VideoLibraryCard(
                        project: project,
                        thumbnailURL: model.projectMediaURL(project, file: "thumbnail.jpg"),
                        onPreview: { model.playProject(project, file: "preview") },
                        onFull: { model.playProject(project, file: "final_video.mp4") },
                        onOpen: { model.openProjectVideo(project, file: "preview") }
                    )
                }
            }
        }
    }
}

struct UploadsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScreenScroll {
            SectionCard(title: "Tai khoan & trang thai", symbol: "person.crop.circle.badge.checkmark") {
                if model.toolStatuses.isEmpty {
                    EmptyState(text: "Cham Refresh de kiem tra YouTube, TikTok, Facebook, Drive, Watchdog.")
                }
                ForEach(model.toolStatuses) { row in
                    HStack {
                        Text(row.title).font(.subheadline.weight(.semibold))
                        Spacer()
                        StatusPill(text: row.value, tone: row.tone)
                    }
                    .padding(10)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                Text(model.toolMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    SmallButton(title: "Refresh", symbol: "arrow.clockwise") { Task { await model.refreshToolStatuses() } }
                    SmallButton(title: "YouTube login", symbol: "play.tv") { Task { await model.runToolAction(title: "YouTube login", path: "/api/youtube/login") } }
                    SmallButton(title: "TikTok OAuth", symbol: "music.note") { Task { await model.openURLFromEndpoint(title: "TikTok OAuth", path: "/api/tiktok/oauth/start") } }
                    SmallButton(title: "Drive login", symbol: "externaldrive") { model.openBackendPath("/api/gdrive/login") }
                }
            }

            SectionCard(title: "Upload nhanh", symbol: "arrow.up.circle") {
                Picker("Project", selection: $model.selectedProject) {
                    ForEach(model.projects) { project in
                        Text(project.displayName).tag(project.folderName)
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
                HStack {
                    SmallButton(title: "Sort tap", symbol: "arrow.up.arrow.down") {
                        Task { await model.runToolAction(title: "Sort YouTube queue", path: "/api/youtube/queue/sort", body: ["mode": "episode_asc"]) }
                    }
                    SmallButton(title: "Watchdog", symbol: "shield.lefthalf.filled") {
                        Task { await model.runToolAction(title: "YouTube watchdog", path: "/api/youtube/watchdog/run-once") }
                    }
                }
                if model.uploadRows.isEmpty {
                    EmptyState(text: "Queue upload YouTube dang trong")
                }
                ForEach(model.uploadRows) { row in
                    UploadRowView(row: row)
                }
            }

            SectionCard(title: "Dong bo & watchdog", symbol: "antenna.radiowaves.left.and.right") {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    SmallButton(title: "Drive sync", symbol: "arrow.triangle.2.circlepath") {
                        Task { await model.runToolAction(title: "Drive sync", path: "/api/gdrive/sync_projects_async") }
                    }
                    SmallButton(title: "Mass upload Drive", symbol: "icloud.and.arrow.up") {
                        Task { await model.runToolAction(title: "Drive mass upload", path: "/api/gdrive/mass_upload_videos") }
                    }
                    SmallButton(title: "Douyin watchdog", symbol: "magnifyingglass.circle") {
                        Task { await model.runToolAction(title: "Douyin watchdog", path: "/api/douyin/watchdog/run-once") }
                    }
                    SmallButton(title: "FB pages", symbol: "f.circle") {
                        Task { await model.runToolAction(title: "Facebook status", path: "/api/facebook/reels/status", method: "GET") }
                    }
                }
            }
        }
        .task { await model.refreshToolStatuses() }
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
                Text("App native nay goi backend MBVietSub qua API. Render, Playwright scrape, ffmpeg va upload van chay tren PC/server. Khi app vao nen, iOS cho poll tiep trong mot khoang thoi gian de gui local notification; neu user kill app han thi can push notification/APNs tu backend moi bao dam van bao.")
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
    var onSelect: ((QueueItem) -> Void)? = nil

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

            ForEach(queue.items.prefix(18)) { item in
                Button {
                    onSelect?(item)
                } label: {
                    HStack(alignment: .top, spacing: 8) {
                        Text("#\(item.index + 1)")
                            .font(.caption.monospacedDigit().weight(.bold))
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.url.isEmpty ? item.message : item.url)
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
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
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
            LogConsole(lines: lines, maxHeight: 280)
        }
    }
}

struct LogConsole: View {
    var lines: [String]
    var maxHeight: CGFloat

    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            ScrollView(.vertical, showsIndicators: true) {
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
            .frame(maxHeight: maxHeight)
        }
        .background(Color.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct ProjectCard: View {
    var project: ProjectRow
    var onResume: (() -> Void)? = nil
    var onPlay: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text(project.displayName)
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .lineLimit(2)
                Spacer()
                StatusPill(text: "\(project.progress)%", tone: project.progress >= 100 ? .green : .orange)
            }
            Text(project.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Text([project.series, project.created].filter { !$0.isEmpty }.joined(separator: " - "))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            ProgressView(value: Double(project.progress) / 100.0)
                .tint(project.progress >= 100 ? .green : .orange)
            Text(project.steps.joined(separator: " -> "))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            HStack {
                StatusPill(text: project.rendered ? "Render" : "No render", tone: project.rendered ? .green : .orange)
                StatusPill(text: project.youtube ? "YT" : "YT wait", tone: project.youtube ? .green : .gray)
                StatusPill(text: project.tiktok ? "TT" : "TT wait", tone: project.tiktok ? .pink : .gray)
                StatusPill(text: project.facebook ? "FB" : "FB wait", tone: project.facebook ? .blue : .gray)
            }
            if onPlay != nil || onResume != nil {
                HStack(spacing: 10) {
                    if let onPlay = onPlay, project.rendered {
                        SmallButton(title: "Xem", symbol: "play.rectangle.fill", action: onPlay)
                    }
                    if let onResume = onResume {
                        SmallButton(title: "Resume", symbol: "arrow.clockwise", action: onResume)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct VideoLibraryCard: View {
    var project: ProjectRow
    var thumbnailURL: URL?
    var onPreview: () -> Void
    var onFull: () -> Void
    var onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: onPreview) {
                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [.black.opacity(0.84), .black.opacity(0.54), .accentColor.opacity(0.28)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    if let thumbnailURL = thumbnailURL {
                        AsyncImage(url: thumbnailURL) { phase in
                            if let image = phase.image {
                                image
                                    .resizable()
                                    .scaledToFill()
                            } else {
                                Color.clear
                            }
                        }
                    }
                    VStack(spacing: 8) {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 44, weight: .semibold))
                            .foregroundStyle(.white)
                            .shadow(radius: 12)
                        Text("Tap de xem preview")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white.opacity(0.88))
                    }
                }
                .frame(height: 190)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                Text(project.displayName)
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .lineLimit(2)
                Text(project.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            HStack(spacing: 10) {
                SmallButton(title: "Preview", symbol: "play.fill", action: onPreview)
                SmallButton(title: "Full", symbol: "film.fill", action: onFull)
                SmallButton(title: "Open", symbol: "safari.fill", action: onOpen)
            }
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

struct VideoPlayerSheet: View {
    var selection: VideoSelection
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer
    @State private var currentURL: URL

    init(selection: VideoSelection) {
        self.selection = selection
        _currentURL = State(initialValue: selection.url)
        _player = State(initialValue: AVPlayer(url: selection.url))
    }

    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 14) {
                VideoPlayer(player: player)
                    .frame(height: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(.white.opacity(0.18)))

                VStack(alignment: .leading, spacing: 5) {
                    Text(selection.title)
                        .font(.system(.headline, design: .rounded).weight(.black))
                        .lineLimit(2)
                    Text(selection.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                    Text(currentURL.absoluteString)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                HStack(spacing: 10) {
                    SmallButton(title: "Preview", symbol: "bolt.fill") {
                        switchTo(selection.previewURL)
                    }
                    SmallButton(title: "Full", symbol: "film.fill") {
                        switchTo(selection.finalURL)
                    }
                    SmallButton(title: "Open", symbol: "safari.fill") {
                        UIApplication.shared.open(currentURL, options: [:], completionHandler: nil)
                    }
                }

                Text("Preview dung final_video_preview.mp4 neu backend da tao, neu khong co se fallback sang final_video.mp4.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Spacer()
            }
            .padding(16)
            .background(AppBackground())
            .navigationBarTitle("Xem video", displayMode: .inline)
            .navigationBarItems(trailing: Button("Dong") { dismiss() })
        }
        .onAppear { player.play() }
        .onDisappear { player.pause() }
    }

    private func switchTo(_ url: URL) {
        currentURL = url
        player.pause()
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
        player.play()
    }
}

struct SeriesCard: View {
    var series: SeriesRow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(series.name)
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .lineLimit(2)
            Text("Folder: \(series.folder)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            HStack {
                StatusPill(text: series.episodeRange, tone: .blue)
                StatusPill(text: "\(series.rendered)/\(series.total) render", tone: series.rendered == series.total ? .green : .orange)
                StatusPill(text: "\(series.uploaded) uploaded", tone: series.uploaded > 0 ? .green : .gray)
            }
            ProgressView(value: series.total > 0 ? Double(series.rendered) / Double(series.total) : 0)
                .tint(.green)
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
    let metadata = data["metadata"] as? [String: Any] ?? [:]
    let douyin = data["douyin_meta"] as? [String: Any] ?? [:]
    let ctx = (data["series_context"] as? [String: Any]) ?? (metadata["series_context"] as? [String: Any]) ?? [:]
    let folder = string(data["project_name"], fallback: string(data["name"], fallback: string(data["folder"])))
    let metaTitle = string(metadata["title"])
    let douyinTitle = string(douyin["douyin_title"], fallback: string(douyin["title"]))
    let seriesName = string(ctx["series_name_vi"], fallback: string(ctx["series_name"], fallback: string(data["series_name"])))
    let epNo = intOptional(ctx["episode_no"]) ?? intOptional(data["episode_no"]) ?? extractEpisodeNo(metaTitle) ?? extractEpisodeNo(douyinTitle)
    let display: String
    if let episode = epNo, !seriesName.isEmpty {
        display = "Tap \(episode) | \(seriesName) | MiuBonVietSub"
    } else if !metaTitle.isEmpty {
        display = metaTitle
    } else if !douyinTitle.isEmpty {
        display = douyinTitle
    } else {
        display = folder
    }
    let allSteps = ["download", "separate", "stt", "translate", "tts", "render", "metadata", "upload"]
    let progress = min(100, Int(round(Double(steps.count) / Double(allSteps.count) * 100)))

    return ProjectRow(
        folderName: folder,
        displayName: display,
        subtitle: folder.isEmpty ? douyinTitle : folder,
        created: string(data["created_at"], fallback: string(data["updated_at"])),
        series: seriesName,
        episodeNo: epNo,
        progress: progress,
        steps: steps,
        rendered: steps.contains("render") || !string(data["final_video"]).isEmpty,
        youtube: !(string(youtube?["videoId"]).isEmpty && string(youtube?["url"]).isEmpty),
        tiktok: !(tiktok?.isEmpty ?? true),
        facebook: !(facebook?.isEmpty ?? true)
    )
}

func parseSeries(_ data: [String: Any]) -> SeriesRow {
    let minEp = intOptional(data["episode_min"])
    let maxEp = intOptional(data["episode_max"])
    let range = (minEp != nil || maxEp != nil) ? "Tap \(minEp.map(String.init) ?? "?")-\(maxEp.map(String.init) ?? "?")" : "Series"
    return SeriesRow(
        folder: string(data["series_folder"], fallback: string(data["folder"])),
        name: string(data["series_name"], fallback: string(data["name"], fallback: string(data["series_name_vi"], fallback: "Series"))),
        episodeRange: range,
        total: int(data["total_downloaded"], fallback: int(data["total"], fallback: (data["episodes"] as? [Any])?.count ?? 0)),
        rendered: int(data["rendered_count"]),
        uploaded: int(data["uploaded_count"])
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

func intOptional(_ value: Any?) -> Int? {
    if let value = value as? Int { return value }
    if let value = value as? Double { return Int(value) }
    if let value = value as? String, let parsed = Int(value) { return parsed }
    return nil
}

func extractEpisodeNo(_ text: String) -> Int? {
    let pattern = #"(?i)(?:tap|tập|ep|episode|第)\s*\.?\s*(\d{1,5})"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
    let nsrange = NSRange(text.startIndex..<text.endIndex, in: text)
    guard let match = regex.firstMatch(in: text, range: nsrange),
          match.numberOfRanges > 1,
          let range = Range(match.range(at: 1), in: text) else {
        return nil
    }
    return Int(text[range])
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
