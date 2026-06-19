import SwiftUI

struct DictionaryView: View {
    @EnvironmentObject var appVM: AppViewModel
    
    var body: some View {
        NavigationView {
            VStack {
                Form {
                    Section(header: Text("Bộ Từ Điển Theo Phim")) {
                        Picker("Chọn Series", selection: .constant("")) {
                            Text("Tất cả").tag("")
                        }
                        
                        Button("AI Trích Xuất Từ Mới") {
                            // Gọi API extract
                        }
                    }
                    
                    Section(header: Text("Thêm / Sửa Từ")) {
                        TextField("Tiếng Trung (Gốc)", text: $appVM.glossarySourceInput)
                        TextField("Tiếng Việt (Dịch)", text: $appVM.glossaryTargetInput)
                        Button("Lưu Từ") { }
                            .disabled(appVM.glossarySourceInput.isEmpty || appVM.glossaryTargetInput.isEmpty)
                    }
                }
                
                List {
                    ForEach(appVM.glossaryRows) { entry in
                        HStack {
                            Text(entry.source).bold()
                            Spacer()
                            Image(systemName: "arrow.right").foregroundColor(.secondary)
                            Spacer()
                            Text(entry.target)
                        }
                    }
                }
            }
            .navigationTitle("Từ Điển")
        }
    }
}
