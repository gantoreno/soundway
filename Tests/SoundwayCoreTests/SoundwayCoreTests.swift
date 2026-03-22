import AudioToolbox
import Darwin
import Foundation
import Testing

@testable import SoundwayCore

// MARK: - Defaults

@Test func defaultConfigurationUsesExpectedDevices() {
  let config = BridgeConfiguration.default

  #expect(config.inputDeviceName == "Audient iD14")
  #expect(config.outputDeviceName == "BlackHole 2ch")
  #expect(config.sampleRate == 48_000)
  #expect(config.bufferFrameSize == 256)
  #expect(config.outputChannelMap.isEmpty)
}

// MARK: - CLI

@Test func commandParsingRecognizesKnownCommands() {
  #expect(CLICommand(arguments: ["version"]) == .version)
  #expect(CLICommand(arguments: ["--version"]) == .version)
  #expect(CLICommand(arguments: ["-v"]) == .version)
  #expect(CLICommand(arguments: ["status"]) == .status)
  #expect(CLICommand(arguments: ["devices"]) == .devices)
  #expect(CLICommand(arguments: ["list-devices"]) == .devices)
  #expect(CLICommand(arguments: ["run"]) == .run)
  #expect(CLICommand(arguments: ["serve"]) == .serve)
  #expect(CLICommand(arguments: ["bridge"]) == .run)
  #expect(CLICommand(arguments: ["start"]) == .start)
  #expect(CLICommand(arguments: ["stop"]) == .stop)
  #expect(CLICommand(arguments: ["nope"]) == .help)
  #expect(CLICommand(arguments: []) == .help)
}

@Test func nameNormalizationIgnoresCaseAndWhitespace() {
  #expect(AudioDeviceDiscovery.normalizeName("  BlackHole 2CH ") == "blackhole 2ch")
}

@Test func routingDescriptionFormatsIdentityAndMappedRoutes() {
  #expect(SoundwayStatusFormatting.describeRouting([]) == "identity")
  #expect(SoundwayStatusFormatting.describeRouting([3, 4]) == "1->3, 2->4")
}

@Test func cliOptionsParseDeviceAndRoutingOverrides() throws {
  let options = try SoundwayCLIOptions.parse(arguments: [
    "--input-device", "Audient iD14",
    "--output-device=BlackHole 2ch",
    "--sample-rate", "48000",
    "--buffer-size=512",
    "--route", "3,4",
  ])

  #expect(options.inputDeviceName == "Audient iD14")
  #expect(options.outputDeviceName == "BlackHole 2ch")
  #expect(options.sampleRate == 48_000)
  #expect(options.bufferFrameSize == 512)
  #expect(options.outputChannelMap == [3, 4])
}

// MARK: - Configuration

@Test func configurationResolverHonorsSavedConfigAndOverrides() {
  let savedConfiguration = BridgeConfiguration(
    inputDeviceName: "Interface A",
    outputDeviceName: "BlackHole 2ch",
    sampleRate: 44_100,
    bufferFrameSize: 128,
    outputChannelMap: [5, 6]
  )
  let resolver = SoundwayConfigurationResolver(
    store: MockConfigurationStore(configuration: savedConfiguration))

  let overrideOnly = resolver.resolve(overrides: SoundwayCLIOptions())
  #expect(overrideOnly == savedConfiguration)

  let overridden = resolver.resolve(
    overrides: SoundwayCLIOptions(inputDeviceName: "Interface B", outputChannelMap: [1, 2]))
  #expect(overridden.inputDeviceName == "Interface B")
  #expect(overridden.outputDeviceName == "BlackHole 2ch")
  #expect(overridden.sampleRate == 44_100)
  #expect(overridden.bufferFrameSize == 128)
  #expect(overridden.outputChannelMap == [1, 2])

  let fallbackResolver = SoundwayConfigurationResolver(
    store: MockConfigurationStore(configuration: nil))
  let fallback = fallbackResolver.resolve(overrides: SoundwayCLIOptions())
  #expect(fallback == BridgeConfiguration.default)
}

// MARK: - Routing

