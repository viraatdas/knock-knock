import SwiftUI
import MessageUI

/// Presents the SMS invite pre-filled with `InviteMessage.body`. Uses
/// `MFMessageComposeViewController` when the device can send texts, otherwise
/// falls back to a share sheet so the user can send the same text elsewhere.
struct InviteComposer: UIViewControllerRepresentable {
    let phone: String
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(dismiss: dismiss) }

    func makeUIViewController(context: Context) -> UIViewController {
        if MFMessageComposeViewController.canSendText() {
            let composer = MFMessageComposeViewController()
            composer.recipients = [phone]
            composer.body = InviteMessage.body
            composer.messageComposeDelegate = context.coordinator
            return composer
        } else {
            // Share-sheet fallback (e.g. iPad / iOS Simulator without Messages).
            let activity = UIActivityViewController(
                activityItems: [InviteMessage.body], applicationActivities: nil
            )
            activity.completionWithItemsHandler = { _, _, _, _ in context.coordinator.finish() }
            return activity
        }
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        private let dismiss: DismissAction
        init(dismiss: DismissAction) { self.dismiss = dismiss }

        func messageComposeViewController(_ controller: MFMessageComposeViewController,
                                          didFinishWith result: MessageComposeResult) {
            finish()
        }

        func finish() { dismiss() }
    }
}
