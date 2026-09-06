import Foundation

/// A bundled, dated upstream benchmark snapshot; never a local accuracy claim.
public struct ASRBenchmarkCatalog: Decodable, Sendable {
    public let retrievedAt: String
    public let task: String
    public let sourceURL: String
    public let sourceRevision: String
    public let methodology: String
    public let results: [Result]
    public let speedBenchmark: SpeedBenchmark?
    public let unavailable: [Unavailable]?

    /// Why an exact checkpoint cannot share this snapshot's comparison scale.
    public struct Unavailable: Decodable, Sendable {
        public let modelID: String
        public let evaluatedModel: String
        public let reason: String
    }

    public func unavailableResult(for modelID: String) -> Unavailable? {
        guard result(for: modelID) == nil, speedRTFx(for: modelID) == nil else { return nil }
        return unavailable?.first { $0.modelID == modelID }
    }

    public struct SpeedBenchmark: Decodable, Sendable {
        public let retrievedAt: String
        public let hardware: String
        public let scope: String
        public let methodology: String
        public let sourceURL: String
        public let hardwareSourceURL: String
        public let note: String
    }

    public struct Result: Decodable, Sendable {
        public let modelID: String
        public let evaluatedModel: String
        public let werPercent: Double
        public let sourceURL: String
        public let note: String
        public let rtfx: Double?
    }
    public func result(for modelID: String) -> Result? {
        results.first { $0.modelID == modelID && $0.werPercent.isFinite && $0.werPercent >= 0 }
    }

    public struct AccuracyStanding: Equatable, Sendable {
        public let position: Int
        public let levels: Int
        public var filledSegments: Int { levels - position + 1 }
    }

    /// Dense rank across the entire bundled snapshot, never the current UI filter.
    /// A relative comparison, not a percent-correct or magnitude-of-difference score.
    public func accuracyStanding(for modelID: String) -> AccuracyStanding? {
        guard let result = result(for: modelID) else { return nil }
        let scores = Set(results.map(\.werPercent).filter { $0.isFinite && $0 >= 0 }).sorted()
        guard let index = scores.firstIndex(of: result.werPercent) else { return nil }
        return AccuracyStanding(position: index + 1, levels: scores.count)
    }

    /// Published upstream throughput needs its hardware and evaluation scope to be usable.
    public func speedRTFx(for modelID: String) -> Double? {
        guard speedBenchmark != nil, let value = results.first(where: { $0.modelID == modelID })?.rtfx,
              value.isFinite, value > 0 else { return nil }
        return value
    }

    /// Relative rank inside this one HF hardware cohort; never an estimate of Mac latency.
    public func speedStanding(for modelID: String) -> AccuracyStanding? {
        guard let value = speedRTFx(for: modelID) else { return nil }
        let scores = Set(results.compactMap(\.rtfx).filter { $0.isFinite && $0 > 0 }).sorted(by: >)
        guard let index = scores.firstIndex(of: value) else { return nil }
        return AccuracyStanding(position: index + 1, levels: scores.count)
    }
}
