import Foundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let root = ShareRootView(context: extensionContext) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
        }
        let host = UIHostingController(rootView: root)
        host.view.backgroundColor = .systemBackground
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)
    }
}

struct ShareRootView: View {
    let context: NSExtensionContext?
    var onDone: () -> Void

    @State private var image: UIImage?
    @State private var loadError: String?
    @State private var searchURLToCopy: URL?
    @State private var didStart = false

    var body: some View {
        NavigationStack {
            Group {
                if let image {
                    ShareAnalysisView(image: image) { url in
                        openSearchURL(url)
                    }
                } else if let loadError {
                    ContentUnavailableView(
                        "Nothing to analyze",
                        systemImage: "photo",
                        description: Text(loadError)
                    )
                } else {
                    ProgressView("Analyzing…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Glance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDone)
                }
            }
        }
        .alert(
            "The Browser Can't Open Here",
            isPresented: Binding(
                get: { searchURLToCopy != nil },
                set: { isPresented in
                    if !isPresented {
                        searchURLToCopy = nil
                    }
                }
            )
        ) {
            Button("Copy Search Link") {
                if let searchURLToCopy {
                    UIPasteboard.general.url = searchURLToCopy
                }
                searchURLToCopy = nil
            }
            Button("OK", role: .cancel) {
                searchURLToCopy = nil
            }
        } message: {
            Text("iOS doesn't allow a Share Extension to open another app. Copy the search link and paste it into your browser. If the screenshot was saved, you can also open it from Glance's History and tap Search.")
        }
        .task {
            guard !didStart else { return }
            didStart = true
            await loadImage()
        }
    }

    private func openSearchURL(_ url: URL) {
        guard let context else {
            searchURLToCopy = url
            return
        }

        context.open(url) { opened in
            guard !opened else { return }
            Task { @MainActor in
                searchURLToCopy = url
            }
        }
    }

    private func loadImage() async {
        do {
            let data = try await sharedImageData(from: context)
            guard let image = UIImage(data: data) else {
                throw ShareLoadError.unreadable
            }
            self.image = image
        } catch {
            loadError = error.localizedDescription
        }
    }
}

private enum ShareLoadError: LocalizedError {
    case empty
    case notAnImage
    case unreadable

    var errorDescription: String? {
        switch self {
        case .empty:
            String(localized: "Glance didn't receive an image.")
        case .notAnImage:
            String(localized: "Share one screenshot at a time.")
        case .unreadable:
            String(localized: "Glance couldn't read this image.")
        }
    }
}

private func sharedImageData(from context: NSExtensionContext?) async throws -> Data {
    guard let item = context?.inputItems.first as? NSExtensionItem,
          let providers = item.attachments,
          providers.count == 1,
          let provider = providers.first else {
        throw ShareLoadError.empty
    }

    let types = [UTType.jpeg, .heic, .png, .image].map(\.identifier)
    guard let type = types.first(where: { provider.hasItemConformingToTypeIdentifier($0) }) else {
        throw ShareLoadError.notAnImage
    }

    if let data = try? await loadDataRepresentation(from: provider, type: type), !data.isEmpty {
        return data
    }

    let loaded = try await loadItem(from: provider, type: type)
    if let data = loaded as? Data, !data.isEmpty {
        return data
    }
    if let image = loaded as? UIImage, let data = image.jpegData(compressionQuality: 0.9) {
        return data
    }
    if let url = loaded as? URL {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        let data = try Data(contentsOf: url)
        if !data.isEmpty {
            return data
        }
    }
    throw ShareLoadError.unreadable
}

private func loadDataRepresentation(from provider: NSItemProvider, type: String) async throws -> Data {
    try await withCheckedThrowingContinuation { continuation in
        provider.loadDataRepresentation(forTypeIdentifier: type) { data, error in
            if let data {
                continuation.resume(returning: data)
            } else {
                continuation.resume(throwing: error ?? ShareLoadError.unreadable)
            }
        }
    }
}

private func loadItem(from provider: NSItemProvider, type: String) async throws -> Any? {
    try await withCheckedThrowingContinuation { continuation in
        provider.loadItem(forTypeIdentifier: type, options: nil) { item, error in
            if let error, item == nil {
                continuation.resume(throwing: error)
            } else {
                continuation.resume(returning: item)
            }
        }
    }
}
