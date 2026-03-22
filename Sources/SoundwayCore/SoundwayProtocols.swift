import CoreAudio
import Foundation

public protocol SoundwayDeviceDiscovering {
    func devices() throws -> [AudioDeviceInfo]
    func resolveEndpoints(for configuration: BridgeConfiguration) throws -> ResolvedBridgeEndpoints
    func channelCount(for deviceID: AudioDeviceID, scope: AudioObjectPropertyScope) throws -> UInt32
    func listDevicesText() throws -> String
}

public protocol SoundwayConfigurationLoading {
    func load() throws -> BridgeConfiguration?
}

public protocol SoundwayConfigurationSaving {
    func save(_ configuration: BridgeConfiguration) throws
}

public protocol SoundwayServiceControlling {
    func readStatus() throws -> SoundwayServiceResponse
    func stopDaemon() throws -> SoundwayServiceResponse
    func startBackgroundDaemon(executableURL: URL) throws
    func resolveExecutableURL(commandName: String, environment: [String: String]) -> URL?
}

internal protocol SoundwayBridgeStatusProviding {
    func makeStatus() -> SoundwayServiceStatus
}

