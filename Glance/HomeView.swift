import SwiftUI
import UIKit
import PhotosUI

struct HomeView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var records: [GlanceRecord] = []
    @State private var isConfigured = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var isLoadingPhoto = false
    @State private var isShowingPhotoAnalysis = false
    @State private var photoLoadError: String?
    @State private var isShowingPhotoLoadError = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Turn screenshots into actions.")
                            .font(.title2)
                        Text("Choose a screenshot from your photo library or share one to Glance. It reads the image and suggests what to do next.")
                            .font(.body)
                            .foregroundStyle(.secondary)

                        PhotosPicker(selection: $selectedPhoto, matching: .screenshots) {
                            Label(
                                isLoadingPhoto ? "Loading photo…" : "Choose a screenshot to analyze",
                                systemImage: isLoadingPhoto ? "hourglass" : "photo.on.rectangle.angled"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isLoadingPhoto)
                        .onChange(of: selectedPhoto) { _, item in
                            guard let item else { return }
                            Task { await loadPhoto(from: item) }
                        }
                    }
                    .padding(.vertical, 20)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }

                Section("How it works") {
                    Label("Take a screenshot", systemImage: "camera.viewfinder")
                    Label("Choose it here or share it to Glance", systemImage: "photo.on.rectangle.angled")
                    Label("Confirm a search, event, or reminder", systemImage: "checkmark.circle")
                }

                if !isConfigured {
                    Section {
                        NavigationLink {
                            ProviderSettingsView()
                        } label: {
                            Label("Add an AI provider", systemImage: "key")
                        }
                    } footer: {
                        Text("Glance uses your own API key. Nothing is built in.")
                    }
                }

                Section {
                    if records.isEmpty {
                        Text("Choose a screenshot above or share one to Glance to see it here.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(records.prefix(3))) { record in
                            NavigationLink {
                                HistoryDetailView(record: record)
                            } label: {
                                RecordRow(record: record)
                            }
                        }
                        NavigationLink("History") {
                            HistoryView()
                        }
                    }
                } header: {
                    Text("Recent")
                }
            }
            .navigationTitle("Glance")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        PermissionsView()
                    } label: {
                        Image(systemName: "lock.shield")
                    }
                    .accessibilityLabel(Text("Permissions"))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        ProviderSettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel(Text("AI Provider"))
                }
            }
            .onAppear(perform: reload)
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    reload()
                }
            }
            .sheet(isPresented: $isShowingPhotoAnalysis, onDismiss: {
                selectedImage = nil
                reload()
            }) {
                NavigationStack {
                    if let selectedImage {
                        ShareAnalysisView(image: selectedImage) { url in
                            openURL(url)
                        }
                        .navigationTitle("Screenshot")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") {
                                    isShowingPhotoAnalysis = false
                                }
                            }
                        }
                    } else {
                        ProgressView("Loading photo…")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .presentationDragIndicator(.visible)
            }
            .alert("Couldn't load photo", isPresented: $isShowingPhotoLoadError) {
                Button("OK", role: .cancel) {
                    photoLoadError = nil
                }
            } message: {
                Text(photoLoadError ?? "Glance couldn't read this photo.")
            }
        }
    }

    @MainActor
    private func loadPhoto(from item: PhotosPickerItem) async {
        isLoadingPhoto = true
        defer {
            isLoadingPhoto = false
            selectedPhoto = nil
        }

        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                photoLoadError = "Glance couldn't read this photo."
                isShowingPhotoLoadError = true
                return
            }
            selectedImage = image
            isShowingPhotoAnalysis = true
        } catch {
            photoLoadError = error.localizedDescription
            isShowingPhotoLoadError = true
        }
    }

    private func reload() {
        records = RecordStore.loadAll()
        isConfigured = ProviderConfig.load().isReadyForRequests
    }
}

struct RecordRow: View {
    let record: GlanceRecord

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            thumbnail
            VStack(alignment: .leading, spacing: 4) {
                Group {
                    if record.analysis.summary.isEmpty {
                        Text("Screenshot")
                    } else {
                        Text(record.analysis.summary)
                    }
                }
                .lineLimit(2)
                .foregroundStyle(.primary)
                Text(record.createdAt, format: .relative(presentation: .named))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let image = RecordStore.image(for: record) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)
        } else {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.quaternary)
                .frame(width: 56, height: 56)
                .overlay {
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                }
                .accessibilityHidden(true)
        }
    }
}

#Preview {
    HomeView()
}
