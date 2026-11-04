import Foundation

/// Why this exists
/// ---------------
/// AppKit does not deliver a dependable `clickCount` to a status-item action:
/// the action can be invoked from a system/Kit-defined event, where reading
/// `NSEvent.clickCount` raises `NSInternalInconsistencyException`, and
/// `sendAction(on: .leftMouseDown)` means the press handler runs before the
/// matching mouse-up. Physical double clicks must therefore be recognised by
/// the *arrival time* of two presses, with `clickCount` used only as
/// corroboration. This type is deliberately free of AppKit and of wall-clock
/// time so the decision rule is unit-testable.
public enum StatusClickDecision: Equatable {
    /// First press: hold the single-click action until the window expires.
    case pendingSingle
    /// A second press landed inside the double-click window.
    case double
    /// A further press right after a double click: part of the same burst, ignored.
    case ignored
}

public struct StatusClickTracker {
    public let interval: TimeInterval
    private var pendingAt: TimeInterval?
    private var lastDoubleAt: TimeInterval?

    public init(interval: TimeInterval) {
        self.interval = interval
    }

    public var hasPendingSingle: Bool { pendingAt != nil }

    /// Records a press at monotonic time `t`.
    /// - Parameter clickCount: AppKit's value, if one can be read safely.
    public mutating func press(at t: TimeInterval, clickCount: Int = 1) -> StatusClickDecision {
        if let last = lastDoubleAt, t - last <= interval, t >= last {
            return .ignored
        }
        if clickCount >= 2 {
            // Corroborating signal: AppKit already paired these presses.
            pendingAt = nil
            lastDoubleAt = t
            return .double
        }
        if let start = pendingAt, t - start <= interval, t >= start {
            pendingAt = nil
            lastDoubleAt = t
            return .double
        }
        pendingAt = t
        return .pendingSingle
    }

    /// Called when the timer fires: true means the held single click must run.
    public mutating func expire(at t: TimeInterval) -> Bool {
        guard let start = pendingAt else { return false }
        guard t - start >= interval else { return false }
        pendingAt = nil
        return true
    }

    /// Cancels any held single click (double click, app teardown, menu open).
    public mutating func cancel() {
        pendingAt = nil
    }

    /// Clears all state, including the post-double-click cooldown (tests only).
    public mutating func reset() {
        pendingAt = nil
        lastDoubleAt = nil
    }
}

/// Gate that keeps a menu from being presented while the click that asked for
/// it is still held. Presenting inside the status button's own press handling
/// makes the menu's tracking loop consume that click's release and dismiss the
/// menu immediately, which reads as "double click does nothing".
public struct MenuReleaseGate {
    public let timeout: TimeInterval
    private var beganAt: TimeInterval?

    public init(timeout: TimeInterval) {
        self.timeout = timeout
    }

    public var isWaiting: Bool { beganAt != nil }

    public mutating func begin(at t: TimeInterval) {
        beganAt = t
    }

    /// True exactly once: when the button is up or the bounded wait expired.
    public mutating func shouldPresent(buttonsDown: Bool, at t: TimeInterval) -> Bool {
        guard let start = beganAt else { return false }
        guard !buttonsDown || t - start >= timeout else { return false }
        beganAt = nil
        return true
    }

    public mutating func reset() {
        beganAt = nil
    }
}
