import SwiftUI
import CloudKit
#if os(iOS)
import UIKit
#else
import AppKit
#endif

struct HouseholdShareSheetPayload: Identifiable {
    let id = UUID()
    let share: CKShare
    let container: CKContainer
    let householdName: String
}

/// CloudKit's diagnostic strings can contain record IDs, schema internals,
/// and a copy of the same failure for every task in the household. Keep those
/// details in the sync logs and give people one short, actionable message.
func householdShareErrorMessage(for error: Error) -> String {
    if let syncError = error as? CloudKitSyncError,
       case .iCloudUnavailable = syncError {
        return "iCloud isn’t available. Check that you’re signed in and try again."
    }
    return "We couldn’t prepare the invite. Please try again later."
}

/// Shared preparation state for every place that presents a household invite.
/// Keeping CloudKit loading, payload construction, and errors here prevents
/// onboarding and Settings from implementing subtly different invite flows.
@Observable
@MainActor
final class HouseholdSharePresentation {
    enum Phase {
        case idle
        case preparing(UUID)
        case ready(HouseholdShareSheetPayload)
        case failed(String)
    }

    private(set) var phase: Phase = .idle

    var isPreparing: Bool {
        if case .preparing = phase { return true }
        return false
    }

    var errorMessage: String? {
        guard case .failed(let message) = phase else { return nil }
        return message
    }

    var payloadBinding: Binding<HouseholdShareSheetPayload?> {
        Binding(
            get: {
                guard case .ready(let payload) = self.phase else { return nil }
                return payload
            },
            set: { payload in
                if let payload {
                    self.phase = .ready(payload)
                } else {
                    self.dismiss()
                }
            }
        )
    }

    func prepare(using dataStore: DataStore) async {
        let preparationID = UUID()
        phase = .preparing(preparationID)
        do {
            let prepared = try await dataStore.prepareHouseholdShare()
            guard case .preparing(let activeID) = phase, activeID == preparationID else { return }
            phase = .ready(HouseholdShareSheetPayload(
                share: prepared.share,
                container: prepared.container,
                householdName: prepared.householdName
            ))
        } catch {
            guard case .preparing(let activeID) = phase, activeID == preparationID else { return }
            phase = .failed(householdShareErrorMessage(for: error))
        }
    }

    func dismiss() {
        phase = .idle
    }
}

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
    /// Fired the moment the share is successfully saved to CloudKit — i.e. an
    /// invite has actually gone out. Distinct from `onDismiss` because the
    /// sheet often stays open after this (e.g. while Messages composes), and
    /// callers need to know "an invite was sent" independent of "the sheet
    /// closed" so onboarding can update its UI without waiting on a dismissal
    /// that may never trigger the same delegate callback.
    var onShareSaved: () -> Void = {}
    /// Fired when sharing is stopped or fails before the presentation
    /// dismissal callback, so a prior save cannot be treated as successful.
    var onShareInvalidated: () -> Void = {}
    let onDismiss: () -> Void

    var body: some View {
        #if os(iOS)
        CloudShareSheetIOS(
            share: share, container: container, householdName: householdName,
            onShareSaved: onShareSaved, onShareInvalidated: onShareInvalidated,
            onDismiss: onDismiss
        )
        .ignoresSafeArea()
        #else
        MacInviteFallback(share: share, householdName: householdName, onShareSaved: onShareSaved, onDismiss: onDismiss)
        #endif
    }
}

#if os(iOS)

private struct CloudShareSheetIOS: UIViewControllerRepresentable {
    let share: CKShare
    let container: CKContainer
    let householdName: String
    let onShareSaved: () -> Void
    let onShareInvalidated: () -> Void
    let onDismiss: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            householdName: householdName,
            onShareSaved: onShareSaved,
            onShareInvalidated: onShareInvalidated,
            onDismiss: onDismiss
        )
    }

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: container)
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {}

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        let householdName: String
        let onShareSaved: () -> Void
        let onShareInvalidated: () -> Void
        let onDismiss: () -> Void

        init(
            householdName: String,
            onShareSaved: @escaping () -> Void,
            onShareInvalidated: @escaping () -> Void,
            onDismiss: @escaping () -> Void
        ) {
            self.householdName = householdName
            self.onShareSaved = onShareSaved
            self.onShareInvalidated = onShareInvalidated
            self.onDismiss = onDismiss
        }

        func itemTitle(for csc: UICloudSharingController) -> String? {
            "Join \"\(householdName)\" on ADultingHD"
        }

        func itemThumbnailData(for csc: UICloudSharingController) -> Data? {
            // Without a thumbnail, Messages/Mail render the invite as a bare
            // link with no image — easy to mistake for spam. Attaching the
            // app icon gives the preview card a recognizable source.
            Self.appIconThumbnailData
        }

        // UIKit calls itemThumbnailData(for:) repeatedly while the share
        // sheet is on screen (e.g. once per activity the user scrolls past).
        // The app icon never changes for the process lifetime, so decode and
        // PNG-encode it once instead of repeating that work on every call.
        private static let appIconThumbnailData: Data? = {
            guard
                let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
                let primaryIcons = icons["CFBundlePrimaryIcon"] as? [String: Any],
                let iconFiles = primaryIcons["CFBundleIconFiles"] as? [String],
                let iconName = iconFiles.last
            else { return nil }
            return UIImage(named: iconName)?.pngData()
        }()

        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
            onShareSaved()
        }

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            onShareInvalidated()
            onDismiss()
        }

        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
            onShareInvalidated()
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
    let onShareSaved: () -> Void
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
                    .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: Theme.chipCornerRadius))
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url.absoluteString, forType: .string)
                    // macOS has no Messages/Mail hand-off to confirm a send,
                    // so treat "copied the link" as the closest equivalent to
                    // iOS's cloudSharingControllerDidSaveShare — it's the
                    // point the user has actually taken action to share it,
                    // not just the point the sheet happened to render.
                    onShareSaved()
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
