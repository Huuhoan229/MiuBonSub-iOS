import SwiftUI

struct ScraperView: View {
    @EnvironmentObject var appVM: AppViewModel
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Quét Video Douyin")) {
                    TextField("URL Douyin Profile...", text: $appVM.scrapeURL)
                    TextField("Thời lượng tối thiểu (giây)", text: $appVM.scrapeMinDuration)
                        .keyboardType(.numberPad)
                    Toggle("Quét từ cũ nhất", isOn: $appVM.scrapeOldestFirst)
                    
                    Button(action: {
                        // Gọi API scrape
                    }) {
                        Text("Bắt đầu quét")
                            .frame(maxWidth: .infinity, alignment: .center)
                            .foregroundColor(.blue)
                    }
                }
                
                Section(header: Text("Công Cụ AI Gom Nhóm")) {
                    Button("Dịch Caption") { }
                    Button("Gom nhóm AI") { }
                }
                
                Section(header: Text("Douyin Watchdog (Theo dõi Tự Động)")) {
                    Toggle("Kích hoạt Watchdog", isOn: $appVM.douyinWatchdog.enabled)
                    TextField("Chu kỳ (phút)", text: $appVM.douyinWatchdog.intervalMin)
                        .keyboardType(.numberPad)
                    Button("Lưu cấu hình & Chạy ngay") { }
                }
            }
            .navigationTitle("Trình Quét")
        }
    }
}
