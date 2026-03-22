import CoreAudio
import Foundation

public struct AudioDeviceInfo: Sendable, Equatable {
  public let id: AudioDeviceID
  public let name: String
  public let manufacturer: String?
}

public struct ResolvedBridgeEndpoints: Sendable, Equatable {
  public let input: AudioDeviceInfo
  public let output: AudioDeviceInfo
}

public enum AudioDeviceDiscoveryError: Error, Sendable, Equatable {
  case hardwareQueryFailed(OSStatus)
  case deviceNotFound(String)
  case nameQueryFailed(AudioDeviceID, OSStatus)
  case streamConfigurationQueryFailed(AudioDeviceID, OSStatus)
}

public struct AudioDeviceDiscovery: Sendable, SoundwayDeviceDiscovering {
  public init() {}

  public func devices() throws -> [AudioDeviceInfo] {
    let deviceIDs = try Self.allDeviceIDs()
    return try deviceIDs.map { id in
      try Self.deviceInfo(for: id)
    }
  }

  public func device(named targetName: String) throws -> AudioDeviceInfo {
    let normalizedTarget = Self.normalizeName(targetName)

    for device in try devices() {
      if Self.normalizeName(device.name) == normalizedTarget {
        return device
      }
    }

    throw AudioDeviceDiscoveryError.deviceNotFound(targetName)
  }

  public func resolveEndpoints(for configuration: BridgeConfiguration) throws
    -> ResolvedBridgeEndpoints
  {
    let input = try device(named: configuration.inputDeviceName)
    let output = try device(named: configuration.outputDeviceName)
    return ResolvedBridgeEndpoints(input: input, output: output)
  }

  public func channelCount(for deviceID: AudioDeviceID, scope: AudioObjectPropertyScope) throws
    -> UInt32
  {
    let format = try streamFormat(for: deviceID, scope: scope)
    return max(1, format.mChannelsPerFrame)
  }

  private func streamFormat(for deviceID: AudioDeviceID, scope: AudioObjectPropertyScope) throws
    -> AudioStreamBasicDescription
  {
    var formatAddress = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyStreamFormat,
      mScope: scope,
      mElement: kAudioObjectPropertyElementMain
    )

    var format = AudioStreamBasicDescription()
    var formatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.stride)
    let formatStatus = AudioObjectGetPropertyData(
      deviceID,
      &formatAddress,
      0,
      nil,
      &formatSize,
      &format
    )
    guard formatStatus == noErr else {
      throw AudioDeviceDiscoveryError.streamConfigurationQueryFailed(deviceID, formatStatus)
    }

    return format
  }

  public func listDevicesText() throws -> String {
    let devices = try devices()
    guard !devices.isEmpty else {
      return "No audio devices found."
    }

    return devices.map { device in
      var line = "\(device.id): \(device.name)"
      if let manufacturer = device.manufacturer, !manufacturer.isEmpty {
        line += " (\(manufacturer))"
      }
      return line
    }
    .joined(separator: "\n")
  }

  private static func allDeviceIDs() throws -> [AudioDeviceID] {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDevices,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )

    var dataSize: UInt32 = 0
    let status = AudioObjectGetPropertyDataSize(
      AudioObjectID(kAudioObjectSystemObject),
      &address,
      0,
      nil,
      &dataSize
    )
    guard status == noErr else {
      throw AudioDeviceDiscoveryError.hardwareQueryFailed(status)
    }

    let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.stride
    guard count > 0 else { return [] }

    var deviceIDs = [AudioDeviceID](repeating: 0, count: count)
    var dataSizeForQuery = dataSize
    let queryStatus = AudioObjectGetPropertyData(
      AudioObjectID(kAudioObjectSystemObject),
      &address,
      0,
      nil,
      &dataSizeForQuery,
      &deviceIDs
    )
    guard queryStatus == noErr else {
      throw AudioDeviceDiscoveryError.hardwareQueryFailed(queryStatus)
    }

    return deviceIDs
  }

  private static func deviceInfo(for deviceID: AudioDeviceID) throws -> AudioDeviceInfo {
    let name = try stringProperty(selector: kAudioObjectPropertyName, deviceID: deviceID)
    let manufacturer = try? stringProperty(
      selector: kAudioObjectPropertyManufacturer, deviceID: deviceID)
    return AudioDeviceInfo(id: deviceID, name: name, manufacturer: manufacturer)
  }

  private static func stringProperty(selector: AudioObjectPropertySelector, deviceID: AudioDeviceID)
    throws -> String
  {
    var address = AudioObjectPropertyAddress(
      mSelector: selector,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )

    var value: Unmanaged<CFString>?
    var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.stride)
    let status = AudioObjectGetPropertyData(
      deviceID,
      &address,
      0,
      nil,
      &dataSize,
      &value
    )
    guard status == noErr else {
      throw AudioDeviceDiscoveryError.nameQueryFailed(deviceID, status)
    }

    guard let value else {
      return ""
    }

    return value.takeRetainedValue() as String
  }

  static func normalizeName(_ name: String) -> String {
    name
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
  }
}
