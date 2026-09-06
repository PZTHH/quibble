import Foundation

public struct DictationSession: Sendable {
    public enum State: Equatable, Sendable {
        case idle
        case recording(UUID)
        case processing(UUID)
        case ready(UUID, String)
    }

    public private(set) var state: State = .idle
    public init() {}

    @discardableResult public mutating func start() -> UUID? {
        switch state {
        case .recording, .processing: return nil
        case .idle, .ready: break
        }
        let id = UUID()
        state = .recording(id)
        return id
    }
    public mutating func stop() {
        if case .recording(let id) = state { state = .processing(id) }
    }
    public mutating func cancel() { state = .idle }
    @discardableResult public mutating func complete(_ id: UUID, text: String) -> Bool {
        guard state == .processing(id) else { return false }
        state = .ready(id, text)
        return true
    }
}
