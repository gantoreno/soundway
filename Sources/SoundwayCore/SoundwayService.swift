import Foundation
import Darwin
import CoreAudio

public enum SoundwayServiceError: Error, Sendable, Equatable {
    case socketCreationFailed(Int32)
    case socketBindFailed(Int32)
    case socketListenFailed(Int32)
    case socketConnectFailed(Int32)
    case socketCommunicationFailed(String)
    case daemonLaunchFailed(String)
    case responseDecodingFailed
}

public enum SoundwayServiceAction: String, Codable, Sendable {
    case status
    case stop
}

public struct SoundwayServiceRequest: Codable, Sendable {
    public let action: SoundwayServiceAction

    public init(action: SoundwayServiceAction) {
        self.action = action
    }
}

public struct SoundwayServiceStatus: Codable, Sendable, Equatable {
    public let state: String
    public let version: String
    public let inputDevice: String
    public let outputDevice: String
    public let inputChannels: UInt32
    public let outputChannels: UInt32
    public let outputChannelMap: [Int]
    public let sampleRate: Double
    public let bufferFrames: UInt32
    public let capturedFrames: UInt64
    public let renderedFrames: UInt64
    public let inputPeak: Float
    public let outputPeak: Float
    public let inputCallbackCount: UInt64
    public let outputCallbackCount: UInt64
    public let lastInputRenderStatus: Int32
    public let lastOutputRenderStatus: Int32
}

public struct SoundwayServiceResponse: Codable, Sendable, Equatable {
    public let ok: Bool
    public let message: String?
    public let status: SoundwayServiceStatus?

    public static func success(status: SoundwayServiceStatus? = nil, message: String? = nil) -> Self {
        Self(ok: true, message: message, status: status)
    }

    public static func failure(_ message: String) -> Self {
        Self(ok: false, message: message, status: nil)
    }
}

public struct SoundwayServiceEndpoint: Sendable, Equatable {
    public let socketURL: URL

    public init(socketURL: URL) {
        self.socketURL = socketURL
    }
}

/// Shared daemon control helpers used by the CLI and the background process.
public enum SoundwayServiceControl {
    public static var endpoint: SoundwayServiceEndpoint {
        let uid = getuid()
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("soundway-\(uid).sock")
        return SoundwayServiceEndpoint(socketURL: path)
    }

    public static func resolveExecutableURL(commandName: String, environment: [String: String] = ProcessInfo.processInfo.environment) -> URL? {
        let fileManager = FileManager.default

        if commandName.contains("/") {
            return fileManager.isExecutableFile(atPath: commandName) ? URL(fileURLWithPath: commandName) : nil
        }

        guard let pathValue = environment["PATH"], !pathValue.isEmpty else {
            return nil
        }

        for component in pathValue.split(separator: ":") {
            let directory = String(component)
            let candidatePath = (directory as NSString).appendingPathComponent(commandName)
            if fileManager.isExecutableFile(atPath: candidatePath) {
                return URL(fileURLWithPath: candidatePath)
            }
        }

        return nil
    }

    public static func startBackgroundDaemon(executableURL: URL) throws {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = ["serve"]
        process.standardInput = FileHandle(forReadingAtPath: "/dev/null")
        process.standardOutput = FileHandle(forWritingAtPath: "/dev/null")
        process.standardError = FileHandle(forWritingAtPath: "/dev/null")

        do {
            try process.run()
        } catch {
            throw SoundwayServiceError.daemonLaunchFailed(error.localizedDescription)
        }

        try waitForDaemonReady(timeoutSeconds: 2.0)
    }

    public static func stopDaemon() throws -> SoundwayServiceResponse {
        let response = try send(action: .stop)
        return response
    }

    public static func readStatus() throws -> SoundwayServiceResponse {
        try send(action: .status)
    }

