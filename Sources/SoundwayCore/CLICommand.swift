import Foundation

public enum CLICommand: Sendable, Equatable {
    case help
    case status
    case start
    case stop

    public init(arguments: [String]) {
        guard let first = arguments.first else {
            self = .help
            return
        }

        switch first.lowercased() {
        case "status":
            self = .status
        case "start":
            self = .start
        case "stop":
            self = .stop
        default:
            self = .help
        }
    }
}

public enum CLIHelp {
    public static let text = """
    soundway - a small macOS audio bridge helper

    Usage:
      soundway status
      soundway start
      soundway stop

    Commands:
      status  Show the current bridge configuration.
      start   Start the bridge process.
      stop    Stop the bridge process.
    """
}
