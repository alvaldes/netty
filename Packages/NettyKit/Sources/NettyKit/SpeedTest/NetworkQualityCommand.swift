import Foundation

/// Runs Apple's built-in `networkQuality` tool: no third-party servers or dependencies.
nonisolated enum NetworkQualityCommand {
    struct Failed: Error {
        var status: Int32
        var message: String
    }

    static let url = URL(fileURLWithPath: "/usr/bin/networkQuality")
    /// Caps the test's duration, and so the data it uses.
    static let maxRuntime = 20

    static func run() async throws -> Data {
        let process = Process()
        process.executableURL = url
        process.arguments = ["-c", "-M", String(maxRuntime)]
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                // Reading blocks until the process closes the pipe, so keep it off the cooperative pool.
                DispatchQueue.global(qos: .utility).async {
                    do {
                        try process.run()
                        let data = output.fileHandleForReading.readDataToEndOfFile()
                        let message = errors.fileHandleForReading.readDataToEndOfFile()
                        process.waitUntilExit()
                        if process.terminationStatus == 0 {
                            continuation.resume(returning: data)
                        } else {
                            continuation.resume(throwing: Failed(status: process.terminationStatus,
                                                                 message: String(decoding: message, as: UTF8.self)))
                        }
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            process.terminate()
        }
    }
}
