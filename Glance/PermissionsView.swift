import EventKit
import SwiftUI
import UIKit

struct PermissionsView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var calendarStatus = EventActions.calendarStatus()
    @State private var reminderStatus = EventActions.reminderStatus()
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                LabeledContent("Calendar", value: calendarStatus.glanceLabel)
                permissionButton(
                    isAllowed: calendarStatus.glanceCanWrite,
                    needsSettings: calendarStatus == .denied || calendarStatus == .restricted,
                    title: "Allow Calendar Access"
                ) {
                    await allowCalendar()
                }
            } footer: {
                Text("Glance adds an event only after you tap Add.")
            }

            Section {
                LabeledContent("Reminders", value: reminderStatus.glanceLabel)
                permissionButton(
                    isAllowed: reminderStatus.glanceCanWrite,
                    needsSettings: reminderStatus == .denied || reminderStatus == .restricted,
                    title: "Allow Reminders Access"
                ) {
                    await allowReminders()
                }
            } footer: {
                Text("Glance adds a reminder only after you tap Add.")
            }

            if let message {
                Section {
                    Text(message)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Permissions")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: refresh)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                refresh()
            }
        }
    }

    @ViewBuilder
    private func permissionButton(
        isAllowed: Bool,
        needsSettings: Bool,
        title: LocalizedStringKey,
        action: @escaping () async -> Void
    ) -> some View {
        if needsSettings {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            }
        } else {
            Button(title) {
                Task { await action() }
            }
            .disabled(isAllowed)
        }
    }

    private func refresh() {
        calendarStatus = EventActions.calendarStatus()
        reminderStatus = EventActions.reminderStatus()
    }

    private func allowCalendar() async {
        do {
            let granted = try await EKEventStore().requestWriteOnlyAccessToEvents()
            message = granted
                ? String(localized: "Calendar access is on.")
                : String(localized: "Calendar access was not granted.")
        } catch {
            message = error.localizedDescription
        }
        refresh()
    }

    private func allowReminders() async {
        do {
            let granted = try await EKEventStore().requestFullAccessToReminders()
            message = granted
                ? String(localized: "Reminders access is on.")
                : String(localized: "Reminders access was not granted.")
        } catch {
            message = error.localizedDescription
        }
        refresh()
    }
}
