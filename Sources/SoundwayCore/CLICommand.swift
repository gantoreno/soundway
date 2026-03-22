import Foundation

public enum CLICommand: Sendable, Equatable {
    case help
    case status
    case devices
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
        case "devices", "list-devices":
            self = .devices
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
      soundway devices
      soundway status
      soundway start
      soundway stop

    Commands:
      devices Show all available audio devices.
      status  Show the current bridge configuration.
      start   Start the bridge process.
      stop    Stop the bridge process.
    """
}
