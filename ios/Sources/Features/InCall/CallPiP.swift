import SwiftUI
import AVKit
import CoreMedia

#if canImport(LiveKit)
import LiveKit

/// System Picture-in-Picture for video calls: when the app is backgrounded
/// mid-call, the remote feed continues in a floating PiP window instead of
/// silently disappearing.
///
/// Mechanics: a `VideoRenderer` converts each remote `VideoFrame` to a
/// `CMSampleBuffer` and enqueues it on an `AVSampleBufferDisplayLayer`; an
/// `AVPictureInPictureController` with that layer as its content source starts
/// PiP automatically on backgrounding (the layer's host view must be in the
/// window hierarchy — InCallView embeds a 1pt anchor).
final class PiPSampleBufferRenderer: NSObject, VideoRenderer, @unchecked Sendable {
    let displayLayer = AVSampleBufferDisplayLayer()

    @MainActor var isAdaptiveStreamEnabled: Bool { true }
    @MainActor var adaptiveStreamSize: CGSize { CGSize(width: 1280, height: 720) }

    func render(frame: VideoFrame) {
        guard let sampleBuffer = frame.toCMSampleBuffer() else { return }
        // Live video: mark every frame display-immediately so the layer never
        // waits on a timebase.
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: true),
           CFArrayGetCount(attachments) > 0 {
            let dict = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(dict,
                                 Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                                 Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }
        DispatchQueue.main.async { [displayLayer] in
            if displayLayer.status == .failed { displayLayer.flush() }
            displayLayer.enqueue(sampleBuffer)
        }
    }
}

@MainActor
final class CallPiPController: NSObject {
    static let shared = CallPiPController()

    private let renderer = PiPSampleBufferRenderer()
    private var pip: AVPictureInPictureController?
    private weak var attachedTrack: VideoTrack?

    /// Host view for the display layer — must be installed somewhere in the
    /// call screen's hierarchy (1pt is enough) for auto-PiP to engage.
    let sourceView = PiPSourceUIView()

    override private init() {
        super.init()
        sourceView.hostedLayer = renderer.displayLayer
    }

    /// Start mirroring `track` into the PiP layer (idempotent per track).
    func attachIfNeeded(track: VideoTrack) {
        guard attachedTrack !== track else { return }
        if let old = attachedTrack { old.remove(videoRenderer: renderer) }
        attachedTrack = track
        track.add(videoRenderer: renderer)
        setupControllerIfNeeded()
    }

    /// Tear down at call end so no stale PiP window lingers.
    func detach() {
        if let old = attachedTrack { old.remove(videoRenderer: renderer) }
        attachedTrack = nil
        if pip?.isPictureInPictureActive == true { pip?.stopPictureInPicture() }
        renderer.displayLayer.flushAndRemoveImage()
    }

    private func setupControllerIfNeeded() {
        guard pip == nil, AVPictureInPictureController.isPictureInPictureSupported() else { return }
        let source = AVPictureInPictureController.ContentSource(
            sampleBufferDisplayLayer: renderer.displayLayer,
            playbackDelegate: self)
        let controller = AVPictureInPictureController(contentSource: source)
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.delegate = self
        pip = controller
    }
}

extension CallPiPController: AVPictureInPictureControllerDelegate {
    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        // The call screen is still presented underneath; nothing to rebuild.
        completionHandler(true)
    }
}

extension CallPiPController: AVPictureInPictureSampleBufferPlaybackDelegate {
    nonisolated func pictureInPictureController(_ controller: AVPictureInPictureController, setPlaying playing: Bool) {}
    nonisolated func pictureInPictureControllerTimeRangeForPlayback(_ controller: AVPictureInPictureController) -> CMTimeRange {
        // Live content: infinite range, no scrubbing.
        CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity)
    }
    nonisolated func pictureInPictureControllerIsPlaybackPaused(_ controller: AVPictureInPictureController) -> Bool { false }
    nonisolated func pictureInPictureController(_ controller: AVPictureInPictureController,
                                                didTransitionToRenderSize newRenderSize: CMVideoDimensions) {}
    nonisolated func pictureInPictureController(_ controller: AVPictureInPictureController,
                                                skipByInterval skipInterval: CMTime) async {}
}

/// Plain UIView that hosts the sample-buffer layer and keeps it sized.
final class PiPSourceUIView: UIView {
    var hostedLayer: AVSampleBufferDisplayLayer? {
        didSet {
            oldValue?.removeFromSuperlayer()
            if let hostedLayer { layer.addSublayer(hostedLayer) }
        }
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        hostedLayer?.frame = bounds
    }
}

/// SwiftUI anchor that installs the PiP source view into the hierarchy.
struct PiPAnchorView: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView { CallPiPController.shared.sourceView }
    func updateUIView(_ uiView: UIView, context: Context) {}
}
#endif
