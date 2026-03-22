import CoreAudio
import Foundation

internal struct SoundwayAudioBlock: Sendable, Equatable {
  var channels: [[Float]]

  var frameCount: Int {
    channels.first?.count ?? 0
  }

  init(channels: [[Float]]) {
    self.channels = channels
  }

  static func silence(channelCount: Int, frameCount: Int) -> Self {
    Self(channels: Array(repeating: Array(repeating: 0, count: frameCount), count: channelCount))
  }
}

internal final class SoundwayBridgeProcessor {
  struct Settings: Sendable, Equatable {
    var sampleRate: Double
    var inputChannelCount: UInt32
    var outputChannelCount: UInt32
    var maximumFramesPerSlice: UInt32
    var outputChannelMap: [Int]
  }

  struct Telemetry: Sendable, Equatable {
    let capturedFrames: UInt64
    let renderedFrames: UInt64
    let inputPeak: Float
    let outputPeak: Float
    let inputCallbackCount: UInt64
    let outputCallbackCount: UInt64
    let lastInputRenderStatus: OSStatus
    let lastOutputRenderStatus: OSStatus
  }

  private let settings: Settings
  private let sampleBufferCapacityFrames: Int
  private let bridgeChannelCount: Int
  private let outputChannelCount: Int
  private var sampleBuffer: [Float]
  private let lock = NSLock()
  private var readFrameIndex: Int = 0
  private var writeFrameIndex: Int = 0
  private var storedFrameCount: Int = 0
  private var capturedFrames: UInt64 = 0
  private var renderedFrames: UInt64 = 0
  private var inputPeak: Float = 0
  private var outputPeak: Float = 0
  private var inputCallbackCount: UInt64 = 0
  private var outputCallbackCount: UInt64 = 0
  private var lastInputRenderStatus: OSStatus = noErr
  private var lastOutputRenderStatus: OSStatus = noErr

  init(settings: Settings) {
    self.settings = settings
    self.sampleBufferCapacityFrames = max(Int(settings.maximumFramesPerSlice) * 16, 1024)
    self.bridgeChannelCount = max(
      1, max(Int(settings.inputChannelCount), Int(settings.outputChannelCount)))
    self.outputChannelCount = max(1, Int(settings.outputChannelCount))
    self.sampleBuffer = Array(repeating: 0, count: sampleBufferCapacityFrames * bridgeChannelCount)
  }

  func capture(input: SoundwayAudioBlock) {
    lock.lock()
    defer { lock.unlock() }

    inputCallbackCount += 1

    // Keep a bounded ring buffer so capture and render can advance independently.
    let frameCount = min(input.frameCount, sampleBufferCapacityFrames)
    guard frameCount > 0 else { return }

    let availableChannels = min(input.channels.count, bridgeChannelCount)
    var localPeak: Float = 0

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
      let destinationSampleBase = destinationFrameIndex * bridgeChannelCount

      for channel in 0..<bridgeChannelCount {
        let sample: Float
        if channel < availableChannels, frameOffset < input.channels[channel].count {
          sample = input.channels[channel][frameOffset]
        } else {
          sample = 0
        }

        sampleBuffer[destinationSampleBase + channel] = sample
        localPeak = max(localPeak, abs(sample))
      }
    }

    writeFrameIndex = (writeFrameIndex + frameCount) % sampleBufferCapacityFrames
    storedFrameCount += frameCount
    capturedFrames += UInt64(frameCount)
    inputPeak = localPeak
    lastInputRenderStatus = noErr
  }

  func renderOutput(frameCount: Int) -> SoundwayAudioBlock {
    lock.lock()
    defer { lock.unlock() }

    outputCallbackCount += 1

    guard frameCount > 0 else {
      lastOutputRenderStatus = noErr
      return .silence(channelCount: outputChannelCount, frameCount: 0)
    }

    var output = SoundwayAudioBlock.silence(
      channelCount: outputChannelCount, frameCount: frameCount)
    let framesToCopy = min(frameCount, storedFrameCount)
    var localPeak: Float = 0

    for channel in 0..<outputChannelCount {
      let sourceChannelIndex = outputSourceChannelIndex(for: channel)

      for frameOffset in 0..<framesToCopy {
        let sourceFrameIndex = (readFrameIndex + frameOffset) % sampleBufferCapacityFrames
        let sourceSampleBase = sourceFrameIndex * bridgeChannelCount
        let sample =
          sourceChannelIndex.flatMap { sourceChannel -> Float? in
            guard sourceChannel < bridgeChannelCount else { return nil }
            return sampleBuffer[sourceSampleBase + sourceChannel]
          } ?? 0
        output.channels[channel][frameOffset] = sample
        localPeak = max(localPeak, abs(sample))
      }
    }

    readFrameIndex = (readFrameIndex + framesToCopy) % sampleBufferCapacityFrames
    storedFrameCount -= framesToCopy
    renderedFrames += UInt64(framesToCopy)
    outputPeak = localPeak
    lastOutputRenderStatus = noErr
    return output
  }

  func telemetry() -> Telemetry {
    lock.lock()
    defer { lock.unlock() }

    return Telemetry(
      capturedFrames: capturedFrames,
      renderedFrames: renderedFrames,
      inputPeak: inputPeak,
      outputPeak: outputPeak,
      inputCallbackCount: inputCallbackCount,
      outputCallbackCount: outputCallbackCount,
      lastInputRenderStatus: lastInputRenderStatus,
      lastOutputRenderStatus: lastOutputRenderStatus
    )
  }

  func reset() {
    lock.lock()
    defer { lock.unlock() }

    // Clear the entire buffer so a restarted bridge begins from silence.
    readFrameIndex = 0
    writeFrameIndex = 0
    storedFrameCount = 0
    capturedFrames = 0
    renderedFrames = 0
    inputPeak = 0
    outputPeak = 0
    inputCallbackCount = 0
    outputCallbackCount = 0
    lastInputRenderStatus = noErr
    lastOutputRenderStatus = noErr
    sampleBuffer = Array(repeating: 0, count: sampleBufferCapacityFrames * bridgeChannelCount)
  }

  private func outputSourceChannelIndex(for outputChannel: Int) -> Int? {
    guard outputChannel >= 0 else { return nil }
    if outputChannel < settings.outputChannelMap.count {
      let mappedChannel = settings.outputChannelMap[outputChannel]
      return mappedChannel > 0 ? mappedChannel - 1 : nil
    }
    return outputChannel
  }
}
