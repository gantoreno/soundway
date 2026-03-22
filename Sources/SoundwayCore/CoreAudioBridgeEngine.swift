import AudioToolbox
import CoreAudio
import Foundation

public enum CoreAudioBridgeEngineError: Error, Sendable, Equatable {
    case audioComponentNotFound
    case audioUnitCreationFailed(OSStatus)
    case audioUnitConfigurationFailed(OSStatus)
    case audioUnitStartFailed(OSStatus)
    case audioUnitStopFailed(OSStatus)
}

public final class CoreAudioBridgeEngine {
    public struct Telemetry: Sendable, Equatable {
        public let capturedFrames: UInt64
        public let renderedFrames: UInt64
        public let inputPeak: Float
        public let outputPeak: Float
        public let inputCallbackCount: UInt64
        public let outputCallbackCount: UInt64
        public let lastInputRenderStatus: OSStatus
        public let lastOutputRenderStatus: OSStatus
    }

    public struct Settings: Sendable {
        public var sampleRate: Double
        public var inputChannelCount: UInt32
        public var outputChannelCount: UInt32
        public var maximumFramesPerSlice: UInt32
        public var outputChannelMap: [Int]

        public init(
            sampleRate: Double,
            inputChannelCount: UInt32,
            outputChannelCount: UInt32,
            maximumFramesPerSlice: UInt32,
            outputChannelMap: [Int] = []
        ) {
            self.sampleRate = sampleRate
            self.inputChannelCount = inputChannelCount
            self.outputChannelCount = outputChannelCount
            self.maximumFramesPerSlice = maximumFramesPerSlice
            self.outputChannelMap = outputChannelMap
        }
    }

    public enum State: Sendable, Equatable {
        case stopped
        case running
    }

    private let endpoints: ResolvedBridgeEndpoints
    private let settings: Settings
    private let processor: SoundwayBridgeProcessor
    private let sampleBufferLock = NSLock()
    private let inputChannelBuffers: [UnsafeMutablePointer<Float>]
    private let inputFrameCapacity: Int
    private let inputBufferList: UnsafeMutableAudioBufferListPointer
    private let effectiveMaximumFramesPerSlice: UInt32
    private var inputUnit: AudioUnit?
    private var outputUnit: AudioUnit?
    private var state: State = .stopped
    private var isTransitioning = false

    public init(endpoints: ResolvedBridgeEndpoints, settings: Settings) {
        self.endpoints = endpoints
        self.settings = settings
        let effectiveMaximumFramesPerSlice = max(settings.maximumFramesPerSlice, 4096)
        self.effectiveMaximumFramesPerSlice = effectiveMaximumFramesPerSlice
        self.processor = SoundwayBridgeProcessor(settings: .init(
            sampleRate: settings.sampleRate,
            inputChannelCount: settings.inputChannelCount,
            outputChannelCount: settings.outputChannelCount,
            maximumFramesPerSlice: settings.maximumFramesPerSlice,
            outputChannelMap: settings.outputChannelMap
        ))

        let inputFrameCapacity = max(Int(effectiveMaximumFramesPerSlice) * 2, 4096)
        self.inputFrameCapacity = inputFrameCapacity
        let inputChannelBuffers = (0..<max(1, Int(settings.inputChannelCount))).map { _ in
            let buffer = UnsafeMutablePointer<Float>.allocate(capacity: inputFrameCapacity)
            buffer.initialize(repeating: 0, count: inputFrameCapacity)
            return buffer
        }
        self.inputChannelBuffers = inputChannelBuffers

        self.inputBufferList = AudioBufferList.allocate(maximumBuffers: max(1, Int(settings.inputChannelCount)))
        for channel in 0..<max(1, Int(settings.inputChannelCount)) {
            self.inputBufferList[channel] = AudioBuffer(
                mNumberChannels: 1,
                mDataByteSize: UInt32(inputFrameCapacity * MemoryLayout<Float>.stride),
                mData: inputChannelBuffers[channel]
            )
        }
    }

    deinit {
        stop()
        for buffer in inputChannelBuffers {
            buffer.deallocate()
        }
    }

    public var currentState: State {
        sampleBufferLock.lock()
        defer { sampleBufferLock.unlock() }
        return state
    }