    fileprivate static func waitForDaemonReady(timeoutSeconds: TimeInterval) throws {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if FileManager.default.fileExists(atPath: endpoint.socketURL.path) {
                if (try? readStatus()) != nil {
                    return
                }
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        throw SoundwayServiceError.daemonLaunchFailed("daemon did not become ready in time")
    }

    fileprivate static func send(action: SoundwayServiceAction) throws -> SoundwayServiceResponse {
        let request = SoundwayServiceRequest(action: action)
        let encoder = JSONEncoder()
        let requestData = try encoder.encode(request)
        var payload = requestData
        payload.append(0x0A)

        let socketFD = socket(AF_UNIX, Int32(SOCK_STREAM), 0)
        guard socketFD >= 0 else {
            throw SoundwayServiceError.socketCreationFailed(errno)
        }
        defer { close(socketFD) }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)

        let socketPath = endpoint.socketURL.path
        socketPath.withCString { pathPointer in
            withUnsafeMutableBytes(of: &address.sun_path) { bytes in
                bytes.initializeMemory(as: CChar.self, repeating: 0)
                strncpy(bytes.baseAddress!.assumingMemoryBound(to: CChar.self), pathPointer, bytes.count - 1)
            }
        }

        let connectResult = withUnsafePointer(to: &address) { pointer -> Int32 in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                connect(
                    socketFD,
                    sockaddrPointer,
                    socklen_t(MemoryLayout<sockaddr_un>.stride)
                )
            }
        }
        guard connectResult == 0 else {
            throw SoundwayServiceError.socketConnectFailed(errno)
        }

        try writeAll(fd: socketFD, bytes: payload)
        let responseData = try readLine(fd: socketFD)

        guard let response = try? JSONDecoder().decode(SoundwayServiceResponse.self, from: responseData) else {
            throw SoundwayServiceError.responseDecodingFailed
        }
        return response
    }

    fileprivate static func writeAll(fd: Int32, bytes: Data) throws {
        try bytes.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            var bytesRemaining = rawBuffer.count
            var currentPointer = baseAddress.bindMemory(to: UInt8.self, capacity: rawBuffer.count)

            while bytesRemaining > 0 {
                let written = write(fd, currentPointer, bytesRemaining)
                if written < 0 {
                    throw SoundwayServiceError.socketCommunicationFailed(String(cString: strerror(errno)))
                }
                bytesRemaining -= written
                currentPointer = currentPointer.advanced(by: written)
            }
        }
    }

    fileprivate static func readLine(fd: Int32) throws -> Data {
        var buffer = Data()
        var byte: UInt8 = 0

        while true {
            let bytesRead = read(fd, &byte, 1)
            if bytesRead < 0 {
                throw SoundwayServiceError.socketCommunicationFailed(String(cString: strerror(errno)))
            }
            if bytesRead == 0 {
                break
            }
            if byte == 0x0A {
                break
            }
            buffer.append(byte)
        }

        return buffer
    }
}

/// Default service controller used by the command-line entry point.
public struct SoundwayServiceController: SoundwayServiceControlling {
    public init() {}

    public func readStatus() throws -> SoundwayServiceResponse {
        try SoundwayServiceControl.readStatus()
    }

    public func stopDaemon() throws -> SoundwayServiceResponse {
        try SoundwayServiceControl.stopDaemon()
    }

    public func startBackgroundDaemon(executableURL: URL) throws {
        try SoundwayServiceControl.startBackgroundDaemon(executableURL: executableURL)
    }

    public func resolveExecutableURL(commandName: String, environment: [String : String]) -> URL? {
        SoundwayServiceControl.resolveExecutableURL(commandName: commandName, environment: environment)
    }
}

internal struct SoundwayDaemonRequestResult {
    let response: SoundwayServiceResponse
    let shouldStop: Bool
}

internal struct SoundwayDaemonRequestHandler {
    let statusProvider: () -> SoundwayServiceStatus

    func handle(_ request: SoundwayServiceRequest) -> SoundwayDaemonRequestResult {
        switch request.action {
        case .status:
            return SoundwayDaemonRequestResult(response: .success(status: statusProvider()), shouldStop: false)
        case .stop:
            return SoundwayDaemonRequestResult(response: .success(message: "stopping"), shouldStop: true)
        }
    }
}

/// Runs the bridge and serves IPC requests for the CLI.
public final class SoundwayDaemon {
    private let config: BridgeConfiguration
    private let engine: CoreAudioBridgeEngine
    private let endpoint = SoundwayServiceControl.endpoint
    private let inputChannelCount: UInt32
    private let outputChannelCount: UInt32
    private var listenerFD: Int32 = -1

    public convenience init(configuration: BridgeConfiguration? = nil) throws {
        try self.init(configuration: configuration, configurationStore: SoundwayConfigurationStore(), deviceDiscovery: AudioDeviceDiscovery())
    }

