import SwiftUI

// MARK: - RangeSlider (two thumbs, one track)

/// Two-thumb range slider. The selected span is drawn in `Theme.Color.warm`
/// on a hairline track, with the bounds printed small under each end.
///
/// - Values snap to `step` and the thumbs never cross: they always stay at
///   least `minimumDistance` apart.
/// - Every step change ticks `Haptics.select()`.
/// - One drag gesture covers the whole 44pt-tall track (the visible thumbs
///   are 28pt). Nothing is decided until the finger has moved `touchSlop`
///   sideways, and further sideways than up or down: lifting before that
///   is a tap, and a vertical scroll that starts on the track or on a thumb
///   leaves the thumbs alone until the ScrollView takes the gesture over.
///   A touch within 22pt of a thumb then grabs it and moves it by the
///   finger's translation from that point, so grabbing it off-centre
///   doesn't make it jump, and neither does the slop already travelled.
///   When the thumbs sit together, pinned `minimumDistance` apart or drawn
///   overlapping, the direction of the drag picks one: left means the lower
///   thumb, right the upper. A tap on the track away from both thumbs moves
///   the nearest thumb there; a sideways drag from the track does the same
///   and then follows the finger.
/// - Everything about the drag in progress lives in `@GestureState`, which
///   SwiftUI clears when the gesture ends or is cancelled (a ScrollView
///   taking over, a sheet pulled down), so nothing stale survives into the
///   next touch.
/// - Positions are derived from the bindings on every render, so a write
///   from outside (e.g. `onAppear` loading `appState.me`) just shows up.
/// - VoiceOver sees two adjustable elements named `lowerLabel` and
///   `upperLabel`, each reporting its value; swipe up/down moves one step.
struct RangeSlider: View {
    @Binding var lowerValue: Double
    @Binding var upperValue: Double
    var bounds: ClosedRange<Double> = 18...99
    var step: Double = 1
    var minimumDistance: Double = 1
    /// VoiceOver names for the two thumbs.
    var lowerLabel: String = "Minimum"
    var upperLabel: String = "Maximum"

    private enum Thumb { case lower, upper }

    /// What the finger on the track is doing.
    private enum DragInfo {
        /// Finger down, but which thumb it means isn't known yet.
        case undecided
        /// `startValue` is what the finger's translation is applied to.
        case dragging(Thumb, startValue: Double)
    }

    /// Nil while no finger is down. SwiftUI resets it when the gesture ends
    /// and when it is cancelled, so no per-drag bookkeeping goes in `@State`.
    @GestureState private var drag: DragInfo?

    private let thumbDiameter: CGFloat = 28
    private let hitArea: CGFloat = 44
    private let trackHeight: CGFloat = 4
    /// A touch has to travel this far sideways, and further sideways than up
    /// or down, before it counts as a drag; lifting before that is a tap.
    /// This keeps a vertical scroll that happens to start on the track or on
    /// a thumb from moving anything.
    private let touchSlop: CGFloat = 6
    /// Thumb centres this close together are treated as one pile.
    private let coincidenceTolerance: CGFloat = 4

    var body: some View {
        VStack(spacing: Theme.Space.xxs) {
            GeometryReader { geo in
                let usable = max(geo.size.width - thumbDiameter, 1)
                let lowerX = x(for: clampedLower, usable: usable)
                let upperX = x(for: clampedUpper, usable: usable)
                let midY = hitArea / 2

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Theme.Color.hairline)
                        .frame(height: trackHeight)
                    Capsule()
                        .fill(Theme.Color.warm)
                        .frame(width: max(upperX - lowerX, 0), height: trackHeight)
                        .offset(x: lowerX)
                    thumb(.lower, value: clampedLower)
                        .position(x: lowerX, y: midY)
                        .zIndex(activeThumb == .lower ? 1 : 0)
                    thumb(.upper, value: clampedUpper)
                        .position(x: upperX, y: midY)
                        .zIndex(activeThumb == .upper ? 1 : 0)
                }
                .frame(width: geo.size.width, height: hitArea)
                .contentShape(Rectangle())
                .gesture(trackGesture(usable: usable))
            }
            .frame(height: hitArea)

