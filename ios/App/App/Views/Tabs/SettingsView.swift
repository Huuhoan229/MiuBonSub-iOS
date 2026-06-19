import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appVM: AppViewModel
    @State private var backendURLInput: String = ""
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Kết nối Backend")) {
                    TextField("URL (VD: https://api.miubon.xyz)", text: $backendURLInput)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    
                    Button("Cập nhật URL") {
                        NetworkManager.shared.backendURL = backendURLInput
                        Task { await appVM.refreshHealth(silent: false) }
                    }
                    
                    if appVM.isOnline {
                        Label("Đã kết nối", systemImage: "checkmark.circle.fill").foregroundColor(.green)
                    } else {
                        Label("Mất kết nối", systemImage: "xmark.circle.fill").foregroundColor(.red)
                    }
                }
                
                Section(header: Text("Tài Khoản & Thông Báo")) {
                    Button("Yêu cầu quyền gửi Thông Báo") {
                        NotificationCenterBridge.shared.configure()
                    }
                }
                
                Section(header: Text("Giao Diện")) {
                    Picker("Chủ đề", selection: $appVM.themeRaw) {
                        Text("Hệ thống").tag("system")
                        Text("Sáng").tag("light")
                        Text("Tối").tag("dark")
                    }
                }
                
                Section(header: Text("Cấu hình Server (config.json)")) {
                    Button("Tải lại cấu hình") {
                        // fetch config.json
                    }
                    // Danh sách ConfigRows...
                }
            }
            .navigationTitle("Cài Đặt")
            .onAppear {
                backendURLInput = NetworkManager.shared.backendURL
            }
        }
    }
}
