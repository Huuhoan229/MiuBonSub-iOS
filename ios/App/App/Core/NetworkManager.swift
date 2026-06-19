import Foundation
import Combine
import UserNotifications

/// Lớp Singleton quản lý toàn bộ giao tiếp mạng (REST API)
class NetworkManager: ObservableObject {
    static let shared = NetworkManager()
    
    @Published var backendURL: String {
        didSet { UserDefaults.standard.set(backendURL, forKey: "miubon.backendURL") }
    }
    
    @Published var authToken: String {
        didSet { UserDefaults.standard.set(authToken, forKey: "miubon.authToken") }
    }
    
    @Published var isOnline: Bool = false
    @Published var statusMessage: String = "Chưa kết nối"
    
    private init() {
        // Cấu hình URL mặc định nếu chưa có
        self.backendURL = UserDefaults.standard.string(forKey: "miubon.backendURL") ?? "https://api-mbvietsub.miubon.xyz"
        self.authToken = UserDefaults.standard.string(forKey: "miubon.authToken") ?? ""
    }
    
    /// Hàm gọi API sử dụng async/await, trả về Dictionary (JSON Object)
    func request(_ path: String, method: String = "GET", body: Any? = nil, timeout: TimeInterval = 30) async throws -> [String: Any] {
        let cleanBase = backendURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !cleanBase.isEmpty, let url = URL(string: cleanBase + path) else {
            throw NSError(domain: "NetworkManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Backend URL chưa hợp lệ"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        if !authToken.isEmpty {
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        }

        if let body = body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let message = String(data: data, encoding: .utf8) ?? "HTTP Lỗi \(http.statusCode)"
            throw NSError(domain: "NetworkManager", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: message])
        }

        if data.isEmpty { return [:] }
        let object = try JSONSerialization.jsonObject(with: data)
        return object as? [String: Any] ?? ["value": object]
    }
    
    /// Hàm tải dữ liệu thô (vd: hình ảnh, file audio)
    func requestData(_ path: String, method: String = "GET", body: Any? = nil, timeout: TimeInterval = 120) async throws -> Data {
        let cleanBase = backendURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !cleanBase.isEmpty, let url = URL(string: cleanBase + path) else {
            throw NSError(domain: "NetworkManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Backend URL chưa hợp lệ"])
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
            throw NSError(domain: "NetworkManager", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: message])
        }
        return data
    }
}