            HStack {
                Text(format(bounds.lowerBound))
                Spacer()
                Text(format(bounds.upperBound))
            }
            .font(Theme.Font.caption)
            .foregroundStyle(Theme.Color.textSecondary)
            .accessibilityHidden(true)
        }
    }

    // MARK: Thumb

    private func thumb(_ which: Thumb, value: Double) -> some View {
        let isActive = activeThumb == which
        return Circle()
            .fill(Theme.Color.bg)
            .overlay(
                Circle().stroke(Theme.Color.warm, lineWidth: isActive ? 2 : Theme.iconStroke)
            )
            .frame(width: thumbDiameter, height: thumbDiameter)
            .scaleEffect(isActive ? 1.08 : 1)
            .animation(Theme.Motion.fast, value: isActive)
            .frame(width: hitArea, height: hitArea)
            .accessibilityElement()
            .accessibilityLabel(which == .lower ? lowerLabel : upperLabel)
            .accessibilityValue(format(value))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: set(which, to: value + step)
                case .decrement: set(which, to: value - step)
                @unknown default: break
                }
            }
    }

    // MARK: Gesture

    private var activeThumb: Thumb? {
        if case .dragging(let thumb, _)? = drag { return thumb }
        return nil
    }

    private func trackGesture(usable: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($drag) { g, state, _ in
                state = resolve(state, g, usable: usable)
            }
            .onChanged { g in
                guard case .dragging(let thumb, let start) = resolve(drag, g, usable: usable) else { return }
                set(thumb, to: start + Double(g.translation.width / usable) * span)
            }
            .onEnded { g in
                // A tap on the track away from both thumbs moves the nearest
                // one there. A tap on a thumb changes nothing.
                guard abs(g.translation.width) < touchSlop,
                      abs(g.translation.height) < touchSlop else { return }
                let touchX = g.startLocation.x
                let (thumb, distance) = nearestThumb(to: touchX, usable: usable)
                guard distance > hitArea / 2 else { return }
                set(thumb, to: value(atX: touchX, usable: usable))
            }
    }

    /// Works out which thumb a touch means from what is known so far. Once
    /// decided, the answer comes back unchanged, so calling this from both
    /// `updating` and `onChanged` with the same gesture value is safe even
    /// if the second call sees the state from before the first.
    private func resolve(_ current: DragInfo?, _ g: DragGesture.Value, usable: CGFloat) -> DragInfo {
        if let current, case .dragging = current { return current }

        // Nothing is decided until the finger has clearly moved sideways,
        // whether it landed on a thumb or on the bare track. Lifting before
        // that is a tap, handled in onEnded; moving mostly up or down is a
        // scroll, which the enclosing ScrollView takes over.
        let dx = g.translation.width
        guard abs(dx) >= touchSlop, abs(dx) > abs(g.translation.height) else { return .undecided }

        let touchX = g.startLocation.x
        let (nearest, distance) = nearestThumb(to: touchX, usable: usable)

        guard distance <= hitArea / 2 else {
            // Off both thumbs: the nearest one jumps under the finger and
            // follows it from there.
            return .dragging(nearest, startValue: value(atX: touchX, usable: usable))
        }

        // On a thumb. When the two sit together the direction of the drag
        // says which one the finger means; otherwise it is the nearest. The
        // start value is backed off by the distance already travelled so the
        // thumb doesn't jump by that much the moment it is picked. It is not
        // clamped: a thumb at either end would jump by the slop if it were,
        // and `set` clamps everything it writes anyway.
        let thumb: Thumb
        if thumbsPiled(under: touchX, usable: usable) {
            thumb = dx < 0 ? .lower : .upper
        } else {
            thumb = nearest
        }
        return .dragging(thumb, startValue: value(of: thumb) - Double(dx / usable) * span)
    }

    /// True when a touch at `touchX` can't be said to mean one thumb rather
    /// than the other: the thumbs are pinned (see `thumbsPinned`), or they
    /// are drawn overlapping (centres closer than a thumb's width, ages 30
    /// and 32 say) and the touch is within reach of both.
    private func thumbsPiled(under touchX: CGFloat, usable: CGFloat) -> Bool {
        if thumbsPinned(usable: usable) { return true }
        let lowerX = x(for: clampedLower, usable: usable)
        let upperX = x(for: clampedUpper, usable: usable)
        return upperX - lowerX < thumbDiameter
            && abs(touchX - lowerX) <= hitArea / 2
            && abs(touchX - upperX) <= hitArea / 2
    }

    /// True when the thumbs are as close as `minimumDistance` allows, or are
    /// drawn on top of each other, so neither can move toward the other.
    private func thumbsPinned(usable: CGFloat) -> Bool {
        if clampedUpper - clampedLower <= minimumDistance + step / 2 { return true }
        return x(for: clampedUpper, usable: usable) - x(for: clampedLower, usable: usable) <= coincidenceTolerance
    }

    /// The thumb whose centre is closest to `touchX`, and how far it is. On
    /// a tie (a coincident pair, or exactly midway) a touch to the left
    /// means the lower thumb and one to the right the upper, since that is
    /// the thumb that can actually move toward the touch.
    private func nearestThumb(to touchX: CGFloat, usable: CGFloat) -> (thumb: Thumb, distance: CGFloat) {
        let lowerX = x(for: clampedLower, usable: usable)
        let dLower = abs(touchX - lowerX)
        let dUpper = abs(touchX - x(for: clampedUpper, usable: usable))
        if dLower < dUpper { return (.lower, dLower) }
        if dUpper < dLower { return (.upper, dUpper) }
        return touchX < lowerX ? (.lower, dLower) : (.upper, dUpper)
    }

    // MARK: Values

    private var span: Double { max(bounds.upperBound - bounds.lowerBound, .ulpOfOne) }

    /// The bindings clamped into `bounds` for drawing. A stray out-of-range
    /// value (an old profile, say) is shown at the nearest end rather than
    /// off the track; the next drag writes back a valid one.
    private var clampedLower: Double { min(max(lowerValue, bounds.lowerBound), bounds.upperBound) }
    private var clampedUpper: Double { min(max(upperValue, bounds.lowerBound), bounds.upperBound) }

    private func value(of thumb: Thumb) -> Double {
        thumb == .lower ? clampedLower : clampedUpper
    }

    private func x(for value: Double, usable: CGFloat) -> CGFloat {
        thumbDiameter / 2 + CGFloat((value - bounds.lowerBound) / span) * usable
    }

    /// Inverse of `x(for:usable:)`: the unsnapped value under a point on the track.
    private func value(atX touchX: CGFloat, usable: CGFloat) -> Double {
        bounds.lowerBound + Double((touchX - thumbDiameter / 2) / usable) * span
    }

    private func snap(_ raw: Double) -> Double {
        guard step > 0 else { return raw }
        return bounds.lowerBound + ((raw - bounds.lowerBound) / step).rounded() * step
    }

    /// Snap, clamp so the thumbs stay `minimumDistance` apart and inside
    /// `bounds`, then write the binding and tick a haptic only if the value
    /// actually moved a step.
    private func set(_ which: Thumb, to raw: Double) {
        let snapped = snap(raw)
        switch which {
        case .lower:
            let ceiling = max(bounds.lowerBound, clampedUpper - minimumDistance)
            let next = min(max(snapped, bounds.lowerBound), ceiling)
            guard next != lowerValue else { return }
            lowerValue = next
        case .upper:
            let floor = min(bounds.upperBound, clampedLower + minimumDistance)
            let next = max(min(snapped, bounds.upperBound), floor)
            guard next != upperValue else { return }
            upperValue = next
        }
        Haptics.select()
    }

    private func format(_ value: Double) -> String {
        step == step.rounded() ? String(Int(value.rounded())) : value.formatted()
    }
}

// MARK: - Preview

#if DEBUG
private struct RangeSliderPreview: View {
    @State private var lower: Double = 24
    @State private var upper: Double = 35

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text("Ages \(Int(lower))\u{2013}\(Int(upper))").uppercaseLabel()
            RangeSlider(lowerValue: $lower, upperValue: $upper,
                        lowerLabel: "Minimum age", upperLabel: "Maximum age")
        }
        .padding(Theme.Space.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Color.bg)
    }
}

#Preview {
    RangeSliderPreview()
}
#endif
