import SwiftUI
import AVKit
import AVFoundation

/// Watches the live audio route so the in-call button can show where sound is
/// actually going (earpiece, speaker, AirPods, car, …).
@MainActor
final class AudioRouteMonitor: ObservableObject {
    @Published private(set) var portType: AVAudioSession.Port?
    @Published private(set) var portName: String = ""

    private var observer: NSObjectProtocol?

    init() {
        refresh()
        observer = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    private func refresh() {
        let output = AVAudioSession.sharedInstance().currentRoute.outputs.first
        portType = output?.portType
        portName = output?.portName ?? ""
    }

    var isSpeaker: Bool { portType == .builtInSpeaker }

    var icon: String {
        switch portType {
        case .builtInSpeaker: return "speaker.wave.2.fill"
        case .headphones, .headsetMic: return "headphones"
        case .bluetoothA2DP, .bluetoothHFP, .bluetoothLE: return "airpods"
        case .carAudio: return "car.fill"
        case .airPlay: return "airplayaudio"
        default: return "speaker.wave.1"   // built-in receiver (earpiece)
        }
    }

    var label: String {
        switch portType {
        case .builtInSpeaker: return "Speaker"
        case .builtInReceiver, .none: return "iPhone"
        default: return portName
        }
    }
}

/// In-call audio output button: shows the current route's icon (filled when on
/// speaker) and opens the system route picker — earpiece / speaker / Bluetooth —
/// via a transparent `AVRoutePickerView` overlay.
struct AudioRouteButton: View {
    @StateObject private var monitor = AudioRouteMonitor()
    var diameter: CGFloat = 60
    var tint: Color = Theme.Color.text
    var strokeColor: Color = Theme.Color.hairline
    var filledIconColor: Color = Theme.Color.onAccent

    var body: some View {
        ZStack {
            Circle()
                .fill(monitor.isSpeaker ? tint : Color.clear)
                .overlay(
                    Circle().stroke(monitor.isSpeaker ? Color.clear : strokeColor,
                                    lineWidth: Theme.hairlineWidth)
                )
            Image(systemName: monitor.icon)
                .font(.system(size: diameter * 0.30, weight: .light))
                .foregroundStyle(monitor.isSpeaker ? filledIconColor : tint)
                .animation(Theme.Motion.fast, value: monitor.icon)
        }
        .frame(width: diameter, height: diameter)
        .contentShape(Circle())
        // The picker is the actual tap target; our circle is just its face.
        .overlay(SystemRoutePicker().opacity(0.02))
        .simultaneousGesture(TapGesture().onEnded { Haptics.tap() })
        .accessibilityLabel("Audio output")
        .accessibilityValue(monitor.label)
        .accessibilityHint("Choose speaker, earpiece, or Bluetooth")
    }
}

private struct SystemRoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.prioritizesVideoDevices = false
        view.tintColor = .clear
        view.activeTintColor = .clear
        return view
    }
    func updateUIView(_ view: AVRoutePickerView, context: Context) {}
}
