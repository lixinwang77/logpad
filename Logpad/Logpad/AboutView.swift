import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)

            Text(AppVersion.appName)
                .font(.title2.bold())

            Text(AppVersion.aboutVersionString)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(i18n.str("aboutDescription"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)

            Button(i18n.str("OK")) {
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .padding(.top, 4)
        }
        .padding(24)
        .frame(width: 320)
    }
}
