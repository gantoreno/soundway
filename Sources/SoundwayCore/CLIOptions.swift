import Foundation

public enum SoundwayCLIOptionsError: Error, Sendable, Equatable {
  case missingValue(String)
  case invalidDouble(String)
  case invalidUInt32(String)
  case invalidRoute(String)
  case unknownOption(String)
}

public struct SoundwayCLIOptions: Sendable, Equatable {
  public var inputDeviceName: String?
  public var outputDeviceName: String?
  public var sampleRate: Double?
  public var bufferFrameSize: UInt32?
  public var outputChannelMap: [Int]?

  public init(
    inputDeviceName: String? = nil,
    outputDeviceName: String? = nil,
    sampleRate: Double? = nil,
    bufferFrameSize: UInt32? = nil,
    outputChannelMap: [Int]? = nil
  ) {
    self.inputDeviceName = inputDeviceName
    self.outputDeviceName = outputDeviceName
    self.sampleRate = sampleRate
    self.bufferFrameSize = bufferFrameSize
    self.outputChannelMap = outputChannelMap
  }

  public var isEmpty: Bool {
    inputDeviceName == nil
      && outputDeviceName == nil
      && sampleRate == nil
      && bufferFrameSize == nil
      && outputChannelMap == nil
  }

  public func applying(to configuration: BridgeConfiguration) -> BridgeConfiguration {
    BridgeConfiguration(
      inputDeviceName: inputDeviceName ?? configuration.inputDeviceName,
      outputDeviceName: outputDeviceName ?? configuration.outputDeviceName,
      sampleRate: sampleRate ?? configuration.sampleRate,
      bufferFrameSize: bufferFrameSize ?? configuration.bufferFrameSize,
      outputChannelMap: outputChannelMap ?? configuration.outputChannelMap
    )
  }

  public static func parse(arguments: [String]) throws -> SoundwayCLIOptions {
    var iterator = arguments.makeIterator()
    var options = SoundwayCLIOptions()

    while let argument = iterator.next() {
      if let parsed = parseInlineOption(argument) {
        options = options.merging(parsed)
        continue
      }

      switch argument {
      case "--input-device", "-i":
        options.inputDeviceName = try nextValue(after: argument, iterator: &iterator)
      case "--output-device", "-o":
        options.outputDeviceName = try nextValue(after: argument, iterator: &iterator)
      case "--sample-rate", "-s":
        let value = try nextValue(after: argument, iterator: &iterator)
        guard let rate = Double(value) else {
          throw SoundwayCLIOptionsError.invalidDouble(value)
        }
        options.sampleRate = rate
      case "--buffer-size", "-b":
        let value = try nextValue(after: argument, iterator: &iterator)
        guard let size = UInt32(value) else {
          throw SoundwayCLIOptionsError.invalidUInt32(value)
        }
        options.bufferFrameSize = size
      case "--route", "-r":
        let value = try nextValue(after: argument, iterator: &iterator)
        options.outputChannelMap = try parseRoute(value)
      case "--help", "-h":
        continue
      default:
        throw SoundwayCLIOptionsError.unknownOption(argument)
      }
    }

    return options
  }

  private static func parseInlineOption(
    _ argument: String
  ) -> SoundwayCLIOptions? {
    guard let equalsIndex = argument.firstIndex(of: "="), argument.hasPrefix("--") else {
      return nil
    }

    let key = String(argument[..<equalsIndex])
    let value = String(argument[argument.index(after: equalsIndex)...])

    switch key {
    case "--input-device":
      return SoundwayCLIOptions(inputDeviceName: value)
    case "--output-device":
      return SoundwayCLIOptions(outputDeviceName: value)
    case "--sample-rate":
      guard let rate = Double(value) else {
        return nil
      }
      return SoundwayCLIOptions(sampleRate: rate)
    case "--buffer-size":
      guard let size = UInt32(value) else {
        return nil
      }
      return SoundwayCLIOptions(bufferFrameSize: size)
    case "--route":
      guard let route = try? parseRoute(value) else {
        return nil
      }
      return SoundwayCLIOptions(outputChannelMap: route)
    default:
      return nil
    }
  }

  private static func nextValue(after option: String, iterator: inout Array<String>.Iterator) throws
    -> String
  {
    guard let value = iterator.next() else {
      throw SoundwayCLIOptionsError.missingValue(option)
    }
    return value
  }

  private static func parseRoute(_ value: String) throws -> [Int] {
    let parts =
      value
      .split(whereSeparator: { ",:;".contains($0) })
      .map(String.init)
    guard !parts.isEmpty else {
      throw SoundwayCLIOptionsError.invalidRoute(value)
    }

    var route: [Int] = []
    route.reserveCapacity(parts.count)
    for part in parts {
      guard let channel = Int(part), channel >= 0 else {
        throw SoundwayCLIOptionsError.invalidRoute(value)
      }
      route.append(channel)
    }
    return route
  }

  private func merging(_ other: SoundwayCLIOptions) -> SoundwayCLIOptions {
    SoundwayCLIOptions(
      inputDeviceName: other.inputDeviceName ?? inputDeviceName,
      outputDeviceName: other.outputDeviceName ?? outputDeviceName,
      sampleRate: other.sampleRate ?? sampleRate,
      bufferFrameSize: other.bufferFrameSize ?? bufferFrameSize,
      outputChannelMap: other.outputChannelMap ?? outputChannelMap
    )
  }
}
