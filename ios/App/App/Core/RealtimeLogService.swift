import Foundation
import Combine

/// Dịch vụ quản lý kết nối Server-Sent Events (SSE) để nhận log theo thời gian thực (tránh polling gây hao pin)
class RealtimeLogService: ObservableObject {
    @Published var logs: [String] = []
    
    private var urlSession: URLSession?
    private var eventSourceTask: URLSessionDataTask?
    
    func startStreamingLogs(queueId: String, itemIndex: Int) {
        // Dọn dẹp log cũ
        self.logs = []
        stopStreaming()
        
        let backendURL = NetworkManager.shared.backendURL
        let cleanBase = backendURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let path = "\(cleanBase)/api/pipeline/queue/\(queueId)/item/\(itemIndex)/logs/stream"
        
        guard let url = URL(string: path) else { return }

        var request = URLRequest(url: url)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        // Thiết lập timeout cao để giữ kết nối SSE
        request.timeoutInterval = 3600 

        urlSession = URLSession(configuration: .default, delegate: SSEDelegate(service: self), delegateQueue: nil)
        eventSourceTask = urlSession?.dataTask(with: request)
        eventSourceTask?.resume()
    }
    
    func stopStreaming() {
        eventSourceTask?.cancel()
        urlSession?.invalidateAndCancel()
        eventSourceTask = nil
        urlSession = nil
    }
}

/// Lớp uỷ quyền xử lý gói tin trả về từ luồng URLSession theo dạng Streaming
class SSEDelegate: NSObject, URLSessionDataDelegate {
    weak var service: RealtimeLogService?
    private var buffer = ""

    init(service: RealtimeLogService) {
        self.service = service
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let string = String(data: data, encoding: .utf8) else { return }
        
        // Thêm dữ liệu vào bộ đệm và tách dòng
        buffer += string
        var lines = buffer.components(separatedBy: "\n")
        
        // Giữ lại phần cuối cùng chưa hoàn chỉnh trong bộ đệm
        if !buffer.hasSuffix("\n") {
            buffer = lines.removeLast()
        } else {
            buffer = ""
        }
        
        let newLogs = lines.filter { $0.hasPrefix("data: ") }.map { String($0.dropFirst(6)) }
        
        if !newLogs.isEmpty {
            DispatchQueue.main.async {
                self.service?.logs.append(contentsOf: newLogs)
            }
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error, (error as NSError).code != NSURLErrorCancelled {
            DispatchQueue.main.async {
                self.service?.logs.append("[SSE Disconnected] \(error.localizedDescription)")
            }
        }
    }
}
