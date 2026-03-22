import Foundation

public struct SoundwayConfigurationStore: Sendable, Equatable, SoundwayConfigurationLoading,
  SoundwayConfigurationSaving
{
  public let url: URL

  public init(url: URL = Self.defaultURL) {
    self.url = url
  }

  public static var defaultURL: URL {
    let fileManager = FileManager.default
    let baseDirectory =
      fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? fileManager.temporaryDirectory
    return
      baseDirectory
      .appendingPathComponent("soundway", isDirectory: true)
      .appendingPathComponent("config.json")
  }

  public func load() throws -> BridgeConfiguration? {
    guard FileManager.default.fileExists(atPath: url.path) else {
      return nil
    }

    let data = try Data(contentsOf: url)
    return try JSONDecoder().decode(BridgeConfiguration.self, from: data)
  }

  public func save(_ configuration: BridgeConfiguration) throws {
    let directoryURL = url.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(configuration)
    try data.write(to: url, options: [.atomic])
  }
}
