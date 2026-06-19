import SwiftUI

struct RunningView: View {
    @EnvironmentObject var appVM: AppViewModel
    @StateObject private var logService = RealtimeLogService()
    
    var body: some View {
        NavigationView {
            VStack {
                if appVM.runningQueues.isEmpty {
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.green)
                    Text("Không có tiến trình nào đang chạy")
                        .font(.headline)
                        .padding()
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(appVM.runningQueues) { queue in
                                queueCard(queue)
                            }
                        }
                        .padding()
                    }
                }
                
                // Console Log
                if !appVM.activeQueueId.isEmpty {
                    consoleLogView
                }
            }
            .navigationTitle("Đang chạy")
            .background(Color(UIColor.systemGroupedBackground).edgesIgnoringSafeArea(.all))
        }
    }
    
    private func queueCard(_ queue: QueueSnapshot) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Queue: \(queue.id.prefix(8))")
                        .font(.headline)
                    Spacer()
                    Text("\(queue.completed)/\(queue.total)")
                        .bold()
                }
                
                ProgressView(value: queue.progress, total: 1.0)
                    .tint(.blue)
                
                Text(queue.message)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    
                HStack {
                    Button("Tạm dừng") { /* Pause API */ }
                        .buttonStyle(.bordered)
                    Button("Tiếp tục") { /* Resume API */ }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .onTapGesture {
            appVM.activeQueueId = queue.id
            logService.startStreamingLogs(queueId: queue.id, itemIndex: 0)
        }
    }
    
    private var consoleLogView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Console Log (Realtime)")
                    .font(.caption)
                    .bold()
                Spacer()
                Button(action: { logService.stopStreaming() }) {
                    Image(systemName: "stop.circle.fill").foregroundColor(.red)
                }
            }
            .padding(8)
            .background(Color(UIColor.secondarySystemBackground))
            
            ScrollView {
                LazyVStack(alignment: .leading) {
                    ForEach(logService.logs, id: \.self) { line in
                        Text(line)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(.green)
                    }
                }
                .padding(8)
            }
            .frame(height: 200)
            .background(Color.black)
        }
        .cornerRadius(12)
        .padding()
    }
}
