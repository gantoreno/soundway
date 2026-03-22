import Foundation

public enum CLICommand: Sendable, Equatable {
    case help
    case status
    case devices
    case run
    case version
    case serve
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
        case "run", "bridge":
            self = .run
        case "version", "--version", "-v":
            self = .version
        case "serve":
            self = .serve
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
      soundway --version
      soundway devices
      soundway status
      soundway run
      soundway start
      soundway stop

    Commands:
      version Show the current soundway version.
      devices Show all available audio devices.
      status  Show the current bridge configuration.
      run     Run the bridge in the foreground.
      serve   Run the bridge daemon.
      start   Start the bridge process.
      stop    Stop the bridge process.
    """
}
