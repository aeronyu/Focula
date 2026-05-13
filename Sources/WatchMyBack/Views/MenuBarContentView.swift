import SwiftUI

struct MenuBarContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: model.lastFocusState.symbolName)
                    .foregroundStyle(model.lastFocusState.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.selectedGoal?.title ?? "Watch My Back")
                        .font(.headline)
                        .lineLimit(1)
                    Text(model.lastFocusState.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            Button {
                model.togglePaused()
            } label: {
                Label(model.settings.paused ? "Resume Tracking" : "Pause Tracking", systemImage: model.settings.paused ? "play.fill" : "pause.fill")
            }

            Button {
                Task { await model.sampleNow(manual: true) }
            } label: {
                Label("Sample Now", systemImage: "camera.metering.matrix")
            }
            .disabled(model.isSampling)

            Text(model.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .padding(16)
        .frame(width: 300, alignment: .leading)
    }
}
