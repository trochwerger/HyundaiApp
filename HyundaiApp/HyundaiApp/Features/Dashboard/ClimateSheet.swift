import SwiftUI

/// Bottom sheet with remote climate options. Sending a command dismisses the
/// sheet; progress and the result appear in the dashboard's banner.
struct ClimateSheet: View {
    @ObservedObject var controls: ControlsViewModel
    let send: (ControlsViewModel.Command) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Label("Temperature", systemImage: "thermometer.medium")
                        Spacer()
                        Text("\(Int(controls.startTemp)) °C")
                            .font(.title3.weight(.semibold))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                    }
                    Slider(value: $controls.startTemp, in: 17...27, step: 1) {
                        Text("Temperature")
                    } minimumValueLabel: {
                        Text("17°").font(.caption)
                    } maximumValueLabel: {
                        Text("27°").font(.caption)
                    }

                    Stepper(value: $controls.startDuration, in: 1...30) {
                        Label("Run for \(controls.startDuration) min", systemImage: "timer")
                    }

                    Toggle(isOn: $controls.defrost) {
                        Label("Defrost", systemImage: "windshield.front.and.heat.waves")
                    }
                } footer: {
                    Text("Remote start wakes the car. If it fails, nothing is retried automatically.")
                }

                Section {
                    Button {
                        send(.startClimate)
                        dismiss()
                    } label: {
                        Label("Start climate", systemImage: "fan.fill")
                            .frame(maxWidth: .infinity)
                            .font(.headline)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(.green)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())

                    Button(role: .destructive) {
                        send(.stopClimate)
                        dismiss()
                    } label: {
                        Label("Stop climate", systemImage: "stop.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 0, trailing: 0))
                }
                .disabled(controls.busy != nil)
            }
            .navigationTitle("Climate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
