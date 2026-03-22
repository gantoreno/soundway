import Foundation

public struct BridgeConfiguration: Sendable, Equatable, Codable {
    public var inputDeviceName: String
    public var outputDeviceName: String
    public var sampleRate: Double
    public var bufferFrameSize: UInt32
    public var outputChannelMap: [Int]

    public init(
        inputDeviceName: String,
        outputDeviceName: String,
        sampleRate: Double,
        bufferFrameSize: UInt32,
        outputChannelMap: [Int] = []
    ) {
        self.inputDeviceName = inputDeviceName
        self.outputDeviceName = outputDeviceName
        self.sampleRate = sampleRate
        self.bufferFrameSize = bufferFrameSize
        self.outputChannelMap = outputChannelMap
    }
}

public extension BridgeConfiguration {
    static let `default` = BridgeConfiguration(
        inputDeviceName: "Audient iD14",
        outputDeviceName: "BlackHole 2ch",
        sampleRate: 48_000,
        bufferFrameSize: 256,
        outputChannelMap: []
    )
}
