import Foundation
import SoundwayCore

@main
struct SoundwayCLI {
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let command = CLICommand(arguments: arguments)

        switch command {
        case .help:
            print(CLIHelp.text)
        case .status:
            let config = BridgeConfiguration.default
            print("soundway is ready to bridge")
            print("input: \(config.inputDeviceName)")
            print("output: \(config.outputDeviceName)")
            print("sample rate: \(config.sampleRate) Hz")
        case .start:
            print("starting bridge stub")
        case .stop:
            print("stopping bridge stub")
        }
    }
}
