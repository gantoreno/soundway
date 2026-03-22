import CoreAudio
import Foundation
import os

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
  private var unfairLock = os_unfair_lock_s()
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
    acquireLock()
    defer { releaseLock() }
    captureLocked(
      frameCount: min(input.frameCount, sampleBufferCapacityFrames),
      sampleAt: { channel, frameOffset in
        guard channel < input.channels.count,
          frameOffset < input.channels[channel].count
        else {
          return 0
        }
        return input.channels[channel][frameOffset]
      }
    )
    lastInputRenderStatus = noErr
  }

  func capture(input bufferList: UnsafeMutableAudioBufferListPointer, frameCount: Int) -> OSStatus {
    guard frameCount > 0 else {
      acquireLock()
      lastInputRenderStatus = noErr
      releaseLock()
      return noErr
    }

    guard tryAcquireLock() else { return noErr }
    defer { releaseLock() }

    captureLocked(
      frameCount: min(frameCount, sampleBufferCapacityFrames),
      sampleAt: { channel, frameOffset in
        guard channel < bufferList.count,
          let source = bufferList[channel].mData?.assumingMemoryBound(to: Float.self)
        else {
          return 0
        }
        return source[frameOffset]
      }
    )
    lastInputRenderStatus = noErr
    return noErr
  }

  func renderOutput(frameCount: Int) -> SoundwayAudioBlock {
    acquireLock()
    defer { releaseLock() }

    outputCallbackCount += 1

    guard frameCount > 0 else {
      lastOutputRenderStatus = noErr
      return .silence(channelCount: outputChannelCount, frameCount: 0)
    }

    var output = SoundwayAudioBlock.silence(
      channelCount: outputChannelCount, frameCount: frameCount)
    renderLocked(into: &output.channels, frameCount: frameCount)
    lastOutputRenderStatus = noErr
    return output
  }

  func renderOutput(
    frameCount: Int, to bufferList: UnsafeMutableAudioBufferListPointer
  ) -> OSStatus {
    guard frameCount > 0 else {
      zero(bufferList: bufferList, frameCount: 0)
      acquireLock()
      outputCallbackCount += 1
      lastOutputRenderStatus = noErr
      releaseLock()
      return noErr
    }

    guard tryAcquireLock() else {
      zero(bufferList: bufferList, frameCount: frameCount)
      return noErr
    }
    defer { releaseLock() }

    outputCallbackCount += 1
    renderLocked(into: bufferList, frameCount: frameCount)
    lastOutputRenderStatus = noErr
    return noErr
  }

  func telemetry() -> Telemetry {
    acquireLock()
    defer { releaseLock() }

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
    acquireLock()
    defer { releaseLock() }

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

  private func captureLocked(
    frameCount: Int,
    sampleAt: (Int, Int) -> Float
  ) {
    inputCallbackCount += 1

    // Keep a bounded ring buffer so capture and render can advance independently.
    guard frameCount > 0 else { return }

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
        let sample = sampleAt(channel, frameOffset)
        sampleBuffer[destinationSampleBase + channel] = sample
        localPeak = max(localPeak, abs(sample))
      }
    }

    writeFrameIndex = (writeFrameIndex + frameCount) % sampleBufferCapacityFrames
    storedFrameCount += frameCount
    capturedFrames += UInt64(frameCount)
    inputPeak = localPeak
  }

  private func renderLocked(into channels: inout [[Float]], frameCount: Int) {
    let framesToCopy = min(frameCount, storedFrameCount)
    var localPeak: Float = 0

    for channel in 0..<outputChannelCount {
      guard channel < channels.count else { continue }
      let sourceChannelIndex = outputSourceChannelIndex(for: channel)

      for frameOffset in 0..<framesToCopy {
        let sample = sampleForOutput(
          sourceChannelIndex: sourceChannelIndex, frameOffset: frameOffset)
        channels[channel][frameOffset] = sample
        localPeak = max(localPeak, abs(sample))
      }
    }

    readFrameIndex = (readFrameIndex + framesToCopy) % sampleBufferCapacityFrames
    storedFrameCount -= framesToCopy
    renderedFrames += UInt64(framesToCopy)
    outputPeak = localPeak
  }

  private func renderLocked(into bufferList: UnsafeMutableAudioBufferListPointer, frameCount: Int) {
    zero(bufferList: bufferList, frameCount: frameCount)

    let framesToCopy = min(frameCount, storedFrameCount)
    var localPeak: Float = 0

    for channel in 0..<min(outputChannelCount, bufferList.count) {
      let sourceChannelIndex = outputSourceChannelIndex(for: channel)
      guard let destination = bufferList[channel].mData?.assumingMemoryBound(to: Float.self)
      else {
        continue
      }

      for frameOffset in 0..<framesToCopy {
        let sample = sampleForOutput(
          sourceChannelIndex: sourceChannelIndex, frameOffset: frameOffset)
        destination[frameOffset] = sample
        localPeak = max(localPeak, abs(sample))
      }
    }

    readFrameIndex = (readFrameIndex + framesToCopy) % sampleBufferCapacityFrames
    storedFrameCount -= framesToCopy
    renderedFrames += UInt64(framesToCopy)
    outputPeak = localPeak
  }

  private func sampleForOutput(
    sourceChannelIndex: Int?, frameOffset: Int
  ) -> Float {
    guard let sourceChannelIndex, sourceChannelIndex < bridgeChannelCount else {
      return 0
    }
    let sourceFrameIndex = (readFrameIndex + frameOffset) % sampleBufferCapacityFrames
    let sourceSampleBase = sourceFrameIndex * bridgeChannelCount
    return sampleBuffer[sourceSampleBase + sourceChannelIndex]
  }

  private func zero(bufferList: UnsafeMutableAudioBufferListPointer, frameCount: Int) {
    guard frameCount > 0 else { return }
    for channel in 0..<bufferList.count {
      guard let destination = bufferList[channel].mData?.assumingMemoryBound(to: Float.self)
      else {
        continue
      }
      for frameOffset in 0..<frameCount {
        destination[frameOffset] = 0
      }
    }
  }

  private func acquireLock() {
    os_unfair_lock_lock(&unfairLock)
  }

  private func tryAcquireLock() -> Bool {
    os_unfair_lock_trylock(&unfairLock)
  }

  private func releaseLock() {
    os_unfair_lock_unlock(&unfairLock)
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
