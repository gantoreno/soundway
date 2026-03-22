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
    public struct Settings: Sendable, Equatable {
        public var sampleRate: Double
        public var channelCount: UInt32
        public var maximumFramesPerSlice: UInt32

        public init(sampleRate: Double, channelCount: UInt32, maximumFramesPerSlice: UInt32) {
            self.sampleRate = sampleRate
            self.channelCount = channelCount
            self.maximumFramesPerSlice = maximumFramesPerSlice
        }
    }

    public enum State: Sendable, Equatable {
        case stopped
        case running
    }

    private let endpoints: ResolvedBridgeEndpoints
    private let settings: Settings
    private let sampleBufferCapacityFrames: Int
    private var sampleBuffer: [Float]
    private let sampleBufferLock = NSLock()
    private let inputScratch: UnsafeMutablePointer<Float>
    private let inputScratchFrames: Int
    private let inputScratchBytes: UInt32
    private let inputBufferList: UnsafeMutableAudioBufferListPointer
    private var readFrameIndex: Int = 0
    private var writeFrameIndex: Int = 0
    private var storedFrameCount: Int = 0
    private var inputUnit: AudioUnit?
    private var outputUnit: AudioUnit?
    private var state: State = .stopped
    private var isTransitioning = false

    public init(endpoints: ResolvedBridgeEndpoints, settings: Settings) {
        self.endpoints = endpoints
        self.settings = settings
        self.sampleBufferCapacityFrames = max(Int(settings.maximumFramesPerSlice) * 16, 1024)

        let totalSampleCount = sampleBufferCapacityFrames * Int(settings.channelCount)
        self.sampleBuffer = Array(repeating: 0, count: totalSampleCount)

        self.inputScratchFrames = Int(settings.maximumFramesPerSlice)
        self.inputScratch = UnsafeMutablePointer<Float>.allocate(capacity: inputScratchFrames * Int(settings.channelCount))
        self.inputScratch.initialize(repeating: 0, count: inputScratchFrames * Int(settings.channelCount))
        self.inputScratchBytes = UInt32(inputScratchFrames * Int(settings.channelCount) * MemoryLayout<Float>.stride)

        self.inputBufferList = AudioBufferList.allocate(maximumBuffers: 1)
        self.inputBufferList[0] = AudioBuffer(
            mNumberChannels: settings.channelCount,
            mDataByteSize: inputScratchBytes,
            mData: inputScratch
        )
    }

    deinit {
        stop()
        inputScratch.deallocate()
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

        let format = makeStreamFormat()
        do {
            let inputUnit = try createHALOutputUnit(
                deviceID: endpoints.input.id,
                enableInput: true,
                enableOutput: false,
                format: format,
                maximumFramesPerSlice: settings.maximumFramesPerSlice
            )
            let outputUnit = try createHALOutputUnit(
                deviceID: endpoints.output.id,
                enableInput: false,
                enableOutput: true,
                format: format,
                maximumFramesPerSlice: settings.maximumFramesPerSlice
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

    private func makeStreamFormat() -> AudioStreamBasicDescription {
        AudioStreamBasicDescription(
            mSampleRate: settings.sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | kAudioFormatFlagsNativeEndian,
            mBytesPerPacket: settings.channelCount * UInt32(MemoryLayout<Float>.stride),
            mFramesPerPacket: 1,
            mBytesPerFrame: settings.channelCount * UInt32(MemoryLayout<Float>.stride),
            mChannelsPerFrame: settings.channelCount,
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
            busNumber,
            min(frameCount, UInt32(inputScratchFrames)),
            inputBufferList.unsafeMutablePointer
        )
        guard renderStatus == noErr else {
            return renderStatus
        }

        let channels = Int(settings.channelCount)
        let framesToStore = min(Int(frameCount), inputScratchFrames)
        let samples = inputScratch
        appendCapturedFrames(samples, frameCount: framesToStore, channels: channels)
        return noErr
    }

    private func renderOutput(
        frameCount: UInt32,
        ioData: UnsafeMutablePointer<AudioBufferList>
    ) -> OSStatus {
        let bufferList = UnsafeMutableAudioBufferListPointer(ioData)
        let channels = Int(settings.channelCount)
        let framesToFill = Int(frameCount)
        drainInto(bufferList, frameCount: framesToFill, channels: channels)
        return noErr
    }

    private func appendCapturedFrames(
        _ source: UnsafeMutablePointer<Float>,
        frameCount: Int,
        channels: Int
    ) {
        sampleBufferLock.lock()
        defer { sampleBufferLock.unlock() }

        guard frameCount > 0 else { return }

        let frameCount = min(frameCount, sampleBufferCapacityFrames)
        let sourceSampleStart = 0

        if frameCount >= sampleBufferCapacityFrames {
            readFrameIndex = 0
            writeFrameIndex = 0
            storedFrameCount = 0
        }

        while storedFrameCount + frameCount > sampleBufferCapacityFrames {
            readFrameIndex = (readFrameIndex + 1) % sampleBufferCapacityFrames
            storedFrameCount -= 1
        }

        for frameOffset in 0..<frameCount {
            let destinationFrameIndex = (writeFrameIndex + frameOffset) % sampleBufferCapacityFrames
            let destinationSampleBase = destinationFrameIndex * channels
            let sourceSampleBase = sourceSampleStart + (frameOffset * channels)
            for channel in 0..<channels {
                sampleBuffer[destinationSampleBase + channel] = source.advanced(by: sourceSampleBase + channel).pointee
            }
        }

        writeFrameIndex = (writeFrameIndex + frameCount) % sampleBufferCapacityFrames
        storedFrameCount += frameCount
    }

    private func drainInto(
        _ bufferList: UnsafeMutableAudioBufferListPointer,
        frameCount: Int,
        channels: Int
    ) {
        sampleBufferLock.lock()
        defer { sampleBufferLock.unlock() }

        guard frameCount > 0 else { return }

        let framesToCopy = min(frameCount, storedFrameCount)
        let silenceFrames = frameCount - framesToCopy

        if bufferList.count > 0 {
            guard let destination = bufferList[0].mData?.assumingMemoryBound(to: Float.self) else {
                return
            }

            for frameOffset in 0..<framesToCopy {
                let sourceFrameIndex = (readFrameIndex + frameOffset) % sampleBufferCapacityFrames
                let sourceSampleBase = sourceFrameIndex * channels
                let destinationSampleBase = frameOffset * channels
                for channel in 0..<channels {
                    destination[destinationSampleBase + channel] = sampleBuffer[sourceSampleBase + channel]
                }
            }

            if framesToCopy < frameCount {
                let silenceStartSample = framesToCopy * channels
                let silenceSampleCount = silenceFrames * channels
                destination.advanced(by: silenceStartSample).initialize(repeating: 0, count: silenceSampleCount)
            }
        }

        readFrameIndex = (readFrameIndex + framesToCopy) % sampleBufferCapacityFrames
        storedFrameCount -= framesToCopy
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
