import EventKit
import EventKitUI
import SwiftUI

/// Presents the system Calendar editor. Calendar saves the event itself; Glance does not write EventKit.
struct SystemEventEditor: UIViewControllerRepresentable {
    let action: CalendarAction
    let onComplete: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete)
    }

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let store = EKEventStore()
        let controller = EKEventEditViewController()
        controller.eventStore = store
        controller.event = EventActions.makeDraft(action, store: store)
        controller.editViewDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: EKEventEditViewController, context: Context) {
        context.coordinator.onComplete = onComplete
    }

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        var onComplete: (Bool) -> Void

        init(onComplete: @escaping (Bool) -> Void) {
            self.onComplete = onComplete
        }

        func eventEditViewController(
            _ controller: EKEventEditViewController,
            didCompleteWith action: EKEventEditViewAction
        ) {
            let saved = action == .saved
            let finish = onComplete
            controller.dismiss(animated: true) {
                finish(saved)
            }
        }
    }
}
