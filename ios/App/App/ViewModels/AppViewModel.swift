import Foundation
import SwiftUI
import Combine

@MainActor
final class AppViewModel: ObservableObject {
    static let shared = AppViewModel()
    
    // MARK: - Global States
    @Published var themeRaw: String {
        didSet { UserDefaults.standard.set(themeRaw, forKey: "miubon.theme") }
    }
    @Published var pollSeconds: Int {
        didSet { UserDefaults.standard.set(pollSeconds, forKey: "miubon.pollSeconds") }
    }
    @Published var selectedTab: MainTab = .pipeline
    
    // MARK: - App Data
    @Published var health = HealthSnapshot()
    @Published var isOnline = false
    @Published var statusMessage = "Đang khởi tạo..."
    
    // Pipeline & Queue
    @Published var urlInput = ""
    @Published var activeJobId = ""
    @Published var activeQueueId = ""
    @Published var pipelineStatus = "Idle"
    @Published var pipelineProgress: Double = 0
    @Published var pipelineMessage = "Sẵn sàng"
    @Published var logLines: [String] = []
    
    @Published var queue = QueueSnapshot()
    @Published var runningQueues: [QueueSnapshot] = []
    
    // Projects
    @Published var projects: [ProjectRow] = []
    @Published var seriesRows: [SeriesRow] = []
    @Published var selectedProject = ""
    @Published var videoLibraryMode = "series"
    
    // Uploads
    @Published var uploadRows: [UploadQueueRow] = []
    
    // Scraper
    @Published var scrapeURL = ""
    @Published var scrapeMinDuration = "60"
    @Published var scrapeOldestFirst = true
    @Published var scrapeStatus = "Idle"
    @Published var scrapeLogLines: [String] = []
    @Published var scrapeVideos: [ScrapeVideo] = []
    
    @Published var aiSeriesGroups: [AISeriesGroup] = []
    @Published var selectedAIGroupIDs: Set<UUID> = []
    @Published var aiGroupMessage = "Chưa gom nhóm"
    @Published var douyinWatchdog = DouyinWatchdogState()
    
    // Dictionary
    @Published var glossaryRows: [GlossaryEntry] = []
    @Published var glossarySourceInput = ""
    @Published var glossaryTargetInput = ""
    
    // Settings
    @Published var configValues: [String: String] = [:]
    @Published var configRows: [ConfigRow] = []
    
    // Network Service
    private var network = NetworkManager.shared
    private var pollTask: Task<Void, Never>?
    
    private init() {
        themeRaw = UserDefaults.standard.string(forKey: "miubon.theme") ?? AppTheme.system.rawValue
        let savedPoll = UserDefaults.standard.integer(forKey: "miubon.pollSeconds")
        pollSeconds = savedPoll == 0 ? 3 : savedPoll
        
        // Listen to network status
        Task {
            for await _ in network.$isOnline.values {
                self.isOnline = network.isOnline
                self.statusMessage = network.statusMessage
            }
        }
    }
    
    // MARK: - Core Methods
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
        // Gọi thêm các hàm tải queue, dự án...
    }
    
    func refreshHealth(silent: Bool = false) async {
        do {
            let result = try await network.request("/api/health", timeout: 5)
            // Parse result to health (giả lập đơn giản)
            if let server = result["server"] as? [String: Any], let status = server["status"] as? String {
                health.server = status
            }
            network.isOnline = true
            if !silent { network.statusMessage = "Trực tuyến" }
        } catch {
            network.isOnline = false
            if !silent { network.statusMessage = error.localizedDescription }
        }
    }
    
    func refreshProjects() async {
        // Dummy implementation to satisfy compiler
    }
    
    func startPipeline(single: Bool) async {
        guard !urlInput.isEmpty else {
            statusMessage = "Vui lòng nhập URL"
            return
        }
        
        do {
            let result = try await network.request("/api/pipeline/start", method: "POST", body: ["url": urlInput])
            activeJobId = result["job_id"] as? String ?? ""
            pipelineStatus = "Running"
        } catch {
            statusMessage = error.localizedDescription
        }
    }
}
