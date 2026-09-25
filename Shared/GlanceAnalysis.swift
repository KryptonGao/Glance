import Foundation

nonisolated struct GlanceAnalysis: Codable, Hashable, Sendable {
    var summary: String
    var searches: [SearchAction]
    var events: [CalendarAction]
    var reminders: [ReminderAction]

    enum CodingKeys: String, CodingKey {
        case summary
        case searches
        case events
        case reminders
    }

    init(
        summary: String,
        searches: [SearchAction],
        events: [CalendarAction],
        reminders: [ReminderAction]
    ) {
        self.summary = summary
        self.searches = searches
        self.events = events
        self.reminders = reminders
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        summary = try container.decodeIfPresent(String.self, forKey: .summary)?.nilIfBlank ?? ""
        searches = try container.decodeIfPresent([SearchAction].self, forKey: .searches) ?? []
        events = try container.decodeIfPresent([CalendarAction].self, forKey: .events) ?? []
        reminders = try container.decodeIfPresent([ReminderAction].self, forKey: .reminders) ?? []
        searches = searches.filter { !$0.title.isEmpty || !$0.query.isEmpty }
        events = events.filter { !$0.title.isEmpty }
        reminders = reminders.filter { !$0.title.isEmpty }
    }
}

nonisolated struct AreaAnalysis: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var createdAt: Date
    var outline: [NormalizedPoint]
    var analysis: GlanceAnalysis

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        outline: [NormalizedPoint],
        analysis: GlanceAnalysis
    ) {
        self.id = id
        self.createdAt = createdAt
        self.outline = outline
        self.analysis = analysis
    }
}

nonisolated struct SearchAction: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var title: String
    var query: String

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case query
    }

    init(id: UUID = UUID(), title: String, query: String) {
        self.id = id
        self.title = title
        self.query = query
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        let decodedTitle = try container.decodeIfPresent(String.self, forKey: .title)?.nilIfBlank ?? ""
        let decodedQuery = try container.decodeIfPresent(String.self, forKey: .query)?.nilIfBlank ?? ""
        title = decodedTitle.isEmpty ? decodedQuery : decodedTitle
        query = decodedQuery.isEmpty ? decodedTitle : decodedQuery
    }
}

nonisolated struct CalendarAction: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var title: String
    var start: String?
    var end: String?
    var notes: String?
    var location: String?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case start
        case end
        case notes
        case location
    }

    init(
        id: UUID = UUID(),
        title: String,
        start: String? = nil,
        end: String? = nil,
        notes: String? = nil,
        location: String? = nil
    ) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.notes = notes
        self.location = location
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try container.decodeIfPresent(String.self, forKey: .title)?.nilIfBlank ?? ""
        start = try container.decodeIfPresent(String.self, forKey: .start)?.nilIfBlank
        end = try container.decodeIfPresent(String.self, forKey: .end)?.nilIfBlank
        notes = try container.decodeIfPresent(String.self, forKey: .notes)?.nilIfBlank
        location = try container.decodeIfPresent(String.self, forKey: .location)?.nilIfBlank
    }

    var isDateOnly: Bool {
        guard let start else { return false }
        return !start.contains("T") && !start.contains(":")
    }

    var detailText: String? {
        var parts: [String] = []
        if let startDate = GlanceDateParser.date(from: start) {
            if isDateOnly {
                parts.append(startDate.formatted(date: .abbreviated, time: .omitted))
            } else if let endDate = GlanceDateParser.date(from: end) {
                let startText = startDate.formatted(date: .abbreviated, time: .shortened)
                let endText = endDate.formatted(date: .omitted, time: .shortened)
                parts.append("\(startText) – \(endText)")
            } else {
                parts.append(startDate.formatted(date: .abbreviated, time: .shortened))
            }
        }
        if let location {
            parts.append(location)
        }
        if parts.isEmpty {
            return notes
        }
        return parts.joined(separator: " · ")
    }
}

nonisolated struct ReminderAction: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var title: String
    var due: String?
    var notes: String?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case due
        case notes
    }

    init(id: UUID = UUID(), title: String, due: String? = nil, notes: String? = nil) {
        self.id = id
        self.title = title
        self.due = due
        self.notes = notes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try container.decodeIfPresent(String.self, forKey: .title)?.nilIfBlank ?? ""
        due = try container.decodeIfPresent(String.self, forKey: .due)?.nilIfBlank
        notes = try container.decodeIfPresent(String.self, forKey: .notes)?.nilIfBlank
    }

    var detailText: String? {
        if let dueDate = GlanceDateParser.date(from: due) {
            return dueDate.formatted(date: .abbreviated, time: .shortened)
        }
        return notes
    }
}

nonisolated enum GlanceDateParser {
    static func date(from string: String?) -> Date? {
        guard let string = string?.nilIfBlank else { return nil }

        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: string) {
            return date
        }

        let internet = ISO8601DateFormatter()
        internet.formatOptions = [.withInternetDateTime]
        if let date = internet.date(from: string) {
            return date
        }

        let day = DateFormatter()
        day.calendar = Calendar(identifier: .gregorian)
        day.locale = Locale(identifier: "en_US_POSIX")
        day.timeZone = .current
        day.dateFormat = "yyyy-MM-dd"
        return day.date(from: string)
    }
}

nonisolated extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.compare("null", options: .caseInsensitive) == .orderedSame {
            return nil
        }
        return trimmed
    }
}
