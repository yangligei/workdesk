import Foundation

/// Gate that keeps a menu from being presented while the click that asked for
/// it is still held. Presenting inside the status button's own press handling
/// makes the menu's tracking loop consume that click's release and dismiss the
/// menu immediately, which reads as "the two-finger press does nothing".
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
