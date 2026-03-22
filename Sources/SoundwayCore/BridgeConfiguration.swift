import Foundation

public struct BridgeConfiguration: Sendable, Equatable {
    public var inputDeviceName: String
    public var outputDeviceName: String
    public var sampleRate: Double
    public var bufferFrameSize: UInt32

    public init(
        inputDeviceName: String,
        outputDeviceName: String,
        sampleRate: Double,
        bufferFrameSize: UInt32
    ) {
        self.inputDeviceName = inputDeviceName
        self.outputDeviceName = outputDeviceName
        self.sampleRate = sampleRate
        self.bufferFrameSize = bufferFrameSize
    }
}

public extension BridgeConfiguration {
    static let `default` = BridgeConfiguration(
        inputDeviceName: "Audient iD14 MKII",
        outputDeviceName: "BlackHole 2ch",
        sampleRate: 48_000,
        bufferFrameSize: 256
    )
}
