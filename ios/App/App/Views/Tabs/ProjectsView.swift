import SwiftUI

struct ProjectsView: View {
    @EnvironmentObject var appVM: AppViewModel
    
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Thư viện Series")) {
                    ForEach(appVM.seriesRows) { series in
                        NavigationLink(destination: Text("Chi tiết Series: \(series.name)")) {
                            HStack {
                                Image(systemName: "folder.fill")
                                    .foregroundColor(.blue)
                                VStack(alignment: .leading) {
                                    Text(series.name).font(.headline)
                                    Text("\(series.episodeRange) • \(series.total) tập")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
                
                Section(header: Text("Dự án Lẻ")) {
                    ForEach(appVM.projects.filter { $0.series.isEmpty }) { project in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(project.displayName).font(.headline)
                                Text(project.subtitle).font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                            if project.rendered {
                                Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                            } else {
                                Button("Resume") { }
                                    .buttonStyle(.bordered)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Dự Án")
            .onAppear {
                Task {
                    await appVM.refreshProjects()
                    // await appVM.refreshSeries()
                }
            }
        }
    }
}