@Test func bridgeProcessorIdentityRoutingCopiesExpectedChannels() {
  let processor = SoundwayBridgeProcessor(
    settings: .init(
      sampleRate: 48_000,
      inputChannelCount: 2,
      outputChannelCount: 2,
      maximumFramesPerSlice: 64,
      outputChannelMap: []
    ))

  processor.capture(
    input: SoundwayAudioBlock(channels: [
      [1, 2, 3],
      [10, 20, 30],
    ]))

  let output = processor.renderOutput(frameCount: 3)
  #expect(
    output.channels == [
      [1, 2, 3],
      [10, 20, 30],
    ])

  let telemetry = processor.telemetry()
  #expect(telemetry.capturedFrames == 3)
  #expect(telemetry.renderedFrames == 3)
  #expect(telemetry.inputPeak == 30)
  #expect(telemetry.outputPeak == 30)
  #expect(telemetry.inputCallbackCount == 1)
  #expect(telemetry.outputCallbackCount == 1)
  #expect(telemetry.lastInputRenderStatus == noErr)
  #expect(telemetry.lastOutputRenderStatus == noErr)
}

@Test func bridgeProcessorCustomRoutingMapsTheRightChannels() {
  let processor = SoundwayBridgeProcessor(
    settings: .init(
      sampleRate: 48_000,
      inputChannelCount: 4,
      outputChannelCount: 2,
      maximumFramesPerSlice: 64,
      outputChannelMap: [3, 4]
    ))

  processor.capture(
    input: SoundwayAudioBlock(channels: [
      [1, 2, 3],
      [11, 12, 13],
      [21, 22, 23],
      [31, 32, 33],
    ]))

  let output = processor.renderOutput(frameCount: 3)
  #expect(
    output.channels == [
      [21, 22, 23],
      [31, 32, 33],
    ])
}

@Test func bridgeProcessorInvalidRoutingFallsBackToSilence() {
  let processor = SoundwayBridgeProcessor(
    settings: .init(
      sampleRate: 48_000,
      inputChannelCount: 2,
      outputChannelCount: 2,
      maximumFramesPerSlice: 64,
      outputChannelMap: [99, 0]
    ))

  processor.capture(
    input: SoundwayAudioBlock(channels: [
      [1, 2],
      [3, 4],
    ]))

  let output = processor.renderOutput(frameCount: 2)
  #expect(
    output.channels == [
      [0, 0],
      [0, 0],
    ])
}

@Test func bridgeProcessorSilenceStaysSilent() {
  let processor = SoundwayBridgeProcessor(
    settings: .init(
      sampleRate: 48_000,
      inputChannelCount: 2,
      outputChannelCount: 2,
      maximumFramesPerSlice: 64,
      outputChannelMap: []
    ))

  let output = processor.renderOutput(frameCount: 4)
  #expect(
    output.channels == [
      [0, 0, 0, 0],
      [0, 0, 0, 0],
    ])

  let telemetry = processor.telemetry()
  #expect(telemetry.capturedFrames == 0)
  #expect(telemetry.renderedFrames == 0)
  #expect(telemetry.outputPeak == 0)
}

@Test func bridgeProcessorWraparoundPreservesOrder() {
  let processor = SoundwayBridgeProcessor(
    settings: .init(
      sampleRate: 48_000,
      inputChannelCount: 1,
      outputChannelCount: 1,
      maximumFramesPerSlice: 64,
      outputChannelMap: []
    ))

  processor.capture(
    input: SoundwayAudioBlock(channels: [
      Array(0..<600).map(Float.init)
    ]))
  processor.capture(
    input: SoundwayAudioBlock(channels: [
      Array(600..<1200).map(Float.init)
    ]))

  let output = processor.renderOutput(frameCount: 1_024)
  let expected = Array(176..<1_200).map(Float.init)
  #expect(output.channels == [expected])

  let telemetry = processor.telemetry()
  #expect(telemetry.capturedFrames == 1_200)
  #expect(telemetry.renderedFrames == 1_024)
}

