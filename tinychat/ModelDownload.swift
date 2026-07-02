//
//  ModelDownload.swift
//  tinychat
//
//  Created by Matthew Barnson on 7/2/26.
//

import CryptoKit
import Foundation

struct ModelReleaseManifest: Codable, Equatable, Sendable {
    let artifacts: [ModelReleaseArtifact]

    func artifact(for platform: String = ModelCache.platformDirectoryName) throws -> ModelReleaseArtifact {
        guard let artifact = artifacts.first(where: { $0.platform == platform }) else {
            throw ModelReleaseManifestError.noArtifact(platform: platform)
        }
        return artifact
    }
}

struct ModelReleaseArtifact: Codable, Equatable, Sendable {
    let modelID: String
    let displayName: String
    let version: String
    let platform: String
    let archiveURL: URL
    let archiveSHA256: String
    let byteSize: Int64
    let expandedDirectoryName: String
    let expectedFiles: [String]

    init(
        modelID: String = ModelCache.baseModelID,
        displayName: String = ModelCache.baseDisplayName,
        version: String,
        platform: String = ModelCache.platformDirectoryName,
        archiveURL: URL,
        archiveSHA256: String,
        byteSize: Int64,
        expandedDirectoryName: String,
        expectedFiles: [String]
    ) {
        self.modelID = modelID
        self.displayName = displayName
        self.version = version
        self.platform = platform
        self.archiveURL = archiveURL
        self.archiveSHA256 = archiveSHA256
        self.byteSize = byteSize
        self.expandedDirectoryName = expandedDirectoryName
        self.expectedFiles = expectedFiles
    }
}

enum ModelReleaseManifestError: LocalizedError, Equatable {
    case noArtifact(platform: String)

    var errorDescription: String? {
        switch self {
        case .noArtifact(let platform):
            "No model artifact is available for platform \(platform)."
        }
    }
}

struct ModelDownloadProgress: Equatable, Sendable {
    enum Phase: String, Equatable, Sendable {
        case preparing
        case downloading
        case verifying
        case extracting
        case installing
    }

    let phase: Phase
    let completedBytes: Int64
    let totalBytes: Int64?
}

enum ModelDownloadError: LocalizedError, Equatable {
    case unsupportedArchiveURL(URL)
    case downloadFailed(statusCode: Int)
    case archiveSizeMismatch(expected: Int64, actual: Int64)
    case insufficientDiskSpace(required: Int64, available: Int64)
    case sha256Mismatch(expected: String, actual: String)
    case invalidZipArchive
    case unsafeZipEntry(String)
    case unsupportedZipCompression(method: UInt16)
    case missingExpandedDirectory(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedArchiveURL(let url):
            "Unsupported model archive URL: \(url.absoluteString)"
        case .downloadFailed(let statusCode):
            "Model archive download failed with HTTP \(statusCode)."
        case .archiveSizeMismatch(let expected, let actual):
            "Model archive size mismatch: expected \(expected) bytes, got \(actual) bytes."
        case .insufficientDiskSpace(let required, let available):
            "Not enough disk space for model install: requires \(required) bytes, available \(available) bytes."
        case .sha256Mismatch(let expected, let actual):
            "Model archive checksum mismatch: expected \(expected), got \(actual)."
        case .invalidZipArchive:
            "Model archive is not a supported ZIP file."
        case .unsafeZipEntry(let entry):
            "Model archive contains an unsafe path: \(entry)"
        case .unsupportedZipCompression(let method):
            "Model archive uses unsupported ZIP compression method \(method)."
        case .missingExpandedDirectory(let directory):
            "Model archive did not contain expected directory: \(directory)"
        }
    }
}

struct ModelDownloadManager {
    private let cache: ModelCache
    private let fileManager: FileManager

    init(cache: ModelCache = ModelCache(), fileManager: FileManager = .default) {
        self.cache = cache
        self.fileManager = fileManager
    }

    func installBaseModel(
        from releaseManifest: ModelReleaseManifest,
        progress: @Sendable (ModelDownloadProgress) -> Void = { _ in }
    ) async throws -> ModelCacheStatus {
        let artifact = try releaseManifest.artifact()
        return try await installBaseModel(from: artifact, progress: progress)
    }

