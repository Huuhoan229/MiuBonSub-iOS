import Foundation
import AVFoundation
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
    case dictionary
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
        case .dictionary: return "Dict"
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
        case .dictionary: return "book.closed.fill"
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
    var seriesFolder: String
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
    var translation: String = ""
}

struct SeriesRow: Identifiable {
    let id = UUID()
    var folder: String
    var name: String
    var episodeRange: String
    var total: Int
    var rendered: Int
    var uploaded: Int
    var episodes: [SeriesEpisode] = []
}

struct SeriesEpisode: Identifiable {
    let id = UUID()
    var projectName: String
    var title: String
    var episodeNo: Int
    var rendered: Bool
    var created: String
}

struct WatchProgress {
    var episodeIndex: Int
    var time: Double
}

struct AISeriesGroup: Identifiable {
    let id = UUID()
    var folder: String
    var name: String
    var originalName: String
    var reason: String
    var confidence: Double
    var urls: [String]
    var uniqueURLs: [String]
    var episodeMin: Int?
    var episodeMax: Int?
    var duplicateCount: Int
    var videos: [[String: Any]]
}

struct DouyinWatchdogState {
    var enabled = false
    var userURLs = ""
    var intervalMin = "15"
    var minDurationSec = "60"
    var running = false
    var lastRun = "N/A"
    var summary = "Chua load watchdog"
}

struct GlossaryEntry: Identifiable {
    let id = UUID()
    var source: String
    var target: String
}

struct VideoSelection: Identifiable {
    let id = UUID()
    var title: String
    var subtitle: String
    var folderName: String
    var url: URL
    var previewURL: URL
    var finalURL: URL
    var watchFolder: String
    var episodeIndex: Int
    var resumeTime: Double
}

struct StatusLine: Identifiable {
    let id = UUID()
    var title: String
    var value: String
    var tone: Color
}

enum ConfigFieldKind {
    case text
    case number
    case toggle
}

struct ConfigField: Identifiable {
    var id: String { key }
    var key: String
    var label: String
    var group: String
    var kind: ConfigFieldKind
    var sensitive: Bool = false
    var placeholder: String = ""
}

struct ConfigRow: Identifiable {
    var id: String { key }
    var key: String
    var value: String
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

