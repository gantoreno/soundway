import Foundation
import CoreAudio
import SoundwayCore

@main
struct SoundwayCLI {
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let command = CLICommand(arguments: arguments)
        let optionArguments = Array(arguments.dropFirst())
        let configurationStore = SoundwayConfigurationStore()
        let configurationResolver = SoundwayConfigurationResolver(store: configurationStore)
        let discovery = AudioDeviceDiscovery()
        let serviceControl: any SoundwayServiceControlling = SoundwayServiceController()
        let cliOptions: SoundwayCLIOptions

        do {
            cliOptions = try SoundwayCLIOptions.parse(arguments: optionArguments)
        } catch {
            fputs("soundway: invalid options: \(error)\n", stderr)
            exit(1)
        }

        func resolvedConfiguration() -> BridgeConfiguration {
            configurationResolver.resolve(overrides: cliOptions)
        }

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
                let response = try serviceControl.readStatus()
                if let status = response.status {
                    print("soundway is ready to bridge")
                    print("state: \(status.state)")
                    print("version: \(status.version)")
                    print("input: \(status.inputDevice)")
                    print("output: \(status.outputDevice)")
                    print("input channels: \(status.inputChannels)")
                    print("output channels: \(status.outputChannels)")
                    print("channel routing: \(SoundwayStatusFormatting.describeRouting(status.outputChannelMap))")
                    print("sample rate: \(status.sampleRate) Hz")
                    print("buffer size: \(status.bufferFrames) frames")
                    print("captured frames: \(status.capturedFrames)")
                    print("rendered frames: \(status.renderedFrames)")
                    print("input peak: \(status.inputPeak)")
                    print("output peak: \(status.outputPeak)")
                    print("input callbacks: \(status.inputCallbackCount)")
                    print("output callbacks: \(status.outputCallbackCount)")
                    print("last input render status: \(status.lastInputRenderStatus)")
                    print("last output render status: \(status.lastOutputRenderStatus)")
                } else {
                    print(response.message ?? "bridge daemon is not running")
                }
            } catch {
                let config = resolvedConfiguration()
                do {
                    let endpoints = try discovery.resolveEndpoints(for: config)
                    print("soundway is ready to bridge")
                    print("state: not running")
                    print("version: \(SoundwayVersion.current)")
                    print("input: \(endpoints.input.name) [\(endpoints.input.id)]")
                    print("output: \(endpoints.output.name) [\(endpoints.output.id)]")
                    let inputChannels = try discovery.channelCount(for: endpoints.input.id, scope: kAudioObjectPropertyScopeInput)
                    let outputChannels = try discovery.channelCount(for: endpoints.output.id, scope: kAudioObjectPropertyScopeOutput)
                    print("input channels: \(inputChannels)")
                    print("output channels: \(outputChannels)")
                    print("channel routing: \(SoundwayStatusFormatting.describeRouting(config.outputChannelMap))")
                    print("sample rate: \(config.sampleRate) Hz")
                    print("buffer size: \(config.bufferFrameSize) frames")
                    print("captured frames: 0")
                    print("rendered frames: 0")
                    print("input peak: 0")
                    print("output peak: 0")
                    print("input callbacks: 0")
                    print("output callbacks: 0")
                    print("last input render status: 0")
                    print("last output render status: 0")
                } catch {
                    fputs("soundway: bridge endpoints are not fully resolved: \(error)\n", stderr)
                    exit(1)
                }
            }
        case .run:
            do {
                let configuration = resolvedConfiguration()
                if !cliOptions.isEmpty {
                    try configurationStore.save(configuration)
                }
                let daemon = try SoundwayDaemon(configuration: configuration)
                try daemon.run()
            } catch {
                fputs("soundway: failed to run bridge: \(error)\n", stderr)
                exit(1)
            }
        case .serve:
            do {
                let configuration = resolvedConfiguration()
                if !cliOptions.isEmpty {
                    try configurationStore.save(configuration)
                }
                let daemon = try SoundwayDaemon(configuration: configuration)
                try daemon.run()
            } catch {
                fputs("soundway: failed to serve bridge: \(error)\n", stderr)
                exit(1)
            }
        case .start:
            do {
                let configuration = resolvedConfiguration()
                if !cliOptions.isEmpty {
                    try configurationStore.save(configuration)
                }
                guard let executableName = CommandLine.arguments.first,
                      let executableURL = serviceControl.resolveExecutableURL(commandName: executableName, environment: ProcessInfo.processInfo.environment) else {
                    throw SoundwayServiceError.daemonLaunchFailed("could not resolve the soundway executable")
                }
                try serviceControl.startBackgroundDaemon(executableURL: executableURL)
                print("soundway bridge started")
            } catch {
                fputs("soundway: failed to start bridge: \(error)\n", stderr)
                exit(1)
            }
        case .stop:
            do {
                let response = try serviceControl.stopDaemon()
                print(response.message ?? "soundway bridge stopped")
            } catch {
                fputs("soundway: failed to stop bridge: \(error)\n", stderr)
                exit(1)
            }
        }
    }
}
