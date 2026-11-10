import ActivityKit
import SwiftUI
import WidgetKit

/// Lock Screen and Dynamic Island presentation of a remote start.
///
/// Battery-safety rules: this extension makes no network requests and sends
/// no vehicle commands. The countdown uses system timer views that tick on
/// the device; Stop opens the app, which asks for confirmation.
struct RemoteStartLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RemoteStartActivityAttributes.self) { context in
            LockScreenView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.35))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.attributes.vehicleName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(phaseHeadline(context.state, temperature: context.attributes.targetTemperature))
                            .font(.headline)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Countdown(state: context.state)
                        .font(.title.weight(.bold))
                        .foregroundStyle(.green)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 10) {
                        Progress(state: context.state)
                        if phaseIsActive(context.state) {
                            Link(destination: RemoteStartActivityAttributes.stopURL) {
                                Text("Stop remote start")
                                    .font(.subheadline.weight(.bold))
                                    .frame(maxWidth: .infinity, minHeight: 40)
                                    .background(Color.red.opacity(0.25), in: .capsule)
                                    .foregroundStyle(Color(red: 1, green: 0.7, blue: 0.62))
                            }
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: phaseSymbol(context.state))
                    .foregroundStyle(phaseTint(context.state))
            } compactTrailing: {
                Countdown(state: context.state)
                    .foregroundStyle(.green)
                    .frame(maxWidth: 52)
            } minimal: {
                Image(systemName: phaseSymbol(context.state))
                    .foregroundStyle(phaseTint(context.state))
            }
            .widgetURL(URL(string: "hyundaiapp://car"))
        }
    }
}

private struct LockScreenView: View {
    let context: ActivityViewContext<RemoteStartActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: phaseSymbol(context.state))
                    .font(.title3)
                    .foregroundStyle(phaseTint(context.state))
                    .frame(width: 42, height: 42)
                    .background(phaseTint(context.state).opacity(0.2), in: .rect(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(context.attributes.vehicleName) · \(phaseHeadline(context.state, temperature: nil))")
                        .font(.headline)
                    Text(phaseDetail(context.state, temperature: context.attributes.targetTemperature))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Countdown(state: context.state)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.green)
            }

            Progress(state: context.state)

            if phaseIsActive(context.state) {
                HStack {
                    Spacer()
                    Link(destination: RemoteStartActivityAttributes.stopURL) {
                        Text("Stop")
                            .font(.subheadline.weight(.bold))
                            .padding(.horizontal, 18)
                            .frame(minHeight: 40)
                            .background(Color.red.opacity(0.25), in: .capsule)
                    }
                }
            }
        }
        .padding(16)
    }
}

/// On-device countdown; renders nothing outside the running phase.
private struct Countdown: View {
    let state: RemoteStartActivityAttributes.ContentState

    var body: some View {
        if state.phase == .running, let start = state.startedAt, let end = state.endsAt, end > start {
            Text(timerInterval: start...end, countsDown: true)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        }
    }
}

private struct Progress: View {
    let state: RemoteStartActivityAttributes.ContentState

    var body: some View {
        if state.phase == .running, let start = state.startedAt, let end = state.endsAt, end > start {
            ProgressView(timerInterval: start...end, countsDown: true) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .tint(.green)
        }
    }
}

private func phaseIsActive(_ state: RemoteStartActivityAttributes.ContentState) -> Bool {
    state.phase == .confirming || state.phase == .running
}

private func phaseHeadline(_ state: RemoteStartActivityAttributes.ContentState, temperature: Int?) -> String {
    switch state.phase {
    case .confirming: return "Starting…"
    case .running: return temperature.map { "Engine on · \($0) °C" } ?? "Engine on"
    case .finished: return "Finished"
    case .failed: return "Didn't start"
    }
}

private func phaseDetail(_ state: RemoteStartActivityAttributes.ContentState, temperature: Int) -> String {
    switch state.phase {
    case .confirming:
        return "Waiting for the car to confirm"
    case .running:
        if let end = state.endsAt {
            return "Climate \(temperature) °C · ends about \(end.formatted(date: .omitted, time: .shortened))"
        }
        return "Climate \(temperature) °C"
    case .finished, .failed:
        return state.message ?? ""
    }
}

private func phaseSymbol(_ state: RemoteStartActivityAttributes.ContentState) -> String {
    switch state.phase {
    case .confirming: return "hourglass"
    case .running: return "fan.fill"
    case .finished: return "checkmark.circle.fill"
    case .failed: return "exclamationmark.triangle.fill"
    }
}

private func phaseTint(_ state: RemoteStartActivityAttributes.ContentState) -> Color {
    switch state.phase {
    case .confirming: return .orange
    case .running: return .green
    case .finished: return .teal
    case .failed: return .red
    }
}
