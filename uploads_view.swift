struct UploadsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScreenScroll {
            SectionCard(title: "Accounts & status", symbol: "person.crop.circle.badge.checkmark") {
                if model.toolStatuses.isEmpty {
                    EmptyState(text: "Tap Refresh to check YouTube, TikTok, Facebook, Drive, and watchdog.")
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
                    SmallButton(title: "Refresh", symbol: "arrow.clockwise") {
                        Task {
                            await model.refreshToolStatuses()
                            await model.refreshUploadQueue()
                            await model.refreshUploadQueueControls()
                        }
                    }
                    SmallButton(title: "YouTube login", symbol: "play.tv") {
                        Task { await model.runToolAction(title: "YouTube login", path: "/api/youtube/login") }
                    }
                    SmallButton(title: "TikTok OAuth", symbol: "music.note") {
                        Task { await model.openURLFromEndpoint(title: "TikTok OAuth", path: "/api/tiktok/oauth/start") }
                    }
                    SmallButton(title: "Drive login", symbol: "externaldrive") {
                        model.openBackendPath("/api/gdrive/login")
                    }
                }
            }

            SectionCard(title: "Upload queue", symbol: "list.bullet.clipboard") {
                Picker("Queue", selection: $model.uploadQueuePlatform) {
                    ForEach(UploadQueuePlatform.allCases) { platform in
                        Text(platform.label).tag(platform)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: model.uploadQueuePlatform) { platform in
                    Task { await model.selectUploadQueuePlatform(platform) }
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    MetricTile(title: "Queue", value: model.selectedUploadQueueControl.waitingText, tone: model.uploadQueuePlatform.tone)
                    MetricTile(title: "Worker", value: model.selectedUploadQueueControl.workerRunning ? "Running" : "Idle", tone: model.selectedUploadQueueControl.workerRunning ? .green : .gray)
                    MetricTile(title: "Upload", value: model.selectedUploadQueueControl.enabled ? "Enabled" : "Disabled", tone: model.selectedUploadQueueControl.enabled ? .green : .red)
                    MetricTile(title: "Pause", value: model.selectedUploadQueueControl.paused ? "Paused" : "Live", tone: model.selectedUploadQueueControl.paused ? .orange : .green)
                }
                if !model.selectedUploadQueueControl.workerAction.isEmpty {
                    Text("Worker action: \(model.selectedUploadQueueControl.workerAction)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    SmallButton(title: model.selectedUploadQueueControl.enabled ? "Disable upload" : "Enable upload", symbol: model.selectedUploadQueueControl.enabled ? "power.circle" : "power.circle.fill") {
                        Task { await model.setUploadQueueControl(enabled: !model.selectedUploadQueueControl.enabled) }
                    }
                    SmallButton(title: model.selectedUploadQueueControl.paused ? "Resume upload" : "Pause upload", symbol: model.selectedUploadQueueControl.paused ? "play.fill" : "pause.fill") {
                        Task { await model.setUploadQueueControl(paused: !model.selectedUploadQueueControl.paused) }
                    }
                    SmallButton(title: "Refresh queue", symbol: "arrow.clockwise") {
                        Task { await model.refreshUploadQueue() }
                    }
                    if model.uploadQueuePlatform == .youtube {
                        SmallButton(title: "Sort episodes", symbol: "arrow.up.arrow.down") {
                            Task {
                                await model.runToolAction(title: "Sort YouTube queue", path: "/api/youtube/queue/sort", body: ["mode": "episode_asc"])
                                await model.refreshUploadQueue()
                            }
                        }
                    }
                }

                if model.uploadQueuePlatform == .youtube {
                    SmallButton(title: "Run YouTube watchdog", symbol: "shield.lefthalf.filled") {
                        Task { await model.runToolAction(title: "YouTube watchdog", path: "/api/youtube/watchdog/run-once") }
                    }
                }

                Text(model.uploadStatus)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if model.uploadRows.isEmpty {
                    EmptyState(text: "\(model.uploadQueuePlatform.label) queue is empty")
                }
                ForEach(model.uploadRows) { row in
                    UploadRowView(row: row) {
                        Task { await model.forceUploadQueueItem(row) }
                    }
                }
            }

            SectionCard(title: "Quick upload", symbol: "arrow.up.circle") {
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
                    SmallButton(title: "YouTube queue", symbol: "play.tv.fill") {
                        Task {
                            await model.selectUploadQueuePlatform(.youtube)
                        }
                    }
                }
            }

            SectionCard(title: "Sync & watchdog", symbol: "antenna.radiowaves.left.and.right") {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    SmallButton(title: "Drive sync", symbol: "arrow.triangle.2.circlepath") {
                        Task { await model.runToolAction(title: "Drive sync", path: "/api/gdrive/sync_projects_async") }
                    }
                    SmallButton(title: "Drive mass upload", symbol: "icloud.and.arrow.up") {
                        Task { await model.runToolAction(title: "Drive mass upload", path: "/api/gdrive/mass_upload_videos") }
                    }
                    SmallButton(title: "Douyin watchdog", symbol: "magnifyingglass.circle") {
                        Task { await model.runToolAction(title: "Douyin watchdog", path: "/api/douyin/watchdog/run-once") }
                    }
                    SmallButton(title: "Facebook status", symbol: "f.circle") {
                        Task { await model.runToolAction(title: "Facebook status", path: "/api/facebook/reels/status", method: "GET") }
                    }
                }
            }
        }
        .task {
            await model.refreshToolStatuses()
            await model.refreshUploadQueue()
            await model.refreshUploadQueueControls()
            if model.projects.isEmpty { await model.refreshProjects() }
        }
    }
}