    func request(_ path: String, method: String = "GET", body: Any? = nil, authToken: String? = nil, timeout: TimeInterval = 30) async throws -> [String: Any] {
        let cleanBase = baseURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !cleanBase.isEmpty, let url = URL(string: cleanBase + path) else {
            throw NSError(domain: "MiuBonAPI", code: 1, userInfo: [NSLocalizedDescriptionKey: "Backend URL chua hop le"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let authToken, !authToken.isEmpty {
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        }

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

    func requestData(_ path: String, method: String = "GET", body: Any? = nil, timeout: TimeInterval = 120) async throws -> Data {
        let cleanBase = baseURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !cleanBase.isEmpty, let url = URL(string: cleanBase + path) else {
            throw NSError(domain: "MiuBonAPI", code: 1, userInfo: [NSLocalizedDescriptionKey: "Backend URL chua hop le"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body = body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw NSError(domain: "MiuBonAPI", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: message])
        }
        return data
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
    @Published var selectedVideoSeriesFolder = ""
    @Published var videoEpisodeSearch = ""
    @Published var configValues: [String: String] = [:]
    @Published var configRows: [ConfigRow] = []
    @Published var configMessage = "Chua load settings"
    @Published var translationTestMessage = "Chua test 9Router/WebAI"
    @Published var ttsTestMessage = "Chua test TTS/CapCut"
    @Published var warpTestMessage = "Chua test WARP"
    @Published var videoLibraryMode = "series"
    @Published var authUsername = ""
    @Published var authPassword = ""
    @Published var authToken: String {
        didSet { UserDefaults.standard.set(authToken, forKey: "miubon.authToken") }
    }
    @Published var authMessage = "Chua dang nhap"
    @Published var watchProgress: [String: WatchProgress] = [:]
    @Published var selectedGlossaryFolder = ""
    @Published var glossaryRows: [GlossaryEntry] = []
    @Published var glossarySourceInput = ""
    @Published var glossaryTargetInput = ""
    @Published var glossaryMessage = "Chon series de sua tu dien"
    @Published var selectedScrapeURLs: Set<String> = []
    @Published var aiSeriesGroups: [AISeriesGroup] = []
    @Published var selectedAIGroupIDs: Set<UUID> = []
    @Published var aiGroupMessage = "Chua AI group series"
    @Published var completedScrapeURLs: Set<String> = []
    @Published var douyinWatchdog = DouyinWatchdogState()

    private var pollTask: Task<Void, Never>?
    private var runtimeLogOffset = 0
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var pipelineURLContexts: [String: [String: Any]] = [:]
    private var api: MiuBonAPI { MiuBonAPI(baseURL: backendURL) }

    init() {
        backendURL = UserDefaults.standard.string(forKey: "miubon.backendURL") ?? "http://192.168.1.10:2209"
        themeRaw = UserDefaults.standard.string(forKey: "miubon.theme") ?? AppTheme.system.rawValue
        let savedPoll = UserDefaults.standard.integer(forKey: "miubon.pollSeconds")
        pollSeconds = savedPoll == 0 ? 3 : savedPoll
        authToken = UserDefaults.standard.string(forKey: "miubon.authToken") ?? ""
    }

    var theme: AppTheme {
        get { AppTheme(rawValue: themeRaw) ?? .system }
        set { themeRaw = newValue.rawValue }
    }

    var renderedProjects: [ProjectRow] {
        projects.filter { $0.rendered }
    }

    var standaloneProjects: [ProjectRow] {
        renderedProjects.filter { $0.series.isEmpty && $0.seriesFolder.isEmpty }
    }

    var effectiveSeriesRows: [SeriesRow] {
        if !seriesRows.isEmpty { return seriesRows }
        let grouped = Dictionary(grouping: renderedProjects.filter { !$0.series.isEmpty || !$0.seriesFolder.isEmpty }) { project in
            project.seriesFolder.isEmpty ? project.series : project.seriesFolder
        }
        return grouped.map { key, rows in
            let sorted = rows.sorted { ($0.episodeNo ?? 0) < ($1.episodeNo ?? 0) }
            let episodeNumbers = sorted.compactMap(\.episodeNo)
            let minEp = episodeNumbers.min()
            let maxEp = episodeNumbers.max()
            let episodes = sorted.map { project in
                SeriesEpisode(
                    projectName: project.folderName,
                    title: project.displayName,
                    episodeNo: project.episodeNo ?? 1,
                    rendered: project.rendered,
                    created: project.created
                )
            }
            return SeriesRow(
                folder: key,
                name: rows.first?.series.isEmpty == false ? rows.first?.series ?? key : key,
                episodeRange: (minEp != nil || maxEp != nil) ? "Tap \(minEp.map(String.init) ?? "?")-\(maxEp.map(String.init) ?? "?")" : "Series",
                total: rows.count,
                rendered: rows.filter(\.rendered).count,
                uploaded: rows.filter { $0.youtube || $0.tiktok || $0.facebook }.count,
                episodes: episodes
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
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
        if configValues.isEmpty { await refreshConfig() }
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
                let contexts = urls.reduce(into: [String: [String: Any]]()) { out, url in
                    if let context = pipelineURLContexts[url] { out[url] = context }
                }
                let result = try await api.request(
                    "/api/pipeline/batch",
                    method: "POST",
                    body: ["urls": urls.joined(separator: "\n"), "contexts": contexts]
                )
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
        selectedScrapeURLs = []
        aiSeriesGroups = []
        selectedAIGroupIDs = []
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
        if let health = try? await api.request("/api/health") {
            rows.append(StatusLine(title: "CapCut TTS", value: bool(health["capcut_ok"]) ? "OK" : "Offline", tone: bool(health["capcut_ok"]) ? .green : .orange))
            rows.append(StatusLine(title: "FFmpeg", value: string(health["ffmpeg_encoder"], fallback: "unknown"), tone: .blue))
            if let gpu = health["gpu_limiter"] as? [String: Any] {
                rows.append(StatusLine(title: "GPU limiter", value: "\(int(gpu["active"]))/\(int(gpu["limit"], fallback: int(gpu["max"], fallback: 1)))", tone: .indigo))
            }
            if let download = health["download_limiter"] as? [String: Any] {
                rows.append(StatusLine(title: "Download limiter", value: "\(int(download["active"]))/\(int(download["limit"], fallback: int(download["max"], fallback: 1)))", tone: .indigo))
            }
        }
        if let youtube = try? await api.request("/api/youtube/auth") {
            rows.append(StatusLine(title: "YouTube", value: bool(youtube["ok"]) ? "OK" : string(youtube["status"], fallback: "Need login"), tone: bool(youtube["ok"]) ? .green : .orange))
        }
        if let ytQueue = try? await api.request("/api/youtube/upload-queue/status") {
            rows.append(StatusLine(title: "YouTube Queue", value: "\(int(ytQueue["count"])) waiting", tone: int(ytQueue["count"]) > 0 ? .orange : .green))
        }
        if let tiktokBrowser = try? await api.request("/api/tiktok/auth") {
            rows.append(StatusLine(title: "TikTok Browser", value: bool(tiktokBrowser["ok"]) ? "OK" : string(tiktokBrowser["status"], fallback: "Need login"), tone: bool(tiktokBrowser["ok"]) ? .green : .orange))
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
        if let youtubeWatchdog = try? await api.request("/api/youtube/watchdog/state") {
            rows.append(StatusLine(title: "YouTube Watchdog", value: bool(youtubeWatchdog["enabled"]) ? "ON" : "OFF", tone: bool(youtubeWatchdog["enabled"]) ? .green : .gray))
        }
        toolStatuses = rows
    }

    func refreshConfig() async {
        do {
            let result = try await api.request("/api/config")
            var values: [String: String] = [:]
            for field in appConfigFields {
                if field.sensitive {
                    values[field.key] = ""
                } else {
                    values[field.key] = editableConfigValue(result[field.key], kind: field.kind)
                }
            }
            configValues = values
            configRows = result.keys.sorted().map { key in
                ConfigRow(key: key, value: safeConfigDisplay(key: key, value: result[key], masked: result["\(key)_masked"]))
            }
            configMessage = "Da load \(result.count) settings"
        } catch {
            configMessage = "Load settings loi: \(error.localizedDescription)"
        }
    }

    func saveConfig() async {
        guard !configValues.isEmpty else {
            configMessage = "Hay Reload settings truoc khi save"
            return
        }
        var payload: [String: Any] = [:]
        for field in appConfigFields {
            let raw = configValues[field.key] ?? ""
            if field.sensitive && raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                continue
            }
            payload[field.key] = configPayloadValue(raw, kind: field.kind)
        }

        do {
            _ = try await api.request("/api/config", method: "POST", body: payload)
            configMessage = "Da luu \(payload.count) settings"
            await refreshConfig()
            await refreshToolStatuses()
        } catch {
            configMessage = "Save settings loi: \(error.localizedDescription)"
        }
    }

    func testTranslationAPI() async {
        var body: [String: Any] = [
            "source_lang": configValues["source_lang"] ?? "zh",
            "target_lang": configValues["target_lang"] ?? "vi",
            "translation_provider": configValues["translation_provider"] ?? "9router",
            "translation_provider_order": configValues["translation_provider_order"] ?? "9router,webai",
            "ninerouter_url": configValues["ninerouter_url"] ?? "http://127.0.0.1:20128",
            "ninerouter_model": configValues["ninerouter_model"] ?? "",
            "ninerouter_timeout": int(configValues["ninerouter_timeout"], fallback: 180),
            "webai_url": configValues["webai_url"] ?? "http://127.0.0.1:6969",
            "webai_model": configValues["webai_model"] ?? "gemini-3-flash",
            "enable_webai_fallback": configBool(configValues["enable_webai_fallback"])
        ]
        if let key = configValues["ninerouter_key"], !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            body["ninerouter_key"] = key
        }
        do {
            let result = try await api.request("/api/translation/test", method: "POST", body: body)
            if bool(result["ok"]) {
                let provider = string(result["provider"], fallback: string(result["used_provider"], fallback: "provider"))
                let model = string(result["model"])
                let latency = string(result["latency_ms"])
                let sample = string(result["sample_output"])
                translationTestMessage = "OK: \(provider)" + (model.isEmpty ? "" : " | \(model)") + (latency.isEmpty ? "" : " | \(latency)ms") + (sample.isEmpty ? "" : " | \(sample)")
            } else {
                translationTestMessage = "Fail: " + string(result["error"], fallback: compactJSON(result["attempts"]))
            }
        } catch {
            translationTestMessage = "Connection error: \(error.localizedDescription)"
        }
    }

    func testTTSAPI() async {
        let engine = configValues["tts_engine"]?.isEmpty == false ? configValues["tts_engine"]! : "capcut"
        let body: [String: Any] = [
            "engine": engine,
            "vieneu_voice": configValues["vieneu_voice"] ?? "",
            "vieneu_mode": configValues["vieneu_mode"] ?? "preset",
            "ref_voice": configValues["vieneu_ref_voice"] ?? "",
            "capcut_voice": configValues["capcut_voice"] ?? "BV074_streaming",
            "auto_adjust_tts_speed": configBool(configValues["auto_adjust_tts_speed"]),
            "tts_speed": double(configValues["tts_speed"], fallback: 1),
            "tts_pitch": double(configValues["tts_pitch"], fallback: 1),
            "tts_volume": double(configValues["tts_volume"], fallback: 1)
        ]
        do {
            let data = try await api.requestData("/api/tts/test", method: "POST", body: body, timeout: 180)
            ttsTestMessage = "OK: \(engine) tra ve audio \(max(1, data.count / 1024)) KB"
        } catch {
            ttsTestMessage = "TTS/CapCut fail: \(error.localizedDescription)"
        }
    }

    func testWarpProxy() async {
        let proxy = (configValues["douyin_warp_proxy"]?.isEmpty == false ? configValues["douyin_warp_proxy"]! : "socks5://127.0.0.1:40000")
        do {
            let result = try await api.request("/api/warp/test", method: "POST", body: ["proxy": proxy])
            if bool(result["ok"]) {
                warpTestMessage = "OK: IP \(string(result["ip"], fallback: "?")) | \(string(result["latency_ms"], fallback: "?"))ms"
            } else {
                warpTestMessage = "Fail: \(string(result["error"], fallback: "Khong ket noi duoc WARP"))"
            }
        } catch {
            warpTestMessage = "WARP fail: \(error.localizedDescription)"
        }
    }

    func login(register: Bool = false) async {
        guard !authUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !authPassword.isEmpty else {
            authMessage = "Nhap username/password"
            return
        }
        do {
            let result = try await api.request(
                register ? "/api/auth/register" : "/api/auth/login",
                method: "POST",
                body: ["username": authUsername, "password": authPassword]
            )
            if bool(result["ok"]) {
                authToken = string(result["token"])
                authMessage = "Da dang nhap: \(string(result["username"], fallback: authUsername))"
                await loadWatchProgress()
            } else {
                authMessage = string(result["error"], fallback: "Dang nhap that bai")
            }
        } catch {
            authMessage = "Auth error: \(error.localizedDescription)"
        }
    }

    func logout() {
        authToken = ""
        watchProgress = [:]
        authMessage = "Da dang xuat"
    }

    func loadWatchProgress() async {
        guard !authToken.isEmpty else { return }
        do {
            let result = try await api.request("/api/user/progress", authToken: authToken)
            let raw = (result["progress"] as? [String: Any]) ?? [:]
            var parsed: [String: WatchProgress] = [:]
            for (folder, value) in raw {
                let item = value as? [String: Any] ?? [:]
                parsed[folder] = WatchProgress(
                    episodeIndex: int(item["ep_index"]),
                    time: double(item["time"])
                )
            }
            watchProgress = parsed
        } catch {
            authMessage = "Load progress loi: \(error.localizedDescription)"
        }
    }

    func saveWatchProgress(folder: String, episodeIndex: Int, time: Double) async {
        guard !authToken.isEmpty, !folder.isEmpty else { return }
        do {
            _ = try await api.request(
                "/api/user/progress",
                method: "POST",
                body: ["folder": folder, "ep_index": episodeIndex, "time": time],
                authToken: authToken
            )
            watchProgress[folder] = WatchProgress(episodeIndex: episodeIndex, time: time)
        } catch {
            authMessage = "Save progress loi: \(error.localizedDescription)"
        }
    }

    func loadGlossary(folder: String? = nil) async {
        let targetFolder = folder ?? selectedGlossaryFolder
        guard !targetFolder.isEmpty else {
            glossaryMessage = "Chon series truoc"
            return
        }
        selectedGlossaryFolder = targetFolder
        do {
            let encoded = targetFolder.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? targetFolder
            let result = try await api.request("/api/series/\(encoded)/glossary")
            let raw = (result["glossary"] as? [String: Any]) ?? [:]
            glossaryRows = raw.keys.sorted().map { key in
                GlossaryEntry(source: key, target: string(raw[key]))
            }
            glossaryMessage = "Da load \(glossaryRows.count) tu"
        } catch {
            glossaryMessage = "Load tu dien loi: \(error.localizedDescription)"
        }
    }

    func saveGlossary() async {
        guard !selectedGlossaryFolder.isEmpty else {
            glossaryMessage = "Chon series truoc"
            return
        }
        var payload: [String: String] = [:]
        for row in glossaryRows {
            let source = row.source.trimmingCharacters(in: .whitespacesAndNewlines)
            let target = row.target.trimmingCharacters(in: .whitespacesAndNewlines)
            if !source.isEmpty && !target.isEmpty { payload[source] = target }
        }
        do {
            let encoded = selectedGlossaryFolder.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? selectedGlossaryFolder
            let result = try await api.request("/api/series/\(encoded)/glossary", method: "POST", body: ["glossary": payload])
            glossaryMessage = "Da luu \(int(result["saved_items"], fallback: payload.count)) tu"
            await loadGlossary()
        } catch {
            glossaryMessage = "Save tu dien loi: \(error.localizedDescription)"
        }
    }

    func addGlossaryInput() {
        let source = glossarySourceInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = glossaryTargetInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty, !target.isEmpty else {
            glossaryMessage = "Nhap tu goc va ban dich"
            return
        }
        if let index = glossaryRows.firstIndex(where: { $0.source.caseInsensitiveCompare(source) == .orderedSame }) {
            glossaryRows[index].target = target
        } else {
            glossaryRows.append(GlossaryEntry(source: source, target: target))
            glossaryRows.sort { $0.source < $1.source }
        }
        glossarySourceInput = ""
        glossaryTargetInput = ""
        glossaryMessage = "Da them/cap nhat, bam Save de ghi backend"
    }

    func deleteGlossary(_ entry: GlossaryEntry) {
        glossaryRows.removeAll { $0.id == entry.id }
        glossaryMessage = "Da xoa local, bam Save de ghi backend"
    }

    func extractGlossaryAI() async {
        guard !selectedGlossaryFolder.isEmpty else {
            glossaryMessage = "Chon series truoc"
            return
        }
        do {
            let encoded = selectedGlossaryFolder.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? selectedGlossaryFolder
            let result = try await api.request("/api/series/\(encoded)/glossary/extract", method: "POST", body: [:])
            let items = (result["extracted"] as? [[String: Any]]) ?? []
            for item in items {
                let source = string(item["orig"], fallback: string(item["source"]))
                let target = string(item["trans"], fallback: string(item["target"]))
                if !source.isEmpty && !target.isEmpty {
                    if let index = glossaryRows.firstIndex(where: { $0.source.caseInsensitiveCompare(source) == .orderedSame }) {
                        glossaryRows[index].target = target
                    } else {
                        glossaryRows.append(GlossaryEntry(source: source, target: target))
                    }
                }
            }
            glossaryRows.sort { $0.source < $1.source }
            glossaryMessage = "AI trich xuat \(items.count) tu, bam Save de ghi backend"
        } catch {
            glossaryMessage = "AI glossary loi: \(error.localizedDescription)"
        }
    }

    func toggleScrapeSelection(_ video: ScrapeVideo) {
        if selectedScrapeURLs.contains(video.url) {
            selectedScrapeURLs.remove(video.url)
        } else if !video.url.isEmpty {
            selectedScrapeURLs.insert(video.url)
        }
    }

    func setScrapeSelection(all: Bool, newOnly: Bool = false) {
        selectedScrapeURLs = all
            ? Set(scrapeVideos.filter { !newOnly || !$0.done }.map(\.url).filter { !$0.isEmpty })
            : []
    }

    func addSelectedScrapedToPipeline(newOnly: Bool) {
        let urls = scrapeVideos
            .filter { selectedScrapeURLs.contains($0.url) && (!newOnly || !$0.done) }
            .map(\.url)
            .filter { !$0.isEmpty }
        guard !urls.isEmpty else {
            aiGroupMessage = "Chua chon video hop le"
            return
        }
        appendURLsToPipeline(urls)
        selectedTab = .pipeline
        aiGroupMessage = "Da them \(urls.count) URL vao Pipeline"
    }

    func translateScrapeCaptions() async {
        let captions = scrapeVideos.map(\.caption)
        guard !captions.isEmpty else {
            aiGroupMessage = "Chua co caption de dich"
            return
        }
        aiGroupMessage = "Dang dich caption bang 9Router..."
        do {
            let result = try await api.request(
                "/api/douyin/translate-captions",
                method: "POST",
                body: ["captions": captions],
                timeout: 300
            )
            let translations = (result["translations"] as? [String]) ?? []
            for index in scrapeVideos.indices {
                if let translated = translations[safe: index] {
                    scrapeVideos[index].translation = translated
                }
            }
            aiGroupMessage = "Da dich \(translations.count) caption"
        } catch {
            aiGroupMessage = "Dich caption loi: \(error.localizedDescription)"
        }
    }

    func groupScrapeSeriesAI(loadSaved: Bool = false) async {
        aiGroupMessage = loadSaved ? "Dang load AI group da luu..." : "Dang AI group series bang 9Router..."
        do {
            let result: [String: Any]
            if loadSaved {
                result = try await api.request("/api/douyin/load-group")
            } else {
                guard !scrapeVideos.isEmpty else {
                    aiGroupMessage = "Chua co video scrape de group"
                    return
                }
                result = try await api.request(
                    "/api/douyin/group-series",
                    method: "POST",
                    body: ["videos": scrapeVideos.map(scrapeVideoPayload)],
                    timeout: 600
                )
            }
            aiSeriesGroups = parseAISeriesGroups(result)
            selectedAIGroupIDs = Set(aiSeriesGroups.filter { !$0.urls.isEmpty }.map(\.id))
            aiGroupMessage = "AI group: \(aiSeriesGroups.count) series | standalone \(int(result["standalone_count"]))"
            await loadCompletedScrapeURLs()
        } catch {
            aiGroupMessage = "AI group loi: \(error.localizedDescription)"
        }
    }

    func loadCompletedScrapeURLs() async {
        do {
            let result = try await api.request("/api/projects/completed-urls")
            completedScrapeURLs = Set((result["completed"] as? [String]) ?? [])
        } catch {
            completedScrapeURLs = []
        }
    }

    func toggleAIGroup(_ group: AISeriesGroup) {
        if selectedAIGroupIDs.contains(group.id) {
            selectedAIGroupIDs.remove(group.id)
        } else {
            selectedAIGroupIDs.insert(group.id)
        }
    }

    func setAIGroupSelection(all: Bool) {
        selectedAIGroupIDs = all ? Set(aiSeriesGroups.map(\.id)) : []
    }

    func addSelectedAIGroupToPipeline(newOnly: Bool) {
        let prepared = preparedSelectedAIGroupURLs(newOnly: newOnly)
        guard !prepared.urls.isEmpty else {
            aiGroupMessage = "Khong co URL moi trong group da chon"
            return
        }
        appendURLsToPipeline(prepared.urls, contexts: prepared.contexts)
        selectedTab = .pipeline
        aiGroupMessage = "Da them \(prepared.urls.count) URL series vao Pipeline"
    }

    func startSelectedAIGroupQueue(newOnly: Bool = true) async {
        let prepared = preparedSelectedAIGroupURLs(newOnly: newOnly)
        guard !prepared.urls.isEmpty else {
            aiGroupMessage = "Khong co URL de start queue"
            return
        }
        do {
            let result = try await api.request(
                "/api/pipeline/batch",
                method: "POST",
                body: [
                    "urls": prepared.urls.joined(separator: "\n"),
                    "contexts": prepared.contexts
                ]
            )
            activeQueueId = string(result["queue_id"])
            queue.id = activeQueueId
            pipelineStatus = "Queue running"
            pipelineMessage = "Started selected series queue: \(prepared.urls.count) URL"
            aiGroupMessage = pipelineMessage
            selectedTab = .running
            await refreshAll(silent: true)
        } catch {
            aiGroupMessage = "Start selected queue loi: \(error.localizedDescription)"
        }
    }

    func preparedSelectedAIGroupURLs(newOnly: Bool) -> (urls: [String], contexts: [String: [String: Any]]) {
        var urls: [String] = []
        var contexts: [String: [String: Any]] = [:]
        for group in aiSeriesGroups where selectedAIGroupIDs.contains(group.id) {
            let sourceURLs = group.uniqueURLs.isEmpty ? group.urls : group.uniqueURLs
            let filtered = sourceURLs.filter { url in
                !url.isEmpty && (!newOnly || !completedScrapeURLs.contains(url))
            }
            let groupContexts = buildSeriesContextMap(group: group, urls: filtered)
            for url in filtered where !urls.contains(url) {
                urls.append(url)
                if let context = groupContexts[url] {
                    contexts[url] = context
                }
            }
        }
        return (urls, contexts)
    }

    func appendURLsToPipeline(_ urls: [String], contexts: [String: [String: Any]] = [:]) {
        let clean = urls.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        for (url, context) in contexts {
            pipelineURLContexts[url] = context
        }
        let existing = urlInput
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var seen = Set<String>()
        let merged = (existing + clean).filter { seen.insert($0).inserted }
        urlInput = merged.joined(separator: "\n")
    }

    func loadDouyinWatchdogState() async {
        do {
            let result = try await api.request("/api/douyin/watchdog/state")
            let userURLs = (result["user_urls"] as? [String]) ?? []
            douyinWatchdog = DouyinWatchdogState(
                enabled: bool(result["enabled"]),
                userURLs: userURLs.isEmpty ? string(result["user_url"]) : userURLs.joined(separator: "\n"),
                intervalMin: string(result["interval_min"], fallback: "15"),
                minDurationSec: string(result["min_duration_sec"], fallback: "60"),
                running: bool(result["running"]),
                lastRun: string(result["last_run_at"], fallback: "N/A"),
                summary: string(result["last_summary"], fallback: "Watchdog loaded")
            )
        } catch {
            douyinWatchdog.summary = "Load watchdog loi: \(error.localizedDescription)"
        }
    }

    func saveDouyinWatchdog() async {
        let urls = douyinWatchdog.userURLs
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        do {
            _ = try await api.request(
                "/api/douyin/watchdog/config",
                method: "POST",
                body: [
                    "enabled": douyinWatchdog.enabled,
                    "user_urls": urls,
                    "user_url": urls.first ?? "",
                    "interval_min": int(douyinWatchdog.intervalMin, fallback: 15),
                    "min_duration_sec": double(douyinWatchdog.minDurationSec, fallback: 60)
                ]
            )
            await loadDouyinWatchdogState()
            aiGroupMessage = "Da luu Douyin watchdog"
        } catch {
            aiGroupMessage = "Save watchdog loi: \(error.localizedDescription)"
        }
    }

    func runDouyinWatchdogOnce() async {
        aiGroupMessage = "Dang chay Douyin watchdog..."
        do {
            let result = try await api.request("/api/douyin/watchdog/run-once", method: "POST", body: [:], timeout: 600)
            let output = (result["result"] as? [String: Any]) ?? [:]
            aiGroupMessage = "Watchdog done: new \(int(output["new_count"])) | queued \(int(output["queued"]))"
            await loadDouyinWatchdogState()
            await refreshRunning()
        } catch {
            aiGroupMessage = "Run watchdog loi: \(error.localizedDescription)"
            await loadDouyinWatchdogState()
        }
    }

    func runToolAction(title: String, path: String, method: String = "POST", body: [String: Any]? = nil) async {
        do {
            let result = try await api.request(path, method: method, body: body)
            toolMessage = string(result["message"], fallback: string(result["status"], fallback: string(result["ok"], fallback: "\(title) done")))
            NotificationCenterBridge.shared.notifyOnce(key: "tool-\(title)-\(Date().timeIntervalSince1970)", title: title, body: toolMessage)
            if path.contains("/api/gdrive/"), let jobId = result["job_id"] as? String {
                Task { await self.pollUploadJob(jobId: jobId, target: "drive") }
            }
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
        return projectMediaURL(projectName: project.folderName, file: file)
    }

    func projectMediaURL(projectName: String, file: String = "preview") -> URL? {
        guard !projectName.isEmpty else { return nil }
        let encodedProject = projectName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? projectName
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
        let watchFolder = videoWatchFolder(for: project)
        let episodeIndex = resolvedEpisodeIndex(project: project, watchFolder: watchFolder)
        selectedVideo = VideoSelection(
            title: project.displayName,
            subtitle: project.subtitle,
            folderName: project.folderName,
            url: url,
            previewURL: previewURL,
            finalURL: finalURL,
            watchFolder: watchFolder,
            episodeIndex: episodeIndex,
            resumeTime: watchProgress[watchFolder]?.time ?? 0
        )
        selectedVideoSeriesFolder = project.seriesFolder.isEmpty ? project.series : project.seriesFolder
        selectedTab = .videos
    }

    func playEpisode(_ episode: SeriesEpisode, in series: SeriesRow, index: Int) {
        guard episode.rendered else {
            statusMessage = "Tap nay chua render xong"
            return
        }
        let pseudoProject = ProjectRow(
            folderName: episode.projectName,
            displayName: episode.title,
            subtitle: episode.projectName,
            created: episode.created,
            series: series.folder,
            seriesFolder: series.folder,
            episodeNo: episode.episodeNo,
            progress: 100,
            steps: ["render"],
            rendered: true,
            youtube: false,
            tiktok: false,
            facebook: false
        )
        guard
            let previewURL = projectMediaURL(pseudoProject, file: "preview"),
            let finalURL = projectMediaURL(pseudoProject, file: "final_video.mp4")
        else {
            statusMessage = "Khong tao duoc URL video"
            return
        }
        let progress = watchProgress[series.folder]
        selectedVideo = VideoSelection(
            title: episode.title,
            subtitle: "\(series.name) - Tap \(episode.episodeNo)",
            folderName: episode.projectName,
            url: previewURL,
            previewURL: previewURL,
            finalURL: finalURL,
            watchFolder: series.folder,
            episodeIndex: index,
            resumeTime: progress?.episodeIndex == index ? progress?.time ?? 0 : 0
        )
        selectedVideoSeriesFolder = series.folder
        selectedTab = .videos
    }

    func selectSeriesForWatching(_ series: SeriesRow) {
        selectedVideoSeriesFolder = series.folder
        let renderedEpisodes = renderedEpisodes(in: series)
        let saved = watchProgress[series.folder]
        let index = min(max(saved?.episodeIndex ?? 0, 0), max(renderedEpisodes.count - 1, 0))
        if let episode = renderedEpisodes[safe: index] {
            playEpisode(episode, in: series, index: index)
        }
    }

    func renderedEpisodes(in series: SeriesRow) -> [SeriesEpisode] {
        series.episodes
            .filter(\.rendered)
            .sorted { lhs, rhs in
                if lhs.episodeNo == rhs.episodeNo { return lhs.created < rhs.created }
                return lhs.episodeNo < rhs.episodeNo
            }
    }

    func filteredEpisodes(in series: SeriesRow) -> [SeriesEpisode] {
        let episodes = renderedEpisodes(in: series)
        let query = videoEpisodeSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return episodes }
        return episodes.filter { episode in
            String(episode.episodeNo).contains(query)
                || episode.title.lowercased().contains(query)
                || episode.projectName.lowercased().contains(query)
        }
    }

    func selectedVideoSeries() -> SeriesRow? {
        let rows = effectiveSeriesRows
        if let selected = rows.first(where: { $0.folder == selectedVideoSeriesFolder }) {
            return selected
        }
        return rows.first
    }

    func canPlayNext(after selection: VideoSelection) -> Bool {
        nextSelection(after: selection) != nil
    }

    func playNextVideo(after selection: VideoSelection? = nil) {
        guard let next = nextSelection(after: selection ?? selectedVideo) else {
            statusMessage = "Het tap de xem"
            return
        }
        selectedVideo = next
        selectedVideoSeriesFolder = next.watchFolder
    }

    func nextSelection(after selection: VideoSelection?) -> VideoSelection? {
        guard let selection = selection else { return nil }
        if let series = effectiveSeriesRows.first(where: { $0.folder == selection.watchFolder }) {
            let episodes = renderedEpisodes(in: series)
            let nextIndex = selection.episodeIndex + 1
            guard let nextEpisode = episodes[safe: nextIndex] else { return nil }
            return makeVideoSelection(episode: nextEpisode, series: series, index: nextIndex, resume: false)
        }
        let standalone = standaloneProjects
        guard let current = standalone.firstIndex(where: { $0.folderName == selection.folderName }),
              let nextProject = standalone[safe: current + 1] else {
            return nil
        }
        return makeVideoSelection(project: nextProject, resume: false)
    }

    func makeVideoSelection(project: ProjectRow, file: String = "preview", resume: Bool = true) -> VideoSelection? {
        guard
            let previewURL = projectMediaURL(project, file: "preview"),
            let finalURL = projectMediaURL(project, file: "final_video.mp4"),
            let url = projectMediaURL(project, file: file)
        else { return nil }
        let folder = videoWatchFolder(for: project)
        let episodeIndex = resolvedEpisodeIndex(project: project, watchFolder: folder)
        return VideoSelection(
            title: project.displayName,
            subtitle: project.subtitle,
            folderName: project.folderName,
            url: url,
            previewURL: previewURL,
            finalURL: finalURL,
            watchFolder: folder,
            episodeIndex: episodeIndex,
            resumeTime: resume ? watchProgress[folder]?.time ?? 0 : 0
        )
    }

    func makeVideoSelection(episode: SeriesEpisode, series: SeriesRow, index: Int, resume: Bool = true) -> VideoSelection? {
        let pseudoProject = ProjectRow(
            folderName: episode.projectName,
            displayName: episode.title,
            subtitle: episode.projectName,
            created: episode.created,
            series: series.name,
            seriesFolder: series.folder,
            episodeNo: episode.episodeNo,
            progress: 100,
            steps: ["render"],
            rendered: true,
            youtube: false,
            tiktok: false,
            facebook: false
        )
        guard
            let previewURL = projectMediaURL(pseudoProject, file: "preview"),
            let finalURL = projectMediaURL(pseudoProject, file: "final_video.mp4")
        else { return nil }
        let progress = watchProgress[series.folder]
        return VideoSelection(
            title: episode.title,
            subtitle: "\(series.name) - Tap \(episode.episodeNo)",
            folderName: episode.projectName,
            url: previewURL,
            previewURL: previewURL,
            finalURL: finalURL,
            watchFolder: series.folder,
            episodeIndex: index,
            resumeTime: resume && progress?.episodeIndex == index ? progress?.time ?? 0 : 0
        )
    }

    func videoWatchFolder(for project: ProjectRow) -> String {
        if !project.seriesFolder.isEmpty { return project.seriesFolder }
        if !project.series.isEmpty { return project.series }
        return project.folderName
    }

    func resolvedEpisodeIndex(project: ProjectRow, watchFolder: String) -> Int {
        guard let series = effectiveSeriesRows.first(where: { $0.folder == watchFolder }) else {
            return max(0, (project.episodeNo ?? 1) - 1)
        }
        return renderedEpisodes(in: series).firstIndex(where: { $0.projectName == project.folderName })
            ?? max(0, (project.episodeNo ?? 1) - 1)
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
                    DictionaryView().tag(MainTab.dictionary)
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

            ScrapeAIToolsView()
                .environmentObject(model)

            DouyinWatchdogCard()
                .environmentObject(model)

            if !model.scrapeLogLines.isEmpty {
                SectionCard(title: "Scrape logs", symbol: "terminal") {
                    LogConsole(lines: model.scrapeLogLines, maxHeight: 220)
                }
            }

            if !model.scrapeVideos.isEmpty {
                SectionCard(title: "Ket qua scrape", symbol: "film.stack") {
                    HStack(spacing: 10) {
                        SmallButton(title: "Select All", symbol: "checkmark.square") {
                            model.setScrapeSelection(all: true)
                        }
                        SmallButton(title: "New Only", symbol: "sparkles") {
                            model.setScrapeSelection(all: true, newOnly: true)
                        }
                        SmallButton(title: "Clear", symbol: "square") {
                            model.setScrapeSelection(all: false)
                        }
                    }
                    PrimaryAction(title: "Add selected/new vao Pipeline", symbol: "plus.circle.fill") {
                        model.addSelectedScrapedToPipeline(newOnly: true)
                    }
                    ForEach(model.scrapeVideos) { video in
                        ScrapeVideoSelectableCard(video: video)
                            .environmentObject(model)
                    }
                }
            }
        }
    }
}

struct ScrapeAIToolsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        SectionCard(title: "AI group series", symbol: "sparkles.tv.fill") {
            Text("Group video scrape thanh series bang 9Router, giu context series_folder/episode_no khi start queue.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                SmallButton(title: "Translate Captions", symbol: "captions.bubble.fill") {
                    Task { await model.translateScrapeCaptions() }
                }
                SmallButton(title: "AI Group", symbol: "sparkles") {
                    Task { await model.groupScrapeSeriesAI() }
                }
                SmallButton(title: "Load Saved", symbol: "tray.and.arrow.down.fill") {
                    Task { await model.groupScrapeSeriesAI(loadSaved: true) }
                }
                SmallButton(title: "Refresh Done", symbol: "checkmark.seal.fill") {
                    Task { await model.loadCompletedScrapeURLs() }
                }
            }

            HStack(spacing: 10) {
                SmallButton(title: "Select All", symbol: "checkmark.square") {
                    model.setAIGroupSelection(all: true)
                }
                SmallButton(title: "Clear", symbol: "square") {
                    model.setAIGroupSelection(all: false)
                }
            }

            HStack(spacing: 10) {
                PrimaryAction(title: "Add New", symbol: "plus.circle.fill") {
                    model.addSelectedAIGroupToPipeline(newOnly: true)
                }
                PrimaryAction(title: "Start Queue", symbol: "play.fill") {
                    Task { await model.startSelectedAIGroupQueue(newOnly: true) }
                }
            }

            Text(model.aiGroupMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(4)

            if model.aiSeriesGroups.isEmpty {
                EmptyState(text: "Chua co AI group. Bam AI Group sau khi scrape, hoac Load Saved.")
            } else {
                ForEach(model.aiSeriesGroups) { group in
                    AISeriesGroupCard(group: group)
                        .environmentObject(model)
                }
            }
        }
    }
}

struct DouyinWatchdogCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        SectionCard(title: "Douyin User Watchdog", symbol: "dog.fill") {
            Text("Tu scan user theo chu ky, neu co video moi thi backend group series va add vao queue.")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextEditor(text: $model.douyinWatchdog.userURLs)
                .frame(minHeight: 82)
                .padding(10)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(alignment: .topLeading) {
                    if model.douyinWatchdog.userURLs.isEmpty {
                        Text("User URLs, moi dong mot link...")
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 18)
                    }
                }

            HStack {
                TextField("Interval min", text: $model.douyinWatchdog.intervalMin)
                    .keyboardType(.numberPad)
                    .inputShell()
                TextField("Min sec", text: $model.douyinWatchdog.minDurationSec)
                    .keyboardType(.numberPad)
                    .inputShell()
            }

            Toggle("Enable Watchdog", isOn: $model.douyinWatchdog.enabled)
                .toggleStyle(.switch)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                SmallButton(title: "Load", symbol: "arrow.clockwise") {
                    Task { await model.loadDouyinWatchdogState() }
                }
                SmallButton(title: "Save", symbol: "square.and.arrow.down.fill") {
                    Task { await model.saveDouyinWatchdog() }
                }
                SmallButton(title: "Run Once", symbol: "play.circle.fill") {
                    Task { await model.runDouyinWatchdogOnce() }
                }
                StatusPill(text: model.douyinWatchdog.running ? "Running" : "Idle", tone: model.douyinWatchdog.running ? .orange : .green)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            Text("Last: \(model.douyinWatchdog.lastRun) | \(model.douyinWatchdog.summary)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(4)
        }
        .task { await model.loadDouyinWatchdogState() }
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
            SectionCard(title: "Tai khoan xem phim", symbol: "person.crop.circle.fill") {
                if model.authToken.isEmpty {
                    TextField("Username", text: $model.authUsername)
                        .textInputAutocapitalization(.never)
                        .inputShell()
                    SecureField("Password", text: $model.authPassword)
                        .inputShell()
                    HStack(spacing: 10) {
                        SmallButton(title: "Dang nhap", symbol: "person.fill.checkmark") {
                            Task { await model.login() }
                        }
                        SmallButton(title: "Dang ky", symbol: "person.badge.plus") {
                            Task { await model.login(register: true) }
                        }
                    }
                } else {
                    HStack {
                        StatusPill(text: "Logged in", tone: .green)
                        Spacer()
                        SmallButton(title: "Logout", symbol: "rectangle.portrait.and.arrow.right") {
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

            VideoNowPlayingSection()
                .environmentObject(model)

            VideoLibrarySection()
                .environmentObject(model)
        }
        .task {
            if !model.authToken.isEmpty {
                await model.loadWatchProgress()
            }
            if model.selectedVideo == nil, let series = model.effectiveSeriesRows.first {
                model.selectSeriesForWatching(series)
            }
        }
    }
}

struct VideoNowPlayingSection: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        SectionCard(title: "Dang xem", symbol: "play.tv.fill") {
            if let selection = model.selectedVideo {
                InlineVideoPlayer(selection: selection)
                    .environmentObject(model)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "play.rectangle.on.rectangle.fill")
                        .font(.system(size: 44, weight: .black))
                        .foregroundStyle(.secondary)
                    Text("Chon series hoac phim le ben duoi de xem.")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            }
        }
    }
}

struct VideoLibrarySection: View {
    @EnvironmentObject private var model: AppModel
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        SectionCard(title: "Thu vien video", symbol: "play.square.stack.fill") {
            HStack {
                Text("\(model.effectiveSeriesRows.count) series | \(model.standaloneProjects.count) phim le")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                SmallButton(title: "Refresh", symbol: "arrow.clockwise") {
                    Task {
                        await model.refreshSeries()
                        await model.refreshProjects()
                        await model.loadWatchProgress()
                    }
                }
                .frame(width: 116)
            }

            Picker("Loai", selection: $model.videoLibraryMode) {
                Text("Phim series").tag("series")
                Text("Standalone").tag("standalone")
            }
            .pickerStyle(.segmented)

            if model.videoLibraryMode == "series" {
                SeriesWatchLibrary()
                    .environmentObject(model)
            } else {
                TextField("Tim phim le...", text: $model.videoEpisodeSearch)
                    .textInputAutocapitalization(.never)
                    .inputShell()
                let projects = filteredStandalone
                if projects.isEmpty {
                    EmptyState(text: "Chua co phim le render.")
                }
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(projects) { project in
                        StandalonePosterCard(project: project)
                    }
                }
            }
        }
    }

