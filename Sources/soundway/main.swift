import Foundation
import SoundwayCore

@main
struct SoundwayCLI {
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let command = CLICommand(arguments: arguments)
        let discovery = AudioDeviceDiscovery()

        switch command {
        case .help:
            print(CLIHelp.text)
        case .devices:
            do {
                print(try discovery.listDevicesText())
            } catch {
                fputs("soundway: failed to list devices: \(error)\n", stderr)
                exit(1)
            }
        case .status:
            let config = BridgeConfiguration.default
            do {
                let endpoints = try discovery.resolveEndpoints(for: config)
                print("soundway is ready to bridge")
                print("input: \(endpoints.input.name) [\(endpoints.input.id)]")
                print("output: \(endpoints.output.name) [\(endpoints.output.id)]")
                print("sample rate: \(config.sampleRate) Hz")
                print("buffer size: \(config.bufferFrameSize) frames")
            } catch {
                fputs("soundway: bridge endpoints are not fully resolved: \(error)\n", stderr)
                exit(1)
            }
        case .start:
            print("starting bridge stub")
        case .stop:
            print("stopping bridge stub")
        }
    }
}
