import Foundation

/// Returned with the text, but only metadata is retained by the controller.
public struct NormalizationReport {
    public struct BoundaryScore {
        /// One-based line number after local normalization, before cloud joins.
        public let nextLine: Int
        public let score: Double
    }

    public let text: String
    public let localJoins: Int
    public let provider: CloudProvider
    public let scores: [BoundaryScore]
    public let noRequestReason: String?

    public var summary: String {
        if noRequestReason != nil {
            return "Local rules: \(localJoins) joins; \(provider.name) not requested."
        }
        let accepted = scores.filter { $0.score >= provider.joinThreshold }.count
        return "\(provider.name) returned: \(accepted)/\(scores.count) joins; local: \(localJoins)."
    }

    public var details: [String] {
        var rows = ["Local joins: \(localJoins)"]
        if let noRequestReason {
            rows.append("\(provider.name) not requested: " + noRequestReason)
        } else {
            rows.append("\(provider.name) response validated; threshold: \(provider.joinThreshold)")
            rows.append("Line numbers refer to text after local joins.")
            rows += scores.map { boundary in
                let decision = boundary.score >= provider.joinThreshold ? "join" : "keep break"
                return "Lines \(boundary.nextLine - 1)–\(boundary.nextLine): \(boundary.score) → \(decision)"
            }
        }
        return rows
    }

    static func joinCount(from original: String, to result: String) -> Int {
        original.utf8.filter { $0 == 10 }.count - result.utf8.filter { $0 == 10 }.count
    }
}