    private var filteredStandalone: [ProjectRow] {
        let query = model.videoEpisodeSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return model.standaloneProjects }
        return model.standaloneProjects.filter {
            $0.displayName.lowercased().contains(query)
                || $0.folderName.lowercased().contains(query)
        }
    }
}

struct SeriesWatchLibrary: View {
    @EnvironmentObject private var model: AppModel
    private let posterColumns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        if model.effectiveSeriesRows.isEmpty {
            EmptyState(text: "Chua co series nao render.")
        } else {
            LazyVGrid(columns: posterColumns, spacing: 12) {
                ForEach(model.effectiveSeriesRows) { series in
                    SeriesMiniPosterCard(
                        series: series,
                        selected: model.selectedVideoSeriesFolder == series.folder
                    ) {
                        model.selectSeriesForWatching(series)
                    }
                    .environmentObject(model)
                }
            }

            if let series = model.selectedVideoSeries() {
                EpisodeListPanel(series: series)
                    .environmentObject(model)
            }
        }
    }
}

struct SeriesMiniPosterCard: View {
    var series: SeriesRow
    var selected: Bool
    var action: () -> Void
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .bottomLeading) {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(LinearGradient(colors: [.pink.opacity(0.36), .black.opacity(0.82)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    if let first = model.renderedEpisodes(in: series).first,
                       let url = model.projectMediaURL(projectName: first.projectName, file: "thumbnail.jpg") {
                        AsyncImage(url: url) { phase in
                            if let image = phase.image {
                                image.resizable().scaledToFill()
                            } else {
                                Color.clear
                            }
                        }
                    }
                    LinearGradient(colors: [.clear, .black.opacity(0.82)], startPoint: .top, endPoint: .bottom)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(series.name)
                            .font(.system(.caption, design: .rounded).weight(.black))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                        Text("\(series.rendered)/\(series.total) tap")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white.opacity(0.82))
                    }
                    .padding(10)
                }
                .frame(height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(selected ? Color.accentColor : Color.clear, lineWidth: 3))
            }
        }
        .buttonStyle(.plain)
    }
}