    func installBaseModel(
        from artifact: ModelReleaseArtifact,
        progress: @Sendable (ModelDownloadProgress) -> Void = { _ in }
    ) async throws -> ModelCacheStatus {
        progress(.init(phase: .preparing, completedBytes: 0, totalBytes: artifact.byteSize > 0 ? artifact.byteSize : nil))
        try Task.checkCancellation()
        try ensureAvailableDiskSpace(for: artifact)

        let workDirectory = cache.appSupportDirectory
            .appending(path: ".downloads", directoryHint: .isDirectory)
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let archiveURL = workDirectory.appending(path: "model.zip", directoryHint: .notDirectory)
        let extractionDirectory = workDirectory.appending(path: "expanded", directoryHint: .isDirectory)

        try fileManager.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: workDirectory) }

        progress(.init(phase: .downloading, completedBytes: 0, totalBytes: artifact.byteSize > 0 ? artifact.byteSize : nil))
        try await copyArchive(from: artifact.archiveURL, to: archiveURL, expectedByteSize: artifact.byteSize, progress: progress)
        try Task.checkCancellation()

        let archiveSize = try fileManager.attributesOfItem(atPath: archiveURL.path(percentEncoded: false))[.size] as? NSNumber
        let actualSize = archiveSize?.int64Value ?? 0
        if artifact.byteSize > 0, actualSize != artifact.byteSize {
            throw ModelDownloadError.archiveSizeMismatch(expected: artifact.byteSize, actual: actualSize)
        }
        progress(.init(phase: .downloading, completedBytes: actualSize, totalBytes: artifact.byteSize > 0 ? artifact.byteSize : actualSize))

        progress(.init(phase: .verifying, completedBytes: actualSize, totalBytes: actualSize))
        let actualSHA256 = try Self.sha256Hex(for: archiveURL)
        guard actualSHA256.caseInsensitiveCompare(artifact.archiveSHA256) == .orderedSame else {
            throw ModelDownloadError.sha256Mismatch(expected: artifact.archiveSHA256, actual: actualSHA256)
        }
        try Task.checkCancellation()

        progress(.init(phase: .extracting, completedBytes: 0, totalBytes: actualSize))
        try StoredZipExtractor(fileManager: fileManager).extract(archive: archiveURL, to: extractionDirectory)

        let expandedDirectory = extractionDirectory.appending(path: artifact.expandedDirectoryName, directoryHint: .isDirectory)
        guard fileManager.fileExists(atPath: expandedDirectory.path(percentEncoded: false)) else {
            throw ModelDownloadError.missingExpandedDirectory(artifact.expandedDirectoryName)
        }

        progress(.init(phase: .installing, completedBytes: actualSize, totalBytes: actualSize))
        let installManifest = ModelArtifactManifest(
            modelID: artifact.modelID,
            displayName: artifact.displayName,
            platform: artifact.platform,
            version: artifact.version,
            sourceURL: expandedDirectory,
            expectedFiles: artifact.expectedFiles
        )
        try cache.installBaseModel(from: installManifest)
        return cache.baseModelStatus()
    }

    private func copyArchive(
        from sourceURL: URL,
        to destinationURL: URL,
        expectedByteSize: Int64,
        progress: @Sendable (ModelDownloadProgress) -> Void
    ) async throws {
        if sourceURL.isFileURL {
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
            let size = try fileManager.attributesOfItem(atPath: destinationURL.path(percentEncoded: false))[.size] as? NSNumber
            progress(.init(
                phase: .downloading,
                completedBytes: size?.int64Value ?? 0,
                totalBytes: expectedByteSize > 0 ? expectedByteSize : size?.int64Value
            ))
            return
        }

        guard sourceURL.scheme == "https" || sourceURL.scheme == "http" else {
            throw ModelDownloadError.unsupportedArchiveURL(sourceURL)
        }

        let (downloadedURL, response) = try await URLSession.shared.download(from: sourceURL)
        if let httpResponse = response as? HTTPURLResponse, !(200..<300).contains(httpResponse.statusCode) {
            throw ModelDownloadError.downloadFailed(statusCode: httpResponse.statusCode)
        }
        try fileManager.moveItem(at: downloadedURL, to: destinationURL)
        let size = try fileManager.attributesOfItem(atPath: destinationURL.path(percentEncoded: false))[.size] as? NSNumber
        progress(.init(
            phase: .downloading,
            completedBytes: size?.int64Value ?? 0,
            totalBytes: expectedByteSize > 0 ? expectedByteSize : size?.int64Value
        ))
    }

    private func ensureAvailableDiskSpace(for artifact: ModelReleaseArtifact) throws {
        guard artifact.byteSize > 0 else { return }
        let values = try cache.appSupportDirectory
            .deletingLastPathComponent()
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        guard let available = values.volumeAvailableCapacityForImportantUsage else { return }
        let required = artifact.byteSize * 3
        if available < required {
            throw ModelDownloadError.insufficientDiskSpace(required: required, available: available)
        }
    }

    static func sha256Hex(for url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = SHA256()
        while true {
            let data = try handle.read(upToCount: 1_048_576) ?? Data()
            if data.isEmpty { break }
            hasher.update(data: data)
        }
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

}