@Test func bridgeProcessorCallbackStyleApisAvoidIntermediateBlocks() {
  let processor = SoundwayBridgeProcessor(
    settings: .init(
      sampleRate: 48_000,
      inputChannelCount: 2,
      outputChannelCount: 2,
      maximumFramesPerSlice: 64,
      outputChannelMap: []
    ))

  let inputStorage0 = UnsafeMutablePointer<Float>.allocate(capacity: 3)
  let inputStorage1 = UnsafeMutablePointer<Float>.allocate(capacity: 3)
  inputStorage0.initialize(from: [1, 2, 3], count: 3)
  inputStorage1.initialize(from: [10, 20, 30], count: 3)

  let inputBufferList = AudioBufferList.allocate(maximumBuffers: 2)
  defer {
    inputBufferList.unsafeMutablePointer.deallocate()
    inputStorage0.deallocate()
    inputStorage1.deallocate()
  }
  inputBufferList[0] = AudioBuffer(
    mNumberChannels: 1,
    mDataByteSize: UInt32(3 * MemoryLayout<Float>.stride),
    mData: inputStorage0
  )
  inputBufferList[1] = AudioBuffer(
    mNumberChannels: 1,
    mDataByteSize: UInt32(3 * MemoryLayout<Float>.stride),
    mData: inputStorage1
  )

  #expect(processor.capture(input: inputBufferList, frameCount: 3) == noErr)

  let outputStorage0 = UnsafeMutablePointer<Float>.allocate(capacity: 3)
  let outputStorage1 = UnsafeMutablePointer<Float>.allocate(capacity: 3)
  outputStorage0.initialize(repeating: 0, count: 3)
  outputStorage1.initialize(repeating: 0, count: 3)

  let outputBufferList = AudioBufferList.allocate(maximumBuffers: 2)
  defer {
    outputBufferList.unsafeMutablePointer.deallocate()
    outputStorage0.deallocate()
    outputStorage1.deallocate()
  }
  outputBufferList[0] = AudioBuffer(
    mNumberChannels: 1,
    mDataByteSize: UInt32(3 * MemoryLayout<Float>.stride),
    mData: outputStorage0
  )
  outputBufferList[1] = AudioBuffer(
    mNumberChannels: 1,
    mDataByteSize: UInt32(3 * MemoryLayout<Float>.stride),
    mData: outputStorage1
  )

  #expect(processor.renderOutput(frameCount: 3, to: outputBufferList) == noErr)
  #expect(Array(UnsafeBufferPointer(start: outputStorage0, count: 3)) == [1, 2, 3])
  #expect(Array(UnsafeBufferPointer(start: outputStorage1, count: 3)) == [10, 20, 30])
}

// MARK: - Daemon

@Test func daemonRequestHandlerBuildsStatusAndStopResponses() {
  let status = SoundwayServiceStatus(
    state: "running",
    version: "0.6.0",
    inputDevice: "Audient iD14",
    outputDevice: "BlackHole 2ch",
    inputChannels: 12,
    outputChannels: 2,
    outputChannelMap: [3, 4],
    sampleRate: 48_000,
    bufferFrames: 256,
    capturedFrames: 10,
    renderedFrames: 10,
    inputPeak: 0.25,
    outputPeak: 0.25,
    inputCallbackCount: 2,
    outputCallbackCount: 2,
    lastInputRenderStatus: noErr,
    lastOutputRenderStatus: noErr
  )
  let handler = SoundwayDaemonRequestHandler(statusProvider: { status })

  let statusResult = handler.handle(.init(action: .status))
  #expect(statusResult.response.status == status)
  #expect(statusResult.shouldStop == false)

  let stopResult = handler.handle(.init(action: .stop))
  #expect(stopResult.response.message == "stopping")
  #expect(stopResult.shouldStop == true)
}

// MARK: - Persistence

@Test func configurationStoreRoundTripsToDisk() throws {
  let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(
    "soundway-tests-\(UUID().uuidString)")
  let storeURL = tempURL.appendingPathComponent("config.json")
  let store = SoundwayConfigurationStore(url: storeURL)
  let configuration = BridgeConfiguration(
    inputDeviceName: "Interface A",
    outputDeviceName: "BlackHole 2ch",
    sampleRate: 44_100,
    bufferFrameSize: 128,
    outputChannelMap: [3, 4]
  )

  defer {
    try? FileManager.default.removeItem(at: tempURL)
  }

  try store.save(configuration)
  let loaded = try #require(try store.load())

  #expect(loaded == configuration)
}

// MARK: - Utilities

@Test func executableResolutionFindsBinaryOnPath() throws {
  let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
    "soundway-bin-\(UUID().uuidString)", isDirectory: true)
  let executableURL = tempDirectory.appendingPathComponent("soundway")

  try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
  FileManager.default.createFile(
    atPath: executableURL.path, contents: Data("#!/bin/sh\nexit 0\n".utf8))
  chmod(executableURL.path, 0o755)

  defer {
    try? FileManager.default.removeItem(at: tempDirectory)
  }

  let resolved = SoundwayServiceControl.resolveExecutableURL(
    commandName: "soundway",
    environment: ["PATH": tempDirectory.path]
  )

  #expect(resolved == executableURL)
}

@Test func currentVersionTracksRepoState() {
  #expect(SoundwayVersion.current == "0.7.0")
}

private struct MockConfigurationStore: SoundwayConfigurationLoading {
  let configuration: BridgeConfiguration?

  func load() throws -> BridgeConfiguration? {
    configuration
  }
}
