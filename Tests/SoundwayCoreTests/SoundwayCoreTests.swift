import Testing
@testable import SoundwayCore

@Test func defaultConfigurationUsesExpectedDevices() {
    let config = BridgeConfiguration.default

    #expect(config.inputDeviceName == "Audient iD14 MKII")
    #expect(config.outputDeviceName == "BlackHole 2ch")
    #expect(config.sampleRate == 48_000)
    #expect(config.bufferFrameSize == 256)
}

@Test func commandParsingRecognizesKnownCommands() {
    #expect(CLICommand(arguments: ["version"]) == .version)
    #expect(CLICommand(arguments: ["--version"]) == .version)
    #expect(CLICommand(arguments: ["-v"]) == .version)
    #expect(CLICommand(arguments: ["status"]) == .status)
    #expect(CLICommand(arguments: ["devices"]) == .devices)
    #expect(CLICommand(arguments: ["list-devices"]) == .devices)
    #expect(CLICommand(arguments: ["run"]) == .run)
    #expect(CLICommand(arguments: ["bridge"]) == .run)
    #expect(CLICommand(arguments: ["start"]) == .start)
    #expect(CLICommand(arguments: ["stop"]) == .stop)
    #expect(CLICommand(arguments: ["nope"]) == .help)
    #expect(CLICommand(arguments: []) == .help)
}

@Test func nameNormalizationIgnoresCaseAndWhitespace() {
    #expect(AudioDeviceDiscovery.normalizeName("  BlackHole 2CH ") == "blackhole 2ch")
}

@Test func currentVersionTracksRepoState() {
    #expect(SoundwayVersion.current == "0.3.0")
}
