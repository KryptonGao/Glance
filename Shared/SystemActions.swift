import EventKit
import Foundation

enum EventActions {
    static func calendarStatus() -> EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .event)
    }

    static func reminderStatus() -> EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .reminder)
    }

    /// A draft for the system event editor. The calendar stays unset so Calendar uses the default from Settings.
    static func makeDraft(_ action: CalendarAction, store: EKEventStore) -> EKEvent {
        let event = EKEvent(eventStore: store)
        event.title = action.title.nilIfBlank ?? String(localized: "Event")
        event.notes = action.notes
        event.location = action.location

        let start = GlanceDateParser.date(from: action.start) ?? Date()
        if action.isDateOnly {
            var dayCalendar = Calendar(identifier: .gregorian)
            dayCalendar.timeZone = .current
            let startDay = dayCalendar.startOfDay(for: start)
            let parsedEnd = GlanceDateParser.date(from: action.end).map { dayCalendar.startOfDay(for: $0) }
            let endDay = (parsedEnd != nil && parsedEnd! > startDay)
                ? parsedEnd!
                : (dayCalendar.date(byAdding: .day, value: 1, to: startDay) ?? startDay.addingTimeInterval(86_400))
            event.isAllDay = true
            event.startDate = startDay
            event.endDate = endDay
        } else {
            event.timeZone = .current
            event.startDate = start
            let end = GlanceDateParser.date(from: action.end) ?? start.addingTimeInterval(3600)
            event.endDate = end > start ? end : start.addingTimeInterval(3600)
        }
        return event
    }

    static func addReminder(_ action: ReminderAction) async throws {
        try await requireFullAccess(status: reminderStatus(), request: { store in
            try await store.requestFullAccessToReminders()
        }, denied: .reminderDenied)

        let store = EKEventStore()
        guard let calendar = store.defaultCalendarForNewReminders() else {
            throw ActionError.noReminderList
        }
        let reminder = EKReminder(eventStore: store)
        reminder.calendar = calendar
        reminder.title = action.title
        reminder.notes = action.notes
        if let due = GlanceDateParser.date(from: action.due) {
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: due
            )
        }
        do {
            try store.save(reminder, commit: true)
        } catch {
            throw ActionError.saveFailed(error.localizedDescription)
        }
    }

    private static func requireFullAccess(
        status: EKAuthorizationStatus,
        request: (EKEventStore) async throws -> Bool,
        denied: ActionError
    ) async throws {
        switch status {
        case .fullAccess:
            return
        case .notDetermined:
            let granted = try await request(EKEventStore())
            guard granted else { throw denied }
        default:
            throw denied
        }
    }
}

enum ActionError: LocalizedError {
    case reminderDenied
    case noReminderList
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .reminderDenied:
            String(localized: "Allow Reminders access in Permissions, then try again.")
        case .noReminderList:
            String(localized: "No reminder list is available.")
        case .saveFailed(let message):
            message
        }
    }
}

extension EKAuthorizationStatus {
    var glanceCanWrite: Bool {
        switch self {
        case .fullAccess, .writeOnly:
            true
        default:
            false
        }
    }

    var glanceLabel: String {
        switch self {
        case .fullAccess, .writeOnly:
            String(localized: "Allowed")
        case .denied:
            String(localized: "Denied")
        case .restricted:
            String(localized: "Restricted")
        case .notDetermined:
            String(localized: "Not asked")
        @unknown default:
            String(localized: "Unknown")
        }
    }
}
