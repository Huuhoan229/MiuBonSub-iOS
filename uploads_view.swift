struct UploadsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScreenScroll {
            SectionCard(title: "Tài khoản & trạng thái", symbol: "person.crop.circle.badge.checkmark") {
                if model.toolStatuses.isEmpty {
                    EmptyState(text: "Bấm Làm mới để kiểm tra YouTube, TikTok, Facebook, Drive, Watchdog.")
                }
                ForEach(model.toolStatuses) { row in
                    HStack {
                        Text(row.title).font(.subheadline.weight(.semibold))
                        Spacer()
                        StatusPill(text: row.value, tone: row.tone)
                    }
                    .padding(10)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                Text(model.toolMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    SmallButton(title: "Làm mới", symbol: "arrow.clockwise") { Task { await model.refreshToolStatuses() } }
                    SmallButton(title: "Đăng nhập YouTube", symbol: "play.tv") { Task { await model.runToolAction(title: "YouTube login", path: "/api/youtube/login") } }
                    SmallButton(title: "TikTok OAuth", symbol: "music.note") { Task { await model.openURLFromEndpoint(title: "TikTok OAuth", path: "/api/tiktok/oauth/start") } }
                    SmallButton(title: "Đăng nhập Drive", symbol: "externaldrive") { model.openBackendPath("/api/gdrive/login") }
                }
            }

            SectionCard(title: "Upload nhanh", symbol: "arrow.up.circle") {
                Picker("Project", selection: $model.selectedProject) {
                    ForEach(model.projects) { project in
                        Text(project.displayName).tag(project.folderName)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    SmallButton(title: "TikTok", symbol: "music.note") { Task { await model.uploadSelected(to: "tiktok") } }
                    SmallButton(title: "Facebook", symbol: "f.circle.fill") { Task { await model.uploadSelected(to: "facebook") } }
                    SmallButton(title: "Drive", symbol: "externaldrive.fill") { Task { await model.uploadSelected(to: "drive") } }
                    SmallButton(title: "Queue YouTube", symbol: "play.tv.fill") { Task { await model.refreshUploadQueue() } }
                }
                Text(model.uploadStatus)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            SectionCard(title: "Queue YouTube", symbol: "list.bullet.clipboard") {
                HStack {
                    SmallButton(title: "Sắp xếp tập", symbol: "arrow.up.arrow.down") {
                        Task { await model.runToolAction(title: "Sort YouTube queue", path: "/api/youtube/queue/sort", body: ["mode": "episode_asc"]) }
                    }
                    SmallButton(title: "Watchdog", symbol: "shield.lefthalf.filled") {
                        Task { await model.runToolAction(title: "YouTube watchdog", path: "/api/youtube/watchdog/run-once") }
                    }
                }
                if model.uploadRows.isEmpty {
                    EmptyState(text: "Queue upload YouTube đang trống")
                }
                ForEach(model.uploadRows) { row in
                    UploadRowView(row: row)
                }
            }

            SectionCard(title: "Đồng bộ & watchdog", symbol: "antenna.radiowaves.left.and.right") {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    SmallButton(title: "Đồng bộ Drive", symbol: "arrow.triangle.2.circlepath") {
                        Task { await model.runToolAction(title: "Drive sync", path: "/api/gdrive/sync_projects_async") }
                    }
                    SmallButton(title: "Upload Drive hàng loạt", symbol: "icloud.and.arrow.up") {
                        Task { await model.runToolAction(title: "Drive mass upload", path: "/api/gdrive/mass_upload_videos") }
                    }
                    SmallButton(title: "Douyin watchdog", symbol: "magnifyingglass.circle") {
                        Task { await model.runToolAction(title: "Douyin watchdog", path: "/api/douyin/watchdog/run-once") }
                    }
                    SmallButton(title: "FB pages", symbol: "f.circle") {
                        Task { await model.runToolAction(title: "Facebook status", path: "/api/facebook/reels/status", method: "GET") }
                    }
                }
            }
        }
        .task { await model.refreshToolStatuses() }
    }
}

