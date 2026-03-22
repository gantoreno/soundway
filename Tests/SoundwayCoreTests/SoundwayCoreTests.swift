import Foundation
import Darwin
import Testing
@testable import SoundwayCore

@Test func defaultConfigurationUsesExpectedDevices() {
    let config = BridgeConfiguration.default

    #expect(config.inputDeviceName == "Audient iD14")
    #expect(config.outputDeviceName == "BlackHole 2ch")
    #expect(config.sampleRate == 48_000)
    #expect(config.bufferFrameSize == 256)
    #expect(config.outputChannelMap.isEmpty)
}

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

@Test func cliOptionsParseDeviceAndRoutingOverrides() throws {
    let options = try SoundwayCLIOptions.parse(arguments: [
        "--input-device", "Audient iD14",
        "--output-device=BlackHole 2ch",
        "--sample-rate", "48000",
        "--buffer-size=512",
        "--route", "3,4"
    ])

    #expect(options.inputDeviceName == "Audient iD14")
    #expect(options.outputDeviceName == "BlackHole 2ch")
    #expect(options.sampleRate == 48_000)
    #expect(options.bufferFrameSize == 512)
    #expect(options.outputChannelMap == [3, 4])
}

@Test func configurationStoreRoundTripsToDisk() throws {
    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("soundway-tests-\(UUID().uuidString)")
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

@Test func executableResolutionFindsBinaryOnPath() throws {
    let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("soundway-bin-\(UUID().uuidString)", isDirectory: true)
    let executableURL = tempDirectory.appendingPathComponent("soundway")

    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: executableURL.path, contents: Data("#!/bin/sh\nexit 0\n".utf8))
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
    #expect(SoundwayVersion.current == "0.6.0")
}
