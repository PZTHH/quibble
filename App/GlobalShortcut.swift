import AppKit
import QuibbleCore

@MainActor
final class GlobalShortcut {
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    var onToggle: (() -> Void)?
    var onCancel: (() -> Void)?
    var onPasteLast: (() -> Void)?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    var state = ShortcutState()
    var suspended = false { didSet { state.reset() } }

    func start() -> Bool {
        if tap != nil { return true }
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: CGEventMask(mask), callback: { _, type, event, pointer in
                // The tap runs on the main run loop. Return only a Sendable decision
                // across assumeIsolated; the event remains owned by the C callback.
                let forward = MainActor.assumeIsolated {
                    guard let pointer else { return true }
                    return Unmanaged<GlobalShortcut>.fromOpaque(pointer).takeUnretainedValue().handle(type, event)
                }
                return forward ? Unmanaged.passUnretained(event) : nil
            }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let tap else { return false }
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil; source = nil; state.reset()
        DispatchQueue.main.async { [weak self] in self?.onCancel?() }
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout {
            // The session tap consumes our chords. Read hardware state upstream of that tap.
            let keys: Set<UInt16> = [state.dictation.keyCode, state.toggleDictation.keyCode, state.pasteLast.keyCode, 53]
            let pressed = Set(keys.filter { CGEventSource.keyState(.hidSystemState, key: $0) })
            let recovered = state.recoverAfterTimeout(pressedKeys: pressed,
                modifiers: CGEventSource.flagsState(.hidSystemState).rawValue)
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            if recovered.action == .release {
                DispatchQueue.main.async { [weak self] in self?.onRelease?() }
            }
            return true
        }
        if type == .tapDisabledByUserInput {
            state.reset()
            DispatchQueue.main.async { [weak self] in self?.onCancel?() }
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return true
        }
        guard !suspended else { return true }
        let kind: ShortcutState.Event
        switch type { case .keyDown: kind = .down; case .keyUp: kind = .up; case .flagsChanged: kind = .modifiersChanged; default: return true }
        let result = state.handle(kind, key: UInt16(clamping: event.getIntegerValueField(.keyboardEventKeycode)),
            modifiers: event.flags.rawValue, repeated: event.getIntegerValueField(.keyboardEventAutorepeat) != 0)
        if let action = result.action {
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.suspended else { return }
                switch action {
                case .press: self.onPress?()
                case .release: self.onRelease?()
                case .toggle: self.onToggle?()
                case .cancel: self.onCancel?()
                case .pasteLast: self.onPasteLast?()
                }
            }
        }
        return !result.consume
    }
}