    public func start() throws {
        sampleBufferLock.lock()
        guard state == .stopped, !isTransitioning else {
            sampleBufferLock.unlock()
            return
        }
        isTransitioning = true
        sampleBufferLock.unlock()

        let inputFormat = makeStreamFormat(channelCount: settings.inputChannelCount)
        let outputFormat = makeStreamFormat(channelCount: settings.outputChannelCount)
        do {
            let inputUnit = try createHALOutputUnit(
                deviceID: endpoints.input.id,
                enableInput: true,
                enableOutput: false,
                format: inputFormat,
                maximumFramesPerSlice: effectiveMaximumFramesPerSlice
            )
            let outputUnit = try createHALOutputUnit(
                deviceID: endpoints.output.id,
                enableInput: false,
                enableOutput: true,
                format: outputFormat,
                maximumFramesPerSlice: effectiveMaximumFramesPerSlice
            )

            let inputContext = Unmanaged.passUnretained(self).toOpaque()
            let outputContext = Unmanaged.passUnretained(self).toOpaque()
            var inputCallback = AURenderCallbackStruct(inputProc: Self.inputDeviceCallback, inputProcRefCon: inputContext)
            var outputCallback = AURenderCallbackStruct(inputProc: Self.outputDeviceCallback, inputProcRefCon: outputContext)

            let inputCallbackStatus = AudioUnitSetProperty(
                inputUnit,
                kAudioOutputUnitProperty_SetInputCallback,
                kAudioUnitScope_Global,
                0,
                &inputCallback,
                UInt32(MemoryLayout<AURenderCallbackStruct>.stride)
            )
            guard inputCallbackStatus == noErr else {
                _ = AudioComponentInstanceDispose(inputUnit)
                _ = AudioComponentInstanceDispose(outputUnit)
                throw CoreAudioBridgeEngineError.audioUnitConfigurationFailed(inputCallbackStatus)
            }

            let outputCallbackStatus = AudioUnitSetProperty(
                outputUnit,
                kAudioUnitProperty_SetRenderCallback,
                kAudioUnitScope_Input,
                0,
                &outputCallback,
                UInt32(MemoryLayout<AURenderCallbackStruct>.stride)
            )
            guard outputCallbackStatus == noErr else {
                _ = AudioComponentInstanceDispose(inputUnit)
                _ = AudioComponentInstanceDispose(outputUnit)
                throw CoreAudioBridgeEngineError.audioUnitConfigurationFailed(outputCallbackStatus)
            }

            let inputStartStatus = AudioOutputUnitStart(inputUnit)
            guard inputStartStatus == noErr else {
                _ = AudioComponentInstanceDispose(inputUnit)
                _ = AudioComponentInstanceDispose(outputUnit)
                throw CoreAudioBridgeEngineError.audioUnitStartFailed(inputStartStatus)
            }

            let outputStartStatus = AudioOutputUnitStart(outputUnit)
            guard outputStartStatus == noErr else {
                _ = AudioOutputUnitStop(inputUnit)
                _ = AudioComponentInstanceDispose(inputUnit)
                _ = AudioComponentInstanceDispose(outputUnit)
                throw CoreAudioBridgeEngineError.audioUnitStartFailed(outputStartStatus)
            }

            sampleBufferLock.lock()
            self.inputUnit = inputUnit
            self.outputUnit = outputUnit
            self.state = .running
            self.isTransitioning = false
            sampleBufferLock.unlock()
        } catch {
            sampleBufferLock.lock()
            self.isTransitioning = false
            sampleBufferLock.unlock()
            throw error
        }
    }

    public func stop() {
        let units = detachUnits()
        guard units.input != nil || units.output != nil else { return }

        if let inputUnit = units.input {
            _ = AudioOutputUnitStop(inputUnit)
            _ = AudioComponentInstanceDispose(inputUnit)
        }
        if let outputUnit = units.output {
            _ = AudioOutputUnitStop(outputUnit)
            _ = AudioComponentInstanceDispose(outputUnit)
        }
    }

    public func statusText() -> String {
        sampleBufferLock.lock()
        defer { sampleBufferLock.unlock() }

        switch state {
        case .stopped:
            return "bridge status: stopped"
        case .running:
            return "bridge status: running"
        }
    }

