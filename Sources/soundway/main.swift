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
        case .version:
            print(SoundwayVersion.current)
        case .devices:
            do {
                print(try discovery.listDevicesText())
            } catch {
                fputs("soundway: failed to list devices: \(error)\n", stderr)
                exit(1)
            }
        case .status:
            do {
                let response = try SoundwayServiceControl.readStatus()
                if let status = response.status {
                    print("soundway is ready to bridge")
                    print("state: \(status.state)")
                    print("version: \(status.version)")
                    print("input: \(status.inputDevice)")
                    print("output: \(status.outputDevice)")
                    print("sample rate: \(status.sampleRate) Hz")
                    print("buffer size: \(status.bufferFrames) frames")
                } else {
                    print(response.message ?? "bridge daemon is not running")
                }
            } catch {
                let config = BridgeConfiguration.default
                do {
                    let endpoints = try discovery.resolveEndpoints(for: config)
                    print("soundway is ready to bridge")
                    print("state: not running")
                    print("version: \(SoundwayVersion.current)")
                    print("input: \(endpoints.input.name) [\(endpoints.input.id)]")
                    print("output: \(endpoints.output.name) [\(endpoints.output.id)]")
                    print("sample rate: \(config.sampleRate) Hz")
                    print("buffer size: \(config.bufferFrameSize) frames")
                } catch {
                    fputs("soundway: bridge endpoints are not fully resolved: \(error)\n", stderr)
                    exit(1)
                }
            }
        case .run:
            do {
                let daemon = try SoundwayDaemon()
                try daemon.run()
            } catch {
                fputs("soundway: failed to run bridge: \(error)\n", stderr)
                exit(1)
            }
        case .serve:
            do {
                let daemon = try SoundwayDaemon()
                try daemon.run()
            } catch {
                fputs("soundway: failed to serve bridge: \(error)\n", stderr)
                exit(1)
            }
        case .start:
            do {
                let executableURL = URL(fileURLWithPath: CommandLine.arguments.first ?? "")
                try SoundwayServiceControl.startBackgroundDaemon(executableURL: executableURL)
                print("soundway bridge started")
            } catch {
                fputs("soundway: failed to start bridge: \(error)\n", stderr)
                exit(1)
            }
        case .stop:
            do {
                let response = try SoundwayServiceControl.stopDaemon()
                print(response.message ?? "soundway bridge stopped")
            } catch {
                fputs("soundway: failed to stop bridge: \(error)\n", stderr)
                exit(1)
            }
        }
    }
}