private struct StoredZipExtractor {
    private let fileManager: FileManager

    init(fileManager: FileManager) {
        self.fileManager = fileManager
    }

    func extract(archive: URL, to destination: URL) throws {
        let data = try Data(contentsOf: archive, options: .mappedIfSafe)
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)

        var offset = 0
        var sawEntry = false
        while offset + 4 <= data.count {
            let signature = data.uint32LE(at: offset)
            if signature == 0x0201_4B50 || signature == 0x0605_4B50 { break }
            guard signature == 0x0403_4B50 else { throw ModelDownloadError.invalidZipArchive }
            guard offset + 30 <= data.count else { throw ModelDownloadError.invalidZipArchive }

            let flags = data.uint16LE(at: offset + 6)
            let method = data.uint16LE(at: offset + 8)
            let compressedSize = Int(data.uint32LE(at: offset + 18))
            let fileNameLength = Int(data.uint16LE(at: offset + 26))
            let extraLength = Int(data.uint16LE(at: offset + 28))
            let nameStart = offset + 30
            let nameEnd = nameStart + fileNameLength
            let contentsStart = nameEnd + extraLength
            let contentsEnd = contentsStart + compressedSize
            guard nameEnd <= data.count, contentsEnd <= data.count else { throw ModelDownloadError.invalidZipArchive }
            guard flags & 0x0008 == 0 else { throw ModelDownloadError.invalidZipArchive }

            let nameData = data[nameStart..<nameEnd]
            guard let entryName = String(data: nameData, encoding: .utf8), !entryName.isEmpty else {
                throw ModelDownloadError.invalidZipArchive
            }
            try validate(entryName: entryName)

            let entryURL = destination.appending(path: entryName, directoryHint: entryName.hasSuffix("/") ? .isDirectory : .notDirectory)
            if entryName.hasSuffix("/") {
                try fileManager.createDirectory(at: entryURL, withIntermediateDirectories: true)
            } else {
                guard method == 0 else { throw ModelDownloadError.unsupportedZipCompression(method: method) }
                try fileManager.createDirectory(at: entryURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data[contentsStart..<contentsEnd].write(to: entryURL)
            }

            sawEntry = true
            offset = contentsEnd
        }

        if !sawEntry { throw ModelDownloadError.invalidZipArchive }
    }

    private func validate(entryName: String) throws {
        if entryName.hasPrefix("/") || entryName.hasPrefix("\\") {
            throw ModelDownloadError.unsafeZipEntry(entryName)
        }
        let components = entryName.split(separator: "/", omittingEmptySubsequences: false)
        if components.contains("..") {
            throw ModelDownloadError.unsafeZipEntry(entryName)
        }
    }
}

private extension Data {
    func uint16LE(at offset: Int) -> UInt16 {
        UInt16(self[offset]) | (UInt16(self[offset + 1]) << 8)
    }

    func uint32LE(at offset: Int) -> UInt32 {
        UInt32(self[offset])
            | (UInt32(self[offset + 1]) << 8)
            | (UInt32(self[offset + 2]) << 16)
            | (UInt32(self[offset + 3]) << 24)
    }
}
