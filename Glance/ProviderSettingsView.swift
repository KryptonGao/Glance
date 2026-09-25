import SwiftUI

struct ProviderSettingsView: View {
    @State private var name = ""
    @State private var baseURL = ""
    @State private var modelID = ""
    @State private var apiKey = ""
    @State private var hasStoredKey = false
    @State private var searchEngine: SearchEngine = .google
    @State private var statusMessage: String?
    @State private var isTestingConnection = false

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $name, prompt: Text("OpenAI"))
                TextField("Base URL", text: $baseURL, prompt: Text("https://api.openai.com/v1"))
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                TextField("Model ID", text: $modelID, prompt: Text("gpt-4o"))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField(
                    hasStoredKey
                        ? String(localized: "API Key (saved)")
                        : String(localized: "API Key"),
                    text: $apiKey
                )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                if hasStoredKey || !apiKey.isEmpty {
                    Button("Clear API Key", role: .destructive) {
                        clearAPIKey()
                    }
                }

                Button {
                    Task {
                        await testConnection()
                    }
                } label: {
                    HStack {
                        if isTestingConnection {
                            ProgressView()
                        } else {
                            Image(systemName: "network")
                        }
                        Text(isTestingConnection ? "Testing Connection…" : "Test Connection")
                    }
                }
                .disabled(!canTestConnection || isTestingConnection)
            } header: {
                Text("Provider")
            } footer: {
                Text("Any OpenAI-compatible chat completions API. The key stays in the Keychain and is shared with the share extension.")
            }

            Section("Search") {
                Picker("Search engine", selection: $searchEngine) {
                    ForEach(SearchEngine.allCases) { engine in
                        Text(engine.title).tag(engine)
                    }
                }
            }

            if let statusMessage {
                Section {
                    Text(statusMessage)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("AI Provider")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    save()
                }
                .buttonStyle(.glassProminent)
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        let config = ProviderConfig.load()
        name = config.name
        baseURL = config.baseURL
        modelID = config.modelID
        searchEngine = config.searchEngine
        hasStoredKey = !(KeychainStore.readAPIKey() ?? "").isEmpty
    }

    private func save() {
        let config = ProviderConfig(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            baseURL: baseURL.trimmingCharacters(in: .whitespacesAndNewlines),
            modelID: modelID.trimmingCharacters(in: .whitespacesAndNewlines),
            searchEngine: searchEngine
        )
        do {
            try config.save()
        } catch {
            statusMessage = error.localizedDescription
            return
        }

        let typedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !typedKey.isEmpty {
            do {
                try KeychainStore.saveAPIKey(typedKey)
                apiKey = ""
                hasStoredKey = true
                statusMessage = String(localized: "Saved. The API key is in the Keychain.")
            } catch {
                statusMessage = error.localizedDescription
            }
            return
        }

        statusMessage = hasStoredKey
            ? String(localized: "Saved.")
            : String(localized: "Saved the provider. Add an API key before sharing.")
    }

    private var canTestConnection: Bool {
        !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (hasStoredKey || !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    @MainActor
    private func testConnection() async {
        let typedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = typedKey.isEmpty ? (KeychainStore.readAPIKey() ?? "") : typedKey
        guard !key.isEmpty else {
            statusMessage = String(localized: "Add an API key to test the connection.")
            return
        }

        isTestingConnection = true
        defer { isTestingConnection = false }

        let provider = OpenAICompatibleProvider(
            baseURL: baseURL.trimmingCharacters(in: .whitespacesAndNewlines),
            apiKey: key,
            modelID: modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        do {
            try await provider.testConnection()
            statusMessage = String(localized: "Connection successful.")
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func clearAPIKey() {
        do {
            try KeychainStore.deleteAPIKey()
            apiKey = ""
            hasStoredKey = false
            statusMessage = String(localized: "API key cleared.")
        } catch {
            statusMessage = error.localizedDescription
        }
    }
}
