import Foundation

/// Formats status output that is shared between the daemon and CLI.
public enum SoundwayStatusFormatting {
    /// Describes a routing table in human-readable form.
    public static func describeRouting(_ route: [Int]) -> String {
        guard !route.isEmpty else {
            return "identity"
        }

        return route.enumerated().map { index, source in
            "\(index + 1)->\(source > 0 ? source : 0)"
        }.joined(separator: ", ")
    }
}
