import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section("Local vision endpoint") {
                TextField(
                    "Endpoint",
                    text: Binding(
                        get: { model.endpointString },
                        set: { model.updateEndpoint($0) }
                    )
                )

                TextField(
                    "Model",
                    text: Binding(
                        get: { model.settings.model },
                        set: { model.updateModelName($0) }
                    )
                )

                Text("OpenAI-compatible vision endpoint. Screenshots are sent only to this local URL and then discarded.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Sampling") {
                Stepper(
                    value: Binding(
                        get: { model.settings.sampleIntervalSeconds },
                        set: { model.updateSampleInterval($0) }
                    ),
                    in: 15...300,
                    step: 15
                ) {
                    Text("Every \(Int(model.settings.sampleIntervalSeconds)) seconds")
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
