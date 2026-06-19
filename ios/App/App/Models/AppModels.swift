import Foundation
import SwiftUI

// MARK: - Enums
enum AppTheme: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return "Hệ thống"
        case .light: return "Sáng"
        case .dark: return "Tối"
        }
    }
}

enum MainTab: String, CaseIterable, Identifiable {
    case pipeline, running, scraper, projects, videos, uploads, dictionary, settings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .pipeline: return "Xử lý"
        case .running: return "Đang chạy"
        case .scraper: return "Quét"
        case .projects: return "Dự án"
        case .videos: return "Xem"
        case .uploads: return "Công cụ"
        case .dictionary: return "Từ điển"
        case .settings: return "Cài đặt"
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

// MARK: - Network & Health
struct HealthSnapshot {
    var server = "Không rõ"
    var youtube = "Không rõ"
    var tiktok = "Không rõ"
    var facebook = "Không rõ"
    var drive = "Không rõ"
}

// MARK: - Pipeline & Queue
struct QueueItem: Identifiable {
    let id = UUID()
    var index: Int
    var url: String
    var status: String
    var message: String
    var progress: Double
}

struct QueueSnapshot: Identifiable {
    var id = ""
    var status = ""
    var progress: Double = 0
    var message = ""
    var total = 0
    var completed = 0
    var items: [QueueItem] = []
}

// MARK: - Projects
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

// MARK: - Videos & Player
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

struct WatchProgress {
    var episodeIndex: Int
    var time: Double
}

// MARK: - Uploads
struct UploadQueueRow: Identifiable {
    let id = UUID()
    var project: String
    var status: String
    var channel: String
    var message: String
}

// MARK: - Scraper
struct ScrapeVideo: Identifiable {
    let id = UUID()
    var url: String
    var caption: String
    var duration: String
    var done: Bool
    var translation: String = ""
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
    var summary = "Chưa load watchdog"
}

// MARK: - Dictionary
struct GlossaryEntry: Identifiable {
    let id = UUID()
    var source: String
    var target: String
}

// MARK: - Settings
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

struct StatusLine: Identifiable {
    let id = UUID()
    var title: String
    var value: String
    var tone: Color
}