struct EpisodeListPanel: View {
    var series: SeriesRow
    @EnvironmentObject private var model: AppModel
    private let columns = Array(repeating: GridItem(.flexible()), count: 5)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(series.name)
                        .font(.system(.headline, design: .rounded).weight(.black))
                        .lineLimit(2)
                    Text(series.episodeRange)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                SmallButton(title: "Next", symbol: "forward.fill") {
                    model.playNextVideo()
                }
                .frame(width: 92)
            }

            TextField("Tim tap: 42, ten tap, project...", text: $model.videoEpisodeSearch)
                .textInputAutocapitalization(.never)
                .inputShell()

            let episodes = model.filteredEpisodes(in: series)
            if episodes.isEmpty {
                EmptyState(text: "Khong co tap khop tim kiem.")
            } else {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(Array(episodes.enumerated()), id: \.element.id) { _, episode in
                        let absoluteIndex = model.renderedEpisodes(in: series).firstIndex(where: { $0.projectName == episode.projectName }) ?? 0
                        Button {
                            model.playEpisode(episode, in: series, index: absoluteIndex)
                        } label: {
                            VStack(spacing: 2) {
                                Text("\(episode.episodeNo)")
                                    .font(.caption.weight(.black))
                                if model.watchProgress[series.folder]?.episodeIndex == absoluteIndex {
                                    Circle().fill(Color.white).frame(width: 4, height: 4)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(isCurrent(absoluteIndex) ? Color.accentColor : Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .foregroundStyle(isCurrent(absoluteIndex) ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func isCurrent(_ index: Int) -> Bool {
        model.selectedVideo?.watchFolder == series.folder && model.selectedVideo?.episodeIndex == index
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

struct DictionaryView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScreenScroll {
            SectionCard(title: "Tu dien dich", symbol: "book.closed.fill") {
                Picker("Series", selection: $model.selectedGlossaryFolder) {
                    Text("Chon series").tag("")
                    ForEach(model.seriesRows) { series in
                        Text(series.name).tag(series.folder)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .onChange(of: model.selectedGlossaryFolder) { folder in
                    Task { await model.loadGlossary(folder: folder) }
                }

                HStack(spacing: 10) {
                    SmallButton(title: "Reload", symbol: "arrow.clockwise") {
                        Task { await model.loadGlossary() }
                    }
                    SmallButton(title: "AI extract", symbol: "sparkles") {
                        Task { await model.extractGlossaryAI() }
                    }
                    SmallButton(title: "Save", symbol: "square.and.arrow.down.fill") {
                        Task { await model.saveGlossary() }
                    }
                }

                Text(model.glossaryMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            SectionCard(title: "Them / cap nhat tu", symbol: "plus.circle.fill") {
                TextField("Tu goc: Xiaosuke", text: $model.glossarySourceInput)
                    .textInputAutocapitalization(.never)
                    .inputShell()
                TextField("Ban dich: Tieu Tuc", text: $model.glossaryTargetInput)
                    .inputShell()
                PrimaryAction(title: "Them / cap nhat", symbol: "plus") {
                    model.addGlossaryInput()
                }
            }

            SectionCard(title: "Danh sach tu", symbol: "list.bullet") {
                if model.glossaryRows.isEmpty {
                    EmptyState(text: "Chua co tu nao trong series nay.")
                }
                ForEach($model.glossaryRows) { $entry in
                    GlossaryRowView(entry: $entry) {
                        model.deleteGlossary(entry)
                    }
                }
            }
        }
        .task {
            if model.seriesRows.isEmpty { await model.refreshSeries() }
        }
    }
}

struct GlossaryRowView: View {
    @Binding var entry: GlossaryEntry
    var onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Tu goc", text: $entry.source)
                .textInputAutocapitalization(.never)
                .inputShell()
            TextField("Ban dich", text: $entry.target)
                .inputShell()
            HStack {
                Text(String(entry.id.uuidString.prefix(8)))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: onDelete) {
                    Label("Xoa", systemImage: "trash")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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

            SectionCard(title: "Check API", symbol: "checkmark.seal.fill") {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    SmallButton(title: "Refresh status", symbol: "arrow.clockwise") {
                        Task {
                            await model.refreshHealth()
                            await model.refreshToolStatuses()
                            await model.refreshConfig()
                        }
                    }
                    SmallButton(title: "Test 9Router", symbol: "network") {
                        Task { await model.testTranslationAPI() }
                    }
                    SmallButton(title: "Test CapCut", symbol: "speaker.wave.2.fill") {
                        Task { await model.testTTSAPI() }
                    }
                    SmallButton(title: "Test WARP", symbol: "shield.lefthalf.filled") {
                        Task { await model.testWarpProxy() }
                    }
                }

                StatusText(title: "9Router/WebAI", value: model.translationTestMessage)
                StatusText(title: "TTS/CapCut", value: model.ttsTestMessage)
                StatusText(title: "WARP", value: model.warpTestMessage)

                if model.toolStatuses.isEmpty {
                    EmptyState(text: "Chua co status. Bam Refresh status.")
                }
                ForEach(model.toolStatuses) { row in
                    HStack {
                        Text(row.title).font(.caption.weight(.semibold))
                        Spacer()
                        StatusPill(text: row.value, tone: row.tone)
                    }
                    .padding(10)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }

            SectionCard(title: "Settings backend", symbol: "gearshape.2.fill") {
                HStack(spacing: 10) {
                    PrimaryAction(title: "Save Settings", symbol: "square.and.arrow.down.fill") {
                        Task { await model.saveConfig() }
                    }
                    PrimaryAction(title: "Reload", symbol: "arrow.clockwise") {
                        Task { await model.refreshConfig() }
                    }
                }
                Text(model.configMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)

                ForEach(appConfigGroups, id: \.self) { group in
                    ConfigGroupView(
                        title: group,
                        fields: appConfigFields.filter { $0.group == group }
                    )
                    .environmentObject(model)
                }
            }

            SectionCard(title: "Tat ca settings raw", symbol: "list.bullet.rectangle") {
                if model.configRows.isEmpty {
                    EmptyState(text: "Chua load /api/config")
                }
                ForEach(model.configRows) { row in
                    ConfigRawRow(row: row)
                }
            }

            SectionCard(title: "Ghi chu build", symbol: "shippingbox.fill") {
                Text("App native nay goi backend MBVietSub qua API. Render, Playwright scrape, ffmpeg va upload van chay tren PC/server. Khi app vao nen, iOS cho poll tiep trong mot khoang thoi gian de gui local notification; neu user kill app han thi can push notification/APNs tu backend moi bao dam van bao.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .task {
            if model.configValues.isEmpty {
                await model.refreshConfig()
                await model.refreshToolStatuses()
            }
        }
    }
}

struct StatusText: View {
    var title: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct ConfigGroupView: View {
    var title: String
    var fields: [ConfigField]
    @EnvironmentObject private var model: AppModel

    var body: some View {
        DisclosureGroup {
            VStack(spacing: 10) {
                ForEach(fields) { field in
                    ConfigInputRow(
                        field: field,
                        value: Binding(
                            get: { model.configValues[field.key] ?? "" },
                            set: { model.configValues[field.key] = $0 }
                        )
                    )
                }
            }
            .padding(.top, 10)
        } label: {
            HStack {
                Text(title)
                    .font(.system(.subheadline, design: .rounded).weight(.black))
                Spacer()
                Text("\(fields.count)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct ConfigInputRow: View {
    var field: ConfigField
    @Binding var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(field.label)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)

            switch field.kind {
            case .toggle:
                Toggle(isOn: Binding(get: { configBool(value) }, set: { value = $0 ? "true" : "false" })) {
                    Text(configBool(value) ? "On" : "Off")
                        .font(.subheadline.weight(.semibold))
                }
                .toggleStyle(.switch)
            case .number:
                TextField(field.placeholder.isEmpty ? field.key : field.placeholder, text: $value)
                    .keyboardType(.numbersAndPunctuation)
                    .inputShell()
            case .text:
                if field.sensitive {
                    SecureField(field.placeholder.isEmpty ? field.key : field.placeholder, text: $value)
                        .textInputAutocapitalization(.never)
                        .inputShell()
                } else {
                    TextField(field.placeholder.isEmpty ? field.key : field.placeholder, text: $value)
                        .textInputAutocapitalization(.never)
                        .keyboardType(field.key.contains("url") || field.key.contains("uri") ? .URL : .default)
                        .inputShell()
                }
            }

            Text(field.key)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct ConfigRawRow: View {
    var row: ConfigRow

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(row.key)
                .font(.caption.weight(.bold))
                .lineLimit(1)
                .truncationMode(.middle)
            Text(row.value.isEmpty ? "<empty>" : row.value)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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

struct SeriesPosterCard: View {
    var series: SeriesRow
    @EnvironmentObject private var model: AppModel

    var renderedEpisodes: [SeriesEpisode] {
        series.episodes.filter(\.rendered).sorted { $0.episodeNo < $1.episodeNo }
    }

    var body: some View {
        DisclosureGroup {
            EpisodeGridView(series: series, episodes: renderedEpisodes)
                .environmentObject(model)
                .padding(.top, 10)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                posterImage(projectName: renderedEpisodes.first?.projectName)
                    .overlay(alignment: .topLeading) {
                        Text("\(series.rendered)/\(series.total)")
                            .font(.caption.weight(.black))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Color.pink, in: Capsule())
                            .foregroundStyle(.white)
                            .padding(8)
                    }
                Text(series.name)
                    .font(.system(.subheadline, design: .rounded).weight(.black))
                    .lineLimit(2)
                if let progress = model.watchProgress[series.folder] {
                    Text("Dang xem tap \(progress.episodeIndex + 1) | \(formatWatchTime(progress.time))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func posterImage(projectName: String?) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(colors: [.pink.opacity(0.28), .black.opacity(0.82)], startPoint: .topLeading, endPoint: .bottomTrailing))
            if let projectName, let url = model.projectMediaURL(projectName: projectName, file: "thumbnail.jpg") {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        Image(systemName: "play.square.stack.fill")
                            .font(.system(size: 38, weight: .bold))
                            .foregroundStyle(.white.opacity(0.75))
                    }
                }
            }
        }
        .frame(height: 185)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct EpisodeGridView: View {
    var series: SeriesRow
    var episodes: [SeriesEpisode]
    @EnvironmentObject private var model: AppModel
    private let columns = Array(repeating: GridItem(.flexible()), count: 5)

    var body: some View {
        if episodes.isEmpty {
            EmptyState(text: "Series nay chua co tap render.")
        } else {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(Array(episodes.enumerated()), id: \.element.id) { index, episode in
                    Button {
                        model.playEpisode(episode, in: series, index: index)
                    } label: {
                        Text("\(episode.episodeNo)")
                            .font(.caption.weight(.black))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(isCurrent(index) ? Color.pink : Color.secondary.opacity(0.16), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .foregroundStyle(isCurrent(index) ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func isCurrent(_ index: Int) -> Bool {
        model.watchProgress[series.folder]?.episodeIndex == index
    }
}

struct StandalonePosterCard: View {
    var project: ProjectRow
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Button {
            model.playProject(project)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(LinearGradient(colors: [.blue.opacity(0.28), .black.opacity(0.82)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    if let url = model.projectMediaURL(project, file: "thumbnail.jpg") {
                        AsyncImage(url: url) { phase in
                            if let image = phase.image {
                                image.resizable().scaledToFill()
                            } else {
                                Image(systemName: "film.fill")
                                    .font(.system(size: 38, weight: .bold))
                                    .foregroundStyle(.white.opacity(0.75))
                            }
                        }
                    }
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 38, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(radius: 12)
                }
                .frame(height: 185)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                Text(project.displayName)
                    .font(.system(.subheadline, design: .rounded).weight(.black))
                    .lineLimit(2)
                if let progress = model.watchProgress[project.folderName] {
                    Text(formatWatchTime(progress.time))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(10)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
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

struct InlineVideoPlayer: View {
    var selection: VideoSelection
    @EnvironmentObject private var model: AppModel
    @State private var player = AVPlayer()
    @State private var currentURL: URL?
    @State private var endObserver: NSObjectProtocol?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VideoPlayer(player: player)
                .frame(height: 238)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(.white.opacity(0.16)))
                .shadow(color: .black.opacity(0.16), radius: 18, y: 10)

            VStack(alignment: .leading, spacing: 4) {
                Text(selection.title)
                    .font(.system(.headline, design: .rounded).weight(.black))
                    .lineLimit(2)
                Text(selection.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if selection.resumeTime > 2 {
                    Text("Resume: \(formatWatchTime(selection.resumeTime))")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                SmallButton(title: "Preview", symbol: "bolt.fill") {
                    switchTo(selection.previewURL)
                }
                SmallButton(title: "Full", symbol: "film.fill") {
                    switchTo(selection.finalURL)
                }
                SmallButton(title: "Next", symbol: "forward.fill") {
                    Task {
                        await saveCurrentProgress()
                        model.playNextVideo(after: selection)
                    }
                }
                .opacity(model.canPlayNext(after: selection) ? 1 : 0.42)
                SmallButton(title: "Open", symbol: "safari.fill") {
                    UIApplication.shared.open(currentURL ?? selection.url, options: [:], completionHandler: nil)
                }
            }

            Text("Player nam cung trang voi danh sach tap. Het tap se tu chuyen tap tiep theo neu con video rendered.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear { configurePlayer(for: selection, autoplay: true) }
        .onChange(of: selection.id) { _ in
            Task { await saveCurrentProgress() }
            configurePlayer(for: selection, autoplay: true)
        }
        .onDisappear {
            Task { await saveCurrentProgress() }
            removeEndObserver()
            player.pause()
        }
    }

    private func configurePlayer(for selection: VideoSelection, autoplay: Bool) {
        removeEndObserver()
        currentURL = selection.url
        let item = AVPlayerItem(url: selection.url)
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
                model.playNextVideo(after: selection)
            }
        }
        if autoplay { player.play() }
    }

    private func switchTo(_ url: URL) {
        currentURL = url
        removeEndObserver()
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { _ in
            Task {
                await saveCurrentProgress()
                model.playNextVideo(after: selection)
            }
        }
        player.play()
    }

    private func saveCurrentProgress() async {
        let seconds = player.currentTime().seconds
        guard seconds.isFinite else { return }
        await model.saveWatchProgress(folder: selection.watchFolder, episodeIndex: selection.episodeIndex, time: seconds)
    }

    private func removeEndObserver() {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
    }
}

struct VideoPlayerSheet: View {
    var selection: VideoSelection
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: AppModel
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
        .onAppear {
            if selection.resumeTime > 2 {
                player.seek(to: CMTime(seconds: selection.resumeTime, preferredTimescale: 600))
            }
            player.play()
        }
        .onDisappear {
            let seconds = player.currentTime().seconds
            player.pause()
            if seconds.isFinite {
                Task {
                    await model.saveWatchProgress(folder: selection.watchFolder, episodeIndex: selection.episodeIndex, time: seconds)
                }
            }
        }
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

struct AISeriesGroupCard: View {
    var group: AISeriesGroup
    @EnvironmentObject private var model: AppModel

    var isSelected: Bool {
        model.selectedAIGroupIDs.contains(group.id)
    }

    var newCount: Int {
        group.urls.filter { !model.completedScrapeURLs.contains($0) }.count
    }

    var body: some View {
        Button {
            model.toggleAIGroup(group)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(group.name)
                            .font(.system(.subheadline, design: .rounded).weight(.black))
                            .lineLimit(2)
                        Text(group.folder.isEmpty ? "Folder chua co" : group.folder)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    StatusPill(text: "\(newCount) new", tone: newCount > 0 ? .green : .gray)
                }

                HStack {
                    StatusPill(text: "\(group.urls.count) urls", tone: .blue)
                    StatusPill(text: "conf \(Int(group.confidence * 100))%", tone: group.confidence > 0.65 ? .green : .orange)
                    if let min = group.episodeMin, let max = group.episodeMax {
                        StatusPill(text: "Tap \(min)-\(max)", tone: .indigo)
                    }
                }

                if !group.reason.isEmpty {
                    Text(group.reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }

                ForEach(group.urls.prefix(3), id: \.self) { url in
                    HStack(spacing: 6) {
                        Image(systemName: model.completedScrapeURLs.contains(url) ? "checkmark.circle.fill" : "circle")
                            .font(.caption2)
                            .foregroundStyle(model.completedScrapeURLs.contains(url) ? .green : .secondary)
                        Text(url)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
            .padding(12)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(isSelected ? Color.accentColor.opacity(0.7) : Color.clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }
}

struct ScrapeVideoSelectableCard: View {
    var video: ScrapeVideo
    @EnvironmentObject private var model: AppModel

    var selected: Bool {
        model.selectedScrapeURLs.contains(video.url)
    }

    var body: some View {
        Button {
            model.toggleScrapeSelection(video)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: selected ? "checkmark.square.fill" : "square")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
                    .padding(.top, 2)
                ScrapeVideoCard(video: video)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
            if !video.translation.isEmpty {
                Text(video.translation)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .lineLimit(3)
            }
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

func formatWatchTime(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds > 0 else { return "00:00" }
    let total = Int(seconds)
    let minutes = total / 60
    let secs = total % 60
    return String(format: "%02d:%02d", minutes, secs)
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

let appConfigFields: [ConfigField] = [
    ConfigField(key: "channel_name", label: "Channel Name", group: "General", kind: .text),
    ConfigField(key: "api_key", label: "Gemini/API Key", group: "General", kind: .text, sensitive: true, placeholder: "De trong de giu key da luu"),
    ConfigField(key: "gemini_model", label: "Gemini Model", group: "General", kind: .text),
    ConfigField(key: "auth_user", label: "Auth User", group: "General", kind: .text),
    ConfigField(key: "auth_password", label: "Auth Password", group: "General", kind: .text, sensitive: true, placeholder: "De trong de giu password da luu"),
    ConfigField(key: "youtube_title_mode", label: "YouTube Title Mode", group: "General", kind: .text),
    ConfigField(key: "youtube_upload_strategy", label: "YouTube Upload Strategy", group: "General", kind: .text),
    ConfigField(key: "whisper_model", label: "Whisper Model", group: "General", kind: .text),
    ConfigField(key: "source_lang", label: "Source Language", group: "General", kind: .text),
    ConfigField(key: "target_lang", label: "Target Language", group: "General", kind: .text),
    ConfigField(key: "translation_style", label: "Translation Style", group: "General", kind: .text),
    ConfigField(key: "privacy", label: "Privacy", group: "General", kind: .text),
    ConfigField(key: "projects_dir", label: "Projects Dir", group: "General", kind: .text),

    ConfigField(key: "translation_provider", label: "Translation Provider", group: "Translation / 9Router", kind: .text),
    ConfigField(key: "translation_provider_order", label: "Provider Order", group: "Translation / 9Router", kind: .text),
    ConfigField(key: "ninerouter_url", label: "9Router URL", group: "Translation / 9Router", kind: .text),
    ConfigField(key: "ninerouter_key", label: "9Router API Key", group: "Translation / 9Router", kind: .text, sensitive: true, placeholder: "De trong de giu key da luu"),
    ConfigField(key: "ninerouter_model", label: "9Router Model", group: "Translation / 9Router", kind: .text),
    ConfigField(key: "ninerouter_timeout", label: "9Router Timeout", group: "Translation / 9Router", kind: .number),
    ConfigField(key: "webai_url", label: "WebAI URL", group: "Translation / 9Router", kind: .text),
    ConfigField(key: "webai_model", label: "WebAI Model", group: "Translation / 9Router", kind: .text),
    ConfigField(key: "enable_webai_fallback", label: "Enable WebAI Fallback", group: "Translation / 9Router", kind: .toggle),

    ConfigField(key: "tts_engine", label: "TTS Engine", group: "TTS / CapCut", kind: .text),
    ConfigField(key: "vieneu_voice", label: "VieNeu Voice", group: "TTS / CapCut", kind: .text),
    ConfigField(key: "vieneu_mode", label: "VieNeu Mode", group: "TTS / CapCut", kind: .text),
    ConfigField(key: "vieneu_ref_voice", label: "VieNeu Ref Voice", group: "TTS / CapCut", kind: .text),
    ConfigField(key: "capcut_voice", label: "CapCut Voice ID", group: "TTS / CapCut", kind: .text),
    ConfigField(key: "capcut_tts_workers", label: "CapCut Workers", group: "TTS / CapCut", kind: .number),
    ConfigField(key: "tts_speed", label: "TTS Speed", group: "TTS / CapCut", kind: .number),
    ConfigField(key: "tts_pitch", label: "TTS Pitch", group: "TTS / CapCut", kind: .number),
    ConfigField(key: "tts_volume", label: "TTS Volume", group: "TTS / CapCut", kind: .number),
    ConfigField(key: "auto_adjust_tts_speed", label: "Auto Adjust TTS Speed", group: "TTS / CapCut", kind: .toggle),

    ConfigField(key: "tiktok_upload_provider", label: "TikTok Provider", group: "TikTok / Facebook", kind: .text),
    ConfigField(key: "tiktok_api_client_key", label: "TikTok Client Key", group: "TikTok / Facebook", kind: .text, sensitive: true, placeholder: "De trong de giu key da luu"),
    ConfigField(key: "tiktok_api_client_secret", label: "TikTok Client Secret", group: "TikTok / Facebook", kind: .text, sensitive: true, placeholder: "De trong de giu secret da luu"),
    ConfigField(key: "tiktok_api_redirect_uri", label: "TikTok Redirect URI", group: "TikTok / Facebook", kind: .text),
    ConfigField(key: "tiktok_api_scopes", label: "TikTok Scopes", group: "TikTok / Facebook", kind: .text),
    ConfigField(key: "tiktok_api_pkce_challenge_format", label: "TikTok PKCE Mode", group: "TikTok / Facebook", kind: .text),
    ConfigField(key: "tiktok_api_privacy_level", label: "TikTok Privacy", group: "TikTok / Facebook", kind: .text),
    ConfigField(key: "tiktok_api_poll_timeout_sec", label: "TikTok Poll Timeout", group: "TikTok / Facebook", kind: .number),
    ConfigField(key: "tiktok_api_poll_interval_sec", label: "TikTok Poll Interval", group: "TikTok / Facebook", kind: .number),
    ConfigField(key: "tiktok_max_minutes", label: "TikTok Max Minutes", group: "TikTok / Facebook", kind: .number),
    ConfigField(key: "tiktok_caption_max_chars", label: "TikTok Caption Max Chars", group: "TikTok / Facebook", kind: .number),
    ConfigField(key: "tiktok_upload_timeout_sec", label: "TikTok Upload Timeout", group: "TikTok / Facebook", kind: .number),
    ConfigField(key: "tiktok_auto_split", label: "TikTok Auto Split", group: "TikTok / Facebook", kind: .toggle),
    ConfigField(key: "tiktok_headless", label: "TikTok Headless", group: "TikTok / Facebook", kind: .toggle),
    ConfigField(key: "auto_upload_tiktok", label: "Auto Upload TikTok", group: "TikTok / Facebook", kind: .toggle),
    ConfigField(key: "facebook_page_access_token", label: "Facebook Page Token", group: "TikTok / Facebook", kind: .text, sensitive: true, placeholder: "De trong de giu token da luu"),
    ConfigField(key: "facebook_app_id", label: "Facebook App ID", group: "TikTok / Facebook", kind: .text),
    ConfigField(key: "facebook_app_secret", label: "Facebook App Secret", group: "TikTok / Facebook", kind: .text, sensitive: true, placeholder: "De trong de giu secret da luu"),
    ConfigField(key: "facebook_reels_actor_id", label: "Facebook Actor ID", group: "TikTok / Facebook", kind: .text),
    ConfigField(key: "facebook_graph_version", label: "Facebook Graph Version", group: "TikTok / Facebook", kind: .text),
    ConfigField(key: "facebook_upload_mode", label: "Facebook Upload Mode", group: "TikTok / Facebook", kind: .text),
    ConfigField(key: "facebook_reels_short_threshold_sec", label: "Facebook Short Threshold", group: "TikTok / Facebook", kind: .number),
    ConfigField(key: "facebook_reels_video_state", label: "Facebook Video State", group: "TikTok / Facebook", kind: .text),
    ConfigField(key: "facebook_reels_max_minutes", label: "Facebook Max Minutes", group: "TikTok / Facebook", kind: .number),
    ConfigField(key: "facebook_reels_auto_split", label: "Facebook Auto Split", group: "TikTok / Facebook", kind: .toggle),
    ConfigField(key: "facebook_reels_poll_timeout_sec", label: "Facebook Poll Timeout", group: "TikTok / Facebook", kind: .number),
    ConfigField(key: "facebook_reels_poll_interval_sec", label: "Facebook Poll Interval", group: "TikTok / Facebook", kind: .number),
    ConfigField(key: "facebook_reels_request_timeout_sec", label: "Facebook Request Timeout", group: "TikTok / Facebook", kind: .number),
    ConfigField(key: "facebook_api_proxy", label: "Facebook API Proxy", group: "TikTok / Facebook", kind: .text),
    ConfigField(key: "auto_upload_facebook_reels", label: "Auto Upload Facebook", group: "TikTok / Facebook", kind: .toggle),

    ConfigField(key: "ffmpeg_encoder", label: "FFmpeg Encoder", group: "Render", kind: .text),
    ConfigField(key: "demucs_model", label: "Demucs Model", group: "Render", kind: .text),
    ConfigField(key: "blur_sigma", label: "Blur Sigma", group: "Render", kind: .number),
    ConfigField(key: "mask_h", label: "Mask Height", group: "Render", kind: .number),
    ConfigField(key: "mask_y_pct", label: "Mask Y Position %", group: "Render", kind: .number),
    ConfigField(key: "font_name", label: "Font Video", group: "Render", kind: .text),
    ConfigField(key: "font_name_thumb", label: "Font Thumbnail", group: "Render", kind: .text),
    ConfigField(key: "font_size", label: "Font Size", group: "Render", kind: .number),
    ConfigField(key: "font_color", label: "Font Color", group: "Render", kind: .text),
    ConfigField(key: "font_outline_color", label: "Font Outline Color", group: "Render", kind: .text),
    ConfigField(key: "font_outline_width", label: "Font Outline Width", group: "Render", kind: .number),
    ConfigField(key: "margin_v", label: "Margin V", group: "Render", kind: .number),
    ConfigField(key: "rotate_deg", label: "Rotate", group: "Render", kind: .number),
    ConfigField(key: "intro_path", label: "Intro Path", group: "Render", kind: .text),
    ConfigField(key: "mirror", label: "Mirror", group: "Render", kind: .toggle),
    ConfigField(key: "use_intro", label: "Use Intro", group: "Render", kind: .toggle),
    ConfigField(key: "auto_upload", label: "Auto Upload YouTube", group: "Render", kind: .toggle),
    ConfigField(key: "upload_fifo_strict", label: "Upload Strict FIFO", group: "Render", kind: .toggle),
    ConfigField(key: "pipeline_skip_after_retry_exhausted", label: "Skip After Retry Exhausted", group: "Render", kind: .toggle),
    ConfigField(key: "batch_pipeline_concurrency", label: "Pipeline Concurrency", group: "Render", kind: .number),
    ConfigField(key: "download_concurrency", label: "Download Concurrency", group: "Render", kind: .number),
    ConfigField(key: "gpu_heavy_concurrency", label: "GPU Concurrency", group: "Render", kind: .number),
    ConfigField(key: "pipeline_retry_max", label: "Retry Max", group: "Render", kind: .number),

    ConfigField(key: "thumbnail_mode", label: "Thumbnail Mode", group: "Thumbnail AI", kind: .text),
    ConfigField(key: "ai_thumbnail_provider", label: "AI Thumbnail Provider", group: "Thumbnail AI", kind: .text),
    ConfigField(key: "ai_thumbnail_model", label: "AI Thumbnail Model", group: "Thumbnail AI", kind: .text),
    ConfigField(key: "ai_thumbnail_timeout_sec", label: "AI Thumbnail Timeout", group: "Thumbnail AI", kind: .number),
    ConfigField(key: "ai_thumbnail_style", label: "AI Thumbnail Style", group: "Thumbnail AI", kind: .text),
    ConfigField(key: "ai_thumbnail_api_key", label: "AI Thumbnail API Key", group: "Thumbnail AI", kind: .text, sensitive: true, placeholder: "De trong de giu key da luu"),
    ConfigField(key: "ai_thumbnail_cloudflare_account_id", label: "Cloudflare Account ID", group: "Thumbnail AI", kind: .text),
    ConfigField(key: "ai_thumbnail_cloudflare_api_token", label: "Cloudflare API Token", group: "Thumbnail AI", kind: .text, sensitive: true, placeholder: "De trong de giu token da luu"),
    ConfigField(key: "ai_thumbnail_cloudflare_mode", label: "Cloudflare Mode", group: "Thumbnail AI", kind: .text),
    ConfigField(key: "ai_thumbnail_img2img_strength", label: "Img2Img Strength", group: "Thumbnail AI", kind: .number),
    ConfigField(key: "ai_thumbnail_steps", label: "AI Thumbnail Steps", group: "Thumbnail AI", kind: .number),

    ConfigField(key: "douyin_warp_enabled", label: "Douyin WARP Enabled", group: "WARP / Watchdog", kind: .toggle),
    ConfigField(key: "douyin_warp_proxy", label: "Douyin WARP Proxy", group: "WARP / Watchdog", kind: .text),
    ConfigField(key: "youtube_watchdog_enabled", label: "YouTube Watchdog", group: "WARP / Watchdog", kind: .toggle),
    ConfigField(key: "youtube_watchdog_interval_min", label: "YouTube Watchdog Interval", group: "WARP / Watchdog", kind: .number),
    ConfigField(key: "youtube_watchdog_stuck_minutes", label: "YouTube Stuck Minutes", group: "WARP / Watchdog", kind: .number),
    ConfigField(key: "youtube_watchdog_max_retries", label: "YouTube Max Retries", group: "WARP / Watchdog", kind: .number),
    ConfigField(key: "douyin_watchdog_enabled", label: "Douyin Watchdog", group: "WARP / Watchdog", kind: .toggle),
    ConfigField(key: "douyin_watchdog_user_url", label: "Douyin Watchdog URL", group: "WARP / Watchdog", kind: .text),
    ConfigField(key: "douyin_watchdog_interval_min", label: "Douyin Watchdog Interval", group: "WARP / Watchdog", kind: .number),
    ConfigField(key: "douyin_watchdog_min_duration_sec", label: "Douyin Min Duration", group: "WARP / Watchdog", kind: .number)
]

let appConfigGroups = [
    "General",
    "Translation / 9Router",
    "TTS / CapCut",
    "TikTok / Facebook",
    "Render",
    "Thumbnail AI",
    "WARP / Watchdog"
]

func editableConfigValue(_ value: Any?, kind: ConfigFieldKind) -> String {
    switch kind {
    case .toggle:
        return bool(value) ? "true" : "false"
    case .number:
        if let value = value as? Double { return String(value) }
        if let value = value as? Float { return String(value) }
        if let value = value as? Int { return String(value) }
        return string(value)
    case .text:
        return string(value)
    }
}

func configPayloadValue(_ raw: String, kind: ConfigFieldKind) -> Any {
    switch kind {
    case .toggle:
        return configBool(raw)
    case .number:
        if raw.contains("."), let value = Double(raw) { return value }
        return Int(raw) ?? 0
    case .text:
        return raw
    }
}

func configBool(_ value: String?) -> Bool {
    let normalized = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return ["1", "true", "yes", "on"].contains(normalized)
}

func safeConfigDisplay(key: String, value: Any?, masked: Any?) -> String {
    let lower = key.lowercased()
    if lower.contains("key") || lower.contains("secret") || lower.contains("token") || lower.contains("password") {
        let maskedText = string(masked)
        return maskedText.isEmpty ? "***" : maskedText
    }
    if let dict = value as? [String: Any] { return compactJSON(dict) }
    if let array = value as? [Any] { return compactJSON(array) }
    return string(value)
}

func compactJSON(_ value: Any?) -> String {
    guard let value = value else { return "" }
    if JSONSerialization.isValidJSONObject(value),
       let data = try? JSONSerialization.data(withJSONObject: value, options: []),
       let text = String(data: data, encoding: .utf8) {
        return text
    }
    return String(describing: value)
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
    let seriesFolder = string(ctx["series_folder"], fallback: string(data["series_folder"]))
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
        seriesFolder: seriesFolder,
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
    let episodesRaw = (data["episodes"] as? [[String: Any]]) ?? []
    let episodes = episodesRaw.map { item -> SeriesEpisode in
        let metadata = item["metadata"] as? [String: Any] ?? [:]
        let ctx = (item["series_context"] as? [String: Any]) ?? (metadata["series_context"] as? [String: Any]) ?? [:]
        let projectName = string(item["project_name"], fallback: string(item["name"], fallback: string(item["folder"])))
        let episodeNo = int(item["_ep_no"], fallback: int(ctx["episode_no"], fallback: extractEpisodeNo(string(metadata["title"])) ?? 0))
        let title = episodeNo > 0
            ? "Tap \(episodeNo) | \(string(data["series_name"], fallback: "Series")) | MiuBonVietSub"
            : string(metadata["title"], fallback: projectName)
        return SeriesEpisode(
            projectName: projectName,
            title: title,
            episodeNo: episodeNo > 0 ? episodeNo : 1,
            rendered: !string(item["final_video"]).isEmpty || (item["steps_completed"] as? [String] ?? []).contains("render"),
            created: string(item["created_at"], fallback: string(item["updated_at"]))
        )
    }
    return SeriesRow(
        folder: string(data["series_folder"], fallback: string(data["folder"])),
        name: string(data["series_name"], fallback: string(data["name"], fallback: string(data["series_name_vi"], fallback: "Series"))),
        episodeRange: range,
        total: int(data["total_downloaded"], fallback: int(data["total"], fallback: (data["episodes"] as? [Any])?.count ?? 0)),
        rendered: int(data["rendered_count"]),
        uploaded: int(data["uploaded_count"]),
        episodes: episodes
    )
}

func scrapeVideoPayload(_ video: ScrapeVideo) -> [String: Any] {
    [
        "url": video.url,
        "desc": video.caption,
        "caption": video.caption,
        "duration": video.duration,
        "duration_sec": double(video.duration),
        "local_done": video.done
    ]
}

func parseAISeriesGroups(_ data: [String: Any]) -> [AISeriesGroup] {
    let groups = (data["groups"] as? [[String: Any]]) ?? []
    return groups.map { item in
        let name = string(item["series_name_vi"], fallback: string(item["series_name"], fallback: "Series"))
        let urls = ((item["urls"] as? [String]) ?? []).filter { !$0.isEmpty }
        return AISeriesGroup(
            folder: string(item["folder"], fallback: string(item["folder_name"])),
            name: name,
            originalName: string(item["series_name"]),
            reason: string(item["reason"]),
            confidence: double(item["confidence"]),
            urls: urls,
            uniqueURLs: ((item["unique_episode_urls"] as? [String]) ?? []).filter { !$0.isEmpty },
            episodeMin: intOptional(item["episode_min"]),
            episodeMax: intOptional(item["episode_max"]),
            duplicateCount: int(item["duplicate_episode_count"]),
            videos: (item["videos"] as? [[String: Any]]) ?? []
        )
    }
}

func buildSeriesContextMap(group: AISeriesGroup, urls: [String]) -> [String: [String: Any]] {
    var videosByURL: [String: [String: Any]] = [:]
    for video in group.videos {
        let url = string(video["url"]).trimmingCharacters(in: .whitespacesAndNewlines)
        if !url.isEmpty { videosByURL[url] = video }
    }

    let orderedURLs = group.urls.isEmpty
        ? group.videos.map { string($0["url"]) }.filter { !$0.isEmpty }
        : group.urls
    var indexByURL: [String: Int] = [:]
    for (index, url) in orderedURLs.enumerated() where indexByURL[url] == nil {
        indexByURL[url] = index
    }

    let knownEpisodes = orderedURLs.enumerated().compactMap { index, url -> (Int, Int)? in
        guard let ep = intOptional(videosByURL[url]?["episode_no"]), ep > 0 else { return nil }
        return (index, ep)
    }

    func inferredEpisode(for url: String) -> Int? {
        if let direct = intOptional(videosByURL[url]?["episode_no"]), direct > 0 { return direct }
        guard let index = indexByURL[url], !knownEpisodes.isEmpty else { return nil }
        if let left = knownEpisodes.last(where: { $0.0 < index }),
           let right = knownEpisodes.first(where: { $0.0 > index }),
           right.0 - left.0 == right.1 - left.1 {
            let candidate = left.1 + (index - left.0)
            return candidate > 0 ? candidate : nil
        }
        if knownEpisodes.count >= 2 {
            let first = knownEpisodes[0]
            let second = knownEpisodes[1]
            if index < first.0, second.0 - first.0 == second.1 - first.1 {
                let candidate = first.1 - (first.0 - index)
                return candidate > 0 ? candidate : nil
            }
            let previous = knownEpisodes[knownEpisodes.count - 2]
            let last = knownEpisodes[knownEpisodes.count - 1]
            if index > last.0, last.0 - previous.0 == last.1 - previous.1 {
                let candidate = last.1 + (index - last.0)
                return candidate > 0 ? candidate : nil
            }
        }
        return nil
    }

    var contexts: [String: [String: Any]] = [:]
    for url in urls {
        contexts[url] = [
            "series_name_vi": group.name,
            "series_name": group.originalName.isEmpty ? group.name : group.originalName,
            "series_folder": group.folder,
            "episode_no": inferredEpisode(for: url).map { $0 as Any } ?? NSNull(),
            "episode_min": group.episodeMin.map { $0 as Any } ?? NSNull(),
            "episode_max": group.episodeMax.map { $0 as Any } ?? NSNull(),
            "source": "douyin_series_group"
        ]
    }
    return contexts
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
