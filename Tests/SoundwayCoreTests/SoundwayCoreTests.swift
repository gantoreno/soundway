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
    #expect(CLICommand(arguments: ["status"]) == .status)
    #expect(CLICommand(arguments: ["devices"]) == .devices)
    #expect(CLICommand(arguments: ["list-devices"]) == .devices)
    #expect(CLICommand(arguments: ["start"]) == .start)
    #expect(CLICommand(arguments: ["stop"]) == .stop)
    #expect(CLICommand(arguments: ["nope"]) == .help)
    #expect(CLICommand(arguments: []) == .help)
}

@Test func nameNormalizationIgnoresCaseAndWhitespace() {
    #expect(AudioDeviceDiscovery.normalizeName("  BlackHole 2CH ") == "blackhole 2ch")
}