    internal init<ConfigurationStore: SoundwayConfigurationLoading, DeviceDiscovery: SoundwayDeviceDiscovering>(
        configuration: BridgeConfiguration? = nil,
        configurationStore: ConfigurationStore,
        deviceDiscovery: DeviceDiscovery
    ) throws {
        let resolvedConfiguration = try configuration ?? configurationStore.load() ?? .default
        self.config = resolvedConfiguration
        let endpoints = try deviceDiscovery.resolveEndpoints(for: resolvedConfiguration)
        self.inputChannelCount = try deviceDiscovery.channelCount(for: endpoints.input.id, scope: kAudioObjectPropertyScopeInput)
        self.outputChannelCount = try deviceDiscovery.channelCount(for: endpoints.output.id, scope: kAudioObjectPropertyScopeOutput)
        self.engine = CoreAudioBridgeEngine(
            endpoints: endpoints,
            settings: .init(
                sampleRate: resolvedConfiguration.sampleRate,
                inputChannelCount: inputChannelCount,
                outputChannelCount: outputChannelCount,
                maximumFramesPerSlice: resolvedConfiguration.bufferFrameSize,
                outputChannelMap: resolvedConfiguration.outputChannelMap
            )
        )
    }

    deinit {
        if listenerFD >= 0 {
            close(listenerFD)
        }
    }

    public func run() throws {
        try prepareSocket()
        try engine.start()
        defer {
            engine.stop()
            unlink(endpoint.socketURL.path)
        }

        let requestHandler = SoundwayDaemonRequestHandler(statusProvider: { [engine, config, inputChannelCount, outputChannelCount] in
            let telemetry = engine.telemetry()
            return SoundwayServiceStatus(
                state: engine.currentState == .running ? "running" : "stopped",
                version: SoundwayVersion.current,
                inputDevice: config.inputDeviceName,
                outputDevice: config.outputDeviceName,
                inputChannels: inputChannelCount,
                outputChannels: outputChannelCount,
                outputChannelMap: config.outputChannelMap,
                sampleRate: config.sampleRate,
                bufferFrames: config.bufferFrameSize,
                capturedFrames: telemetry.capturedFrames,
                renderedFrames: telemetry.renderedFrames,
                inputPeak: telemetry.inputPeak,
                outputPeak: telemetry.outputPeak,
                inputCallbackCount: telemetry.inputCallbackCount,
                outputCallbackCount: telemetry.outputCallbackCount,
                lastInputRenderStatus: telemetry.lastInputRenderStatus,
                lastOutputRenderStatus: telemetry.lastOutputRenderStatus
            )
        })

        while true {
            let clientFD = accept(listenerFD, nil, nil)
            if clientFD < 0 {
                if errno == EINTR { continue }
                throw SoundwayServiceError.socketCommunicationFailed(String(cString: strerror(errno)))
            }

            defer { close(clientFD) }

            let requestData = try Self.readLine(fd: clientFD)
            guard let request = try? JSONDecoder().decode(SoundwayServiceRequest.self, from: requestData) else {
                let response = SoundwayServiceResponse.failure("invalid request")
                try Self.writeResponse(response, fd: clientFD)
                continue
            }

            let result = requestHandler.handle(request)
            try Self.writeResponse(result.response, fd: clientFD)
            if result.shouldStop {
                return
            }
        }
    }

    private func prepareSocket() throws {
        let socketPath = endpoint.socketURL.path
        unlink(socketPath)

        let fd = socket(AF_UNIX, Int32(SOCK_STREAM), 0)
        guard fd >= 0 else {
            throw SoundwayServiceError.socketCreationFailed(errno)
        }
        listenerFD = fd

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        socketPath.withCString { pathPointer in
            withUnsafeMutableBytes(of: &address.sun_path) { bytes in
                bytes.initializeMemory(as: CChar.self, repeating: 0)
                strncpy(bytes.baseAddress!.assumingMemoryBound(to: CChar.self), pathPointer, bytes.count - 1)
            }
        }

        let bindResult = withUnsafePointer(to: &address) { pointer -> Int32 in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                bind(listenerFD, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_un>.stride))
            }
        }
        guard bindResult == 0 else {
            throw SoundwayServiceError.socketBindFailed(errno)
        }

        guard listen(listenerFD, 5) == 0 else {
            throw SoundwayServiceError.socketListenFailed(errno)
        }
    }

    private static func writeResponse(_ response: SoundwayServiceResponse, fd: Int32) throws {
        let encoder = JSONEncoder()
        let responseData = try encoder.encode(response)
        var payload = responseData
        payload.append(0x0A)
        try SoundwayServiceControl.writeAll(fd: fd, bytes: payload)
    }

    private static func readLine(fd: Int32) throws -> Data {
        try SoundwayServiceControl.readLine(fd: fd)
    }
}
