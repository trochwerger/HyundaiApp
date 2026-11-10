import SwiftUI

/// Car-screen card for the current remote start: confirming, running with a
/// countdown, didn't start, or finished.
struct RemoteStartCard: View {
    let session: RemoteStartSession
    let isLocked: Bool?
    let isStopping: Bool
    let onStop: () -> Void
    let onRetry: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        Group {
            switch session.stage {
            case .confirming:
                confirming
            case .unconfirmed:
                unconfirmed
            case .running:
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    running(now: context.date)
                }
            case .failed:
                failed
            case .finished:
                finished
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(tint), in: .rect(cornerRadius: 28))
    }

    private var tint: Color {
        session.stage == .failed ? .red.opacity(0.10) : .clear
    }

    // MARK: - Confirming

    private var confirming: some View {
        VStack(alignment: .leading, spacing: 14) {
            header(title: "Climate", detail: settingsText)

            VStack(alignment: .leading, spacing: 12) {
                step(.done, title: "Sent to Hyundai", detail: session.sentAt.formatted(date: .omitted, time: .shortened))
                step(.working, title: "Car confirming", detail: "Usually 20–60 seconds")
                step(.pending, title: "Engine on", detail: nil)
            }

            stopButton(title: "Cancel start", prominent: false)
        }
    }

    private var unconfirmed: some View {
        VStack(alignment: .leading, spacing: 12) {
            header(title: "Climate", detail: settingsText)
            Label("No answer from the car yet", systemImage: "questionmark.circle.fill")
                .font(.headline)
                .foregroundStyle(.orange)
            Text("It may still have started. While the app is open it checks the car's saved status every 2 min, without waking the car.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            stopButton(title: "Stop remote start", prominent: false)
        }
    }

    // MARK: - Running

    private func running(now: Date) -> some View {
        let remaining = session.remaining(at: now)
        return VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label("Engine on", systemImage: "circle.fill")
                    .labelStyle(EngineOnLabelStyle())
                Spacer()
                if let confirmedAt = session.confirmedAt {
                    Text("Confirmed \(confirmedAt.formatted(date: .omitted, time: .shortened))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 20) {
                    countdownRing(remaining: remaining, now: now)
                    runningDetails
                }
                VStack(alignment: .leading, spacing: 16) {
                    countdownRing(remaining: remaining, now: now)
                    runningDetails
                }
            }

            stopButton(title: "Stop remote start", prominent: true)

            Text("Time left is counted on your phone. While the app is open it rechecks the car's saved status every 2 min; it never wakes the car.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func countdownRing(remaining: TimeInterval, now: Date) -> some View {
        ZStack {
            Circle().stroke(.quaternary, lineWidth: 12)
            Circle()
                .trim(from: 0, to: session.remainingFraction(at: now))
                .stroke(Color.green, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: remaining)
            VStack(spacing: 2) {
                Text(RemoteStartSession.countdownText(remaining))
                    .font(.system(.title, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
                Text("left of \(session.durationMinutes) min")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .minimumScaleFactor(0.6)
            .padding(18)
        }
        .frame(width: 136, height: 136)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(RemoteStartSession.countdownText(remaining)) left of \(session.durationMinutes) minutes")
    }

    private var runningDetails: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Cabin target")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("\(Int(session.targetTemperature.rounded())) °C")
                    .font(.title2.weight(.bold))
            }
            Text(session.defrost ? "Defrost on" : "Defrost off")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let endsAt = session.endsAt {
                Text("Ends about \(endsAt.formatted(date: .omitted, time: .shortened))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Outcomes

    private var failed: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("The car didn't start", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.red)
            Text(session.failureMessage ?? "Hyundai reported the remote start failed.")
                .font(.subheadline)
            Text("Common causes: a door, hood or trunk open, the car not in Park, or a low 12V battery. Nothing was retried automatically.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button("Try again", action: onRetry)
                    .buttonStyle(.glassProminent)
                    .frame(maxWidth: .infinity)
                Button("Dismiss", action: onDismiss)
                    .buttonStyle(.glass)
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
        }
    }

    private var finished: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.teal)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Remote start finished")
                        .font(.headline)
                    Text(finishedSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button("Dismiss", systemImage: "xmark", action: onDismiss)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.glass)
            }

            HStack(spacing: 10) {
                stat("Cabin", "\(Int(session.targetTemperature.rounded())) °C")
                stat("Battery used", session.batteryUsed.map { "\($0)%" } ?? "—")
                stat("Doors", isLocked.map { $0 ? "Locked" : "Unlocked" } ?? "—")
            }
        }
    }

    private var finishedSubtitle: String {
        var parts: [String] = []
        if let ranFor = session.ranFor { parts.append("Ran \(RemoteStartSession.durationText(ranFor))") }
        if let endedAt = session.endedAt { parts.append("ended \(endedAt.formatted(date: .omitted, time: .shortened))") }
        return parts.isEmpty ? "Finished" : parts.joined(separator: " · ")
    }

    // MARK: - Pieces

    private var settingsText: String {
        "\(Int(session.targetTemperature.rounded())) °C · \(session.durationMinutes) min"
    }

    private func header(title: String, detail: String) -> some View {
        HStack {
            Text(title).font(.title3.weight(.bold))
            Spacer()
            Text(detail)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.teal)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .glassEffect(.regular.tint(.teal.opacity(0.12)), in: .capsule)
        }
    }

    private enum StepState { case done, working, pending }

    private func step(_ state: StepState, title: String, detail: String?) -> some View {
        HStack(spacing: 12) {
            Group {
                switch state {
                case .done:
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                case .working:
                    ProgressView()
                case .pending:
                    Image(systemName: "circle").foregroundStyle(.tertiary)
                }
            }
            .font(.title3)
            .frame(width: 26)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(state == .pending ? .secondary : .primary)
                if let detail {
                    Text(detail).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func stopButton(title: String, prominent: Bool) -> some View {
        let button = Button(role: .destructive, action: onStop) {
            HStack {
                if isStopping {
                    ProgressView()
                } else {
                    Label(title, systemImage: "stop.fill")
                }
            }
            .frame(maxWidth: .infinity)
        }
        .controlSize(.large)
        .disabled(isStopping)

        if prominent {
            button.buttonStyle(.glassProminent).tint(.red)
        } else {
            button.buttonStyle(.glass)
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }
}

private struct EngineOnLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "circle.fill")
                .font(.system(size: 8))
                .symbolEffect(.pulse)
            configuration.title
        }
        .font(.subheadline.weight(.bold))
        .foregroundStyle(.green)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .glassEffect(.regular.tint(.green.opacity(0.15)), in: .capsule)
    }
}
