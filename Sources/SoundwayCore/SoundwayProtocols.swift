import CoreAudio
import Foundation

/// Provides device lookup and discovery for the bridge layer.
public protocol SoundwayDeviceDiscovering {
  func devices() throws -> [AudioDeviceInfo]
  func resolveEndpoints(for configuration: BridgeConfiguration) throws -> ResolvedBridgeEndpoints
  func channelCount(for deviceID: AudioDeviceID, scope: AudioObjectPropertyScope) throws -> UInt32
  func listDevicesText() throws -> String
}

/// Loads the persisted bridge configuration, if one exists.
public protocol SoundwayConfigurationLoading {
  func load() throws -> BridgeConfiguration?
}

/// Persists the bridge configuration for later runs.
public protocol SoundwayConfigurationSaving {
  func save(_ configuration: BridgeConfiguration) throws
}

/// Controls the daemon lifecycle and IPC entry points used by the CLI.
public protocol SoundwayServiceControlling {
  func readStatus() throws -> SoundwayServiceResponse
  func stopDaemon() throws -> SoundwayServiceResponse
  func startBackgroundDaemon(executableURL: URL) throws
  func resolveExecutableURL(commandName: String, environment: [String: String]) -> URL?
}

internal protocol SoundwayBridgeStatusProviding {
  func makeStatus() -> SoundwayServiceStatus
}
