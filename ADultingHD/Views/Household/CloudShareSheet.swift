import SwiftUI
import CloudKit
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// SwiftUI wrapper around Apple's native CloudKit share sheet.
///
/// On iOS wraps `UICloudSharingController` — Apple's built-in share sheet
/// with contact picking (email/phone), Messages/Mail integration, and
/// automatic handling of accept-on-receiving-device.
///
/// On macOS falls back to an inline URL view with a Copy button — the
/// macOS NSSharingService CloudKit path requires a lot of AppKit plumbing
/// that's not worth the complexity for the current usage pattern.
struct CloudShareSheet: View {
    let share: CKShare
    let container: CKContainer
    let householdName: String
    let onDismiss: () -> Void

    var body: some View {
        #if os(iOS)
        CloudShareSheetIOS(share: share, container: container, householdName: householdName, onDismiss: onDismiss)
            .ignoresSafeArea()
        #else
        MacInviteFallback(share: share, householdName: householdName, onDismiss: onDismiss)
        #endif
    }
}

#if os(iOS)

private struct CloudShareSheetIOS: UIViewControllerRepresentable {
    let share: CKShare
    let container: CKContainer
    let householdName: String
    let onDismiss: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(householdName: householdName, onDismiss: onDismiss)
    }

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: container)
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {}

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        let householdName: String
        let onDismiss: () -> Void

        init(householdName: String, onDismiss: @escaping () -> Void) {
            self.householdName = householdName
            self.onDismiss = onDismiss
        }

        func itemTitle(for csc: UICloudSharingController) -> String? {
            householdName
        }

        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {}

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            onDismiss()
        }

        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
            onDismiss()
        }
    }
}

#else

/// Minimal macOS fallback — shows the CKShare URL with a Copy button.
/// Good enough until someone needs the full NSSharingService contact picker.
private struct MacInviteFallback: View {
    let share: CKShare
    let householdName: String
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Label("Invite to \(householdName)", systemImage: "person.crop.circle.badge.plus")
                .font(.headline)
            if let url = share.url {
                Text(url.absoluteString)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .multilineTextAlignment(.center)
                    .padding()
                    .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url.absoluteString, forType: .string)
                } label: {
                    Label("Copy Link", systemImage: "doc.on.doc")
                }
            } else {
                Text("Share URL unavailable").foregroundStyle(.secondary)
            }
            Button("Done") { onDismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding()
        .frame(minWidth: 420, minHeight: 240)
    }
}

#endif
