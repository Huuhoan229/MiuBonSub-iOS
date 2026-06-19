import SwiftUI

struct UploadsView: View {
    @EnvironmentObject var appVM: AppViewModel
    
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Tải lên nhanh")) {
                    Picker("Chọn Dự án", selection: $appVM.selectedProject) {
                        ForEach(appVM.projects) { project in
                            Text(project.displayName).tag(project.folderName)
                        }
                    }
                    
                    HStack {
                        Button("YouTube") { }
                            .buttonStyle(.bordered)
                        Button("TikTok") { }
                            .buttonStyle(.bordered)
                        Button("Facebook") { }
                            .buttonStyle(.bordered)
                    }
                }
                
                Section(header: Text("Hàng đợi YouTube")) {
                    ForEach(appVM.uploadRows) { row in
                        VStack(alignment: .leading) {
                            Text(row.project).font(.headline)
                            Text("\(row.channel) - \(row.status)")
                                .font(.caption)
                                .foregroundColor(row.status == "done" ? .green : .secondary)
                        }
                    }
                }
            }
            .navigationTitle("Công Cụ Upload")
        }
    }
}
