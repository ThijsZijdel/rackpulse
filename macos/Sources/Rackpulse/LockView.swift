import SwiftUI

struct LockView: View {
    let unlock: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.fill")
                .font(.system(size: 28))
                .foregroundStyle(Theme.secondary)
            Text("Rackpulse is locked")
                .font(.system(size: 15, weight: .semibold))
            Text("Unlock with Touch ID or your password to see your servers.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondary)
                .multilineTextAlignment(.center)
            Button("Unlock", action: unlock)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .padding(.horizontal, 24)
    }
}
