import Foundation
import Security
import UIKit

nonisolated enum GlanceConstants {
    /// Must match the application-groups entitlement on both targets.
    static let appGroupID = "group.space.chenkai.glance"
    /// Earlier builds stored provider settings in this suite. It is not shared with the extension.
    static let legacyAppGroupID = "group.devplaceholder.jws6wo0x.Glance"
    static let providerFilename = "provider.json"
    static let keychainService = "devplaceholder.jws6wo0x.Glance"
    static let keychainAccount = "apiKey"
    /// Must match the keychain-access-groups entitlement. AppIdentifierPrefix is the development team ID.
    static let keychainAccessGroup = "D2G8858WRZ.devplaceholder.jws6wo0x.Glance"
}

nonisolated enum SearchEngine: String, Codable, CaseIterable, Identifiable, Sendable {
    case google
    case bing
    case duckduckgo

    var id: String { rawValue }

    var title: String {
        switch self {
        case .google: "Google"
        case .bing: "Bing"
        case .duckduckgo: "DuckDuckGo"
        }
    }

    func searchURL(for query: String) -> URL? {
        let base: String
        switch self {
        case .google: base = "https://www.google.com/search"
        case .bing: base = "https://www.bing.com/search"
        case .duckduckgo: base = "https://duckduckgo.com/"
        }
        guard var components = URLComponents(string: base) else { return nil }
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        return components.url
    }
}

nonisolated struct ProviderConfig: Codable, Equatable, Sendable {
    var name: String
    var baseURL: String
    var modelID: String
    var searchEngine: SearchEngine

    static let empty = ProviderConfig(name: "", baseURL: "", modelID: "", searchEngine: .google)

    var isReadyForRequests: Bool {
        !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !(KeychainStore.readAPIKey() ?? "").isEmpty
    }

    static func load() -> ProviderConfig {
        if let config = readSharedFile() {
            return config
        }
        if let legacy = readDefaults(suite: GlanceConstants.legacyAppGroupID), legacy.hasProviderFields {
            try? legacy.save()
            return legacy
        }
        return .empty
    }

    func save() throws {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: GlanceConstants.appGroupID
        ) else {
            throw GlanceStoreError.appGroupUnavailable
        }
        let data = try JSONEncoder().encode(self)
        let url = container.appendingPathComponent(GlanceConstants.providerFilename)
        try data.write(to: url, options: .atomic)
    }

    private var hasProviderFields: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func readSharedFile() -> ProviderConfig? {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: GlanceConstants.appGroupID
        ) else {
            return nil
        }
        let url = container.appendingPathComponent(GlanceConstants.providerFilename)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ProviderConfig.self, from: data)
    }

    private static func readDefaults(suite: String) -> ProviderConfig? {
        guard let defaults = UserDefaults(suiteName: suite),
              let data = defaults.data(forKey: "providerConfig") else {
            return nil
        }
        return try? JSONDecoder().decode(ProviderConfig.self, from: data)
    }
}

nonisolated enum KeychainStore {
    static func saveAPIKey(_ key: String) throws {
        let query = baseQuery()
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = Data(key.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw GlanceStoreError.keychain(status)
        }
    }

    static func readAPIKey() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func deleteAPIKey() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw GlanceStoreError.keychain(status)
        }
    }

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: GlanceConstants.keychainService,
            kSecAttrAccount as String: GlanceConstants.keychainAccount,
            kSecAttrAccessGroup as String: GlanceConstants.keychainAccessGroup,
        ]
    }
}

nonisolated struct GlanceRecord: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var createdAt: Date
    var analysis: GlanceAnalysis
    var areaAnalyses: [AreaAnalysis]

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt
        case analysis
        case areaAnalyses
    }

    init(id: UUID, createdAt: Date, analysis: GlanceAnalysis, areaAnalyses: [AreaAnalysis] = []) {
        self.id = id
        self.createdAt = createdAt
        self.analysis = analysis
        self.areaAnalyses = areaAnalyses
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        analysis = try container.decode(GlanceAnalysis.self, forKey: .analysis)
        areaAnalyses = try container.decodeIfPresent([AreaAnalysis].self, forKey: .areaAnalyses) ?? []
    }
}

nonisolated enum RecordStore {
    static func loadAll() -> [GlanceRecord] {
        guard let directory = try? recordsDirectory() else { return [] }
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? JSONDecoder().decode(GlanceRecord.self, from: data)
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    static func load(_ recordID: UUID) -> GlanceRecord? {
        guard let directory = try? recordsDirectory() else { return nil }
        let url = directory.appendingPathComponent("\(recordID.uuidString).json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(GlanceRecord.self, from: data)
    }

    static func save(imageJPEG: Data, analysis: GlanceAnalysis) throws -> GlanceRecord {
        let record = GlanceRecord(id: UUID(), createdAt: Date(), analysis: analysis)
        let directory = try recordsDirectory()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(record)
        try data.write(to: directory.appendingPathComponent("\(record.id.uuidString).json"), options: .atomic)
        try imageJPEG.write(to: directory.appendingPathComponent("\(record.id.uuidString).jpg"), options: .atomic)
        return record
    }

    static func addAreaAnalysis(_ areaAnalysis: AreaAnalysis, to recordID: UUID) throws {
        let directory = try recordsDirectory()
        let recordURL = directory.appendingPathComponent("\(recordID.uuidString).json")
        let data = try Data(contentsOf: recordURL)
        var record = try JSONDecoder().decode(GlanceRecord.self, from: data)
        record.areaAnalyses.append(areaAnalysis)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(record).write(to: recordURL, options: .atomic)
    }

    static func imageData(for record: GlanceRecord) -> Data? {
        guard let directory = try? recordsDirectory() else { return nil }
        return try? Data(contentsOf: directory.appendingPathComponent("\(record.id.uuidString).jpg"))
    }

    @MainActor
    static func image(for record: GlanceRecord) -> UIImage? {
        guard let data = imageData(for: record) else { return nil }
        return UIImage(data: data)
    }

    static func delete(_ record: GlanceRecord) {
        guard let directory = try? recordsDirectory() else { return }
        try? FileManager.default.removeItem(at: directory.appendingPathComponent("\(record.id.uuidString).json"))
        try? FileManager.default.removeItem(at: directory.appendingPathComponent("\(record.id.uuidString).jpg"))
    }

    private static func recordsDirectory() throws -> URL {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: GlanceConstants.appGroupID
        ) else {
            throw GlanceStoreError.appGroupUnavailable
        }
        let directory = container.appendingPathComponent("Records", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

nonisolated enum GlanceStoreError: LocalizedError {
    case appGroupUnavailable
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .appGroupUnavailable:
            String(localized: "Glance can't reach its shared App Group.")
        case .keychain(let status):
            String(localized: "The Keychain couldn't store the API key (\(Int(status))).")
        }
    }
}