    public func telemetry() -> Telemetry {
        let telemetry = processor.telemetry()
        return Telemetry(
            capturedFrames: telemetry.capturedFrames,
            renderedFrames: telemetry.renderedFrames,
            inputPeak: telemetry.inputPeak,
            outputPeak: telemetry.outputPeak,
            inputCallbackCount: telemetry.inputCallbackCount,
            outputCallbackCount: telemetry.outputCallbackCount,
            lastInputRenderStatus: telemetry.lastInputRenderStatus,
            lastOutputRenderStatus: telemetry.lastOutputRenderStatus
        )
    }

    private func detachUnits() -> (input: AudioUnit?, output: AudioUnit?) {
        sampleBufferLock.lock()
        defer { sampleBufferLock.unlock() }

        let detachedInput = inputUnit
        let detachedOutput = outputUnit
        inputUnit = nil
        outputUnit = nil
        state = .stopped
        isTransitioning = false
        return (detachedInput, detachedOutput)
    }

    private func makeStreamFormat(channelCount: UInt32) -> AudioStreamBasicDescription {
        AudioStreamBasicDescription(
            mSampleRate: settings.sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsNonInterleaved | kAudioFormatFlagsNativeEndian,
            mBytesPerPacket: UInt32(MemoryLayout<Float>.stride),
            mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(MemoryLayout<Float>.stride),
            mChannelsPerFrame: channelCount,
            mBitsPerChannel: 32,
            mReserved: 0
        )
    }

    private func createHALOutputUnit(
        deviceID: AudioDeviceID,
        enableInput: Bool,
        enableOutput: Bool,
        format: AudioStreamBasicDescription,
        maximumFramesPerSlice: UInt32
    ) throws -> AudioUnit {
        var description = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_HALOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )

        guard let component = AudioComponentFindNext(nil, &description) else {
            throw CoreAudioBridgeEngineError.audioComponentNotFound
        }

        var unit: AudioUnit?
        let creationStatus = AudioComponentInstanceNew(component, &unit)
        guard creationStatus == noErr, let unit else {
            throw CoreAudioBridgeEngineError.audioUnitCreationFailed(creationStatus)
        }

        var currentDevice = deviceID
        let currentDeviceStatus = AudioUnitSetProperty(
            unit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &currentDevice,
            UInt32(MemoryLayout<AudioObjectID>.stride)
        )
        guard currentDeviceStatus == noErr else {
            _ = AudioComponentInstanceDispose(unit)
            throw CoreAudioBridgeEngineError.audioUnitConfigurationFailed(currentDeviceStatus)
        }

        var inputEnableValue: UInt32 = enableInput ? 1 : 0
        let inputEnableStatus = AudioUnitSetProperty(
            unit,
            kAudioOutputUnitProperty_EnableIO,
            kAudioUnitScope_Input,
            1,
            &inputEnableValue,
            UInt32(MemoryLayout<UInt32>.stride)
        )
        guard inputEnableStatus == noErr else {
            _ = AudioComponentInstanceDispose(unit)
            throw CoreAudioBridgeEngineError.audioUnitConfigurationFailed(inputEnableStatus)
        }

        var outputEnableValue: UInt32 = enableOutput ? 1 : 0
        let outputEnableStatus = AudioUnitSetProperty(
            unit,
            kAudioOutputUnitProperty_EnableIO,
            kAudioUnitScope_Output,
            0,
            &outputEnableValue,
            UInt32(MemoryLayout<UInt32>.stride)
        )
        guard outputEnableStatus == noErr else {
            _ = AudioComponentInstanceDispose(unit)
            throw CoreAudioBridgeEngineError.audioUnitConfigurationFailed(outputEnableStatus)
        }

        let streamScope: AudioUnitScope = enableInput ? kAudioUnitScope_Output : kAudioUnitScope_Input
        let streamBus: AudioUnitElement = enableInput ? 1 : 0
        var negotiatedFormat = format
        let streamFormatStatus = AudioUnitSetProperty(
            unit,
            kAudioUnitProperty_StreamFormat,
            streamScope,
            streamBus,
            &negotiatedFormat,
            UInt32(MemoryLayout<AudioStreamBasicDescription>.stride)
        )
        guard streamFormatStatus == noErr else {
            _ = AudioComponentInstanceDispose(unit)
            throw CoreAudioBridgeEngineError.audioUnitConfigurationFailed(streamFormatStatus)
        }

