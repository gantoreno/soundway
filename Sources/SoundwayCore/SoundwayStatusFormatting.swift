import Foundation

public enum SoundwayStatusFormatting {
    public static func describeRouting(_ route: [Int]) -> String {
        guard !route.isEmpty else {
            return "identity"
        }

        return route.enumerated().map { index, source in
            "\(index + 1)->\(source > 0 ? source : 0)"
        }.joined(separator: ", ")
    }
}