        var maximumFrames = maximumFramesPerSlice
        let maximumFramesStatus = AudioUnitSetProperty(
            unit,
            kAudioUnitProperty_MaximumFramesPerSlice,
            kAudioUnitScope_Global,
            0,
            &maximumFrames,
            UInt32(MemoryLayout<UInt32>.stride)
        )
        guard maximumFramesStatus == noErr else {
            _ = AudioComponentInstanceDispose(unit)
            throw CoreAudioBridgeEngineError.audioUnitConfigurationFailed(maximumFramesStatus)
        }

        let initializeStatus = AudioUnitInitialize(unit)
        guard initializeStatus == noErr else {
            _ = AudioComponentInstanceDispose(unit)
            throw CoreAudioBridgeEngineError.audioUnitConfigurationFailed(initializeStatus)
        }

        return unit
    }

    private func captureInput(
        timeStamp: UnsafePointer<AudioTimeStamp>,
        busNumber: UInt32,
        frameCount: UInt32
    ) -> OSStatus {
        guard let inputUnit else { return noErr }

        var flags = AudioUnitRenderActionFlags()
        let renderStatus = AudioUnitRender(
            inputUnit,
            &flags,
            timeStamp,
            1,
            frameCount,
            inputBufferList.unsafeMutablePointer
        )
        guard renderStatus == noErr else {
            return renderStatus
        }

        let inputBlock = makeInputBlock(from: inputBufferList, frameCount: Int(frameCount))
        processor.capture(input: inputBlock)
        return noErr
    }

    private func renderOutput(
        frameCount: UInt32,
        ioData: UnsafeMutablePointer<AudioBufferList>
    ) -> OSStatus {
        let bufferList = UnsafeMutableAudioBufferListPointer(ioData)
        let outputBlock = processor.renderOutput(frameCount: Int(frameCount))
        write(outputBlock, to: bufferList, frameCount: Int(frameCount))
        return noErr
    }

    private func makeInputBlock(from bufferList: UnsafeMutableAudioBufferListPointer, frameCount: Int) -> SoundwayAudioBlock {
        let channelCount = max(1, Int(settings.inputChannelCount))
        var channels: [[Float]] = []
        channels.reserveCapacity(channelCount)

        for channel in 0..<channelCount {
            guard channel < bufferList.count, let source = bufferList[channel].mData?.assumingMemoryBound(to: Float.self) else {
                channels.append([])
                continue
            }

            channels.append(Array(UnsafeBufferPointer(start: source, count: frameCount)))
        }

        return SoundwayAudioBlock(channels: channels)
    }

    private func write(_ block: SoundwayAudioBlock, to bufferList: UnsafeMutableAudioBufferListPointer, frameCount: Int) {
        if bufferList.count > 0 {
            for channel in 0..<bufferList.count {
                guard let destination = bufferList[channel].mData?.assumingMemoryBound(to: Float.self) else {
                    continue
                }

                for frameOffset in 0..<frameCount {
                    destination[frameOffset] = 0
                }
            }

            let destinationChannels = min(bufferList.count, block.channels.count)
            for channel in 0..<destinationChannels {
                guard let destination = bufferList[channel].mData?.assumingMemoryBound(to: Float.self) else {
                    continue
                }

                let source = block.channels[channel]
                let framesToCopy = min(frameCount, source.count)
                for frameOffset in 0..<framesToCopy {
                    destination[frameOffset] = source[frameOffset]
                }
            }
        }
    }

    private static let inputDeviceCallback: AURenderCallback = { refCon, _, timeStamp, busNumber, frameCount, _ in
        let engine = Unmanaged<CoreAudioBridgeEngine>.fromOpaque(refCon).takeUnretainedValue()
        return engine.captureInput(timeStamp: timeStamp, busNumber: busNumber, frameCount: frameCount)
    }

    private static let outputDeviceCallback: AURenderCallback = { refCon, _, _, _, frameCount, ioData in
        guard let ioData else { return noErr }
        let engine = Unmanaged<CoreAudioBridgeEngine>.fromOpaque(refCon).takeUnretainedValue()
        return engine.renderOutput(frameCount: frameCount, ioData: ioData)
    }
}
