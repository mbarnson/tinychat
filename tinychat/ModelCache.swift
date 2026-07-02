//
//  ModelCache.swift
//  tinychat
//
//  Created by Matthew Barnson on 7/1/26.
//

import Foundation

struct ModelCacheStatus: Equatable {
    enum State: Equatable {
        case missing
        case installed(URL)
    }

    let modelID: String
    let displayName: String
    let state: State

    var isInstalled: Bool {
        if case .installed = state { true } else { false }
    }
}

struct ModelArtifactManifest: Codable, Equatable, Sendable {
    let modelID: String
    let displayName: String
    let platform: String
    let version: String
    let sourceURL: URL
    let expectedFiles: [String]

    init(
        modelID: String = ModelCache.baseModelID,
        displayName: String = ModelCache.baseDisplayName,
        platform: String = ModelCache.platformDirectoryName,
        version: String,
        sourceURL: URL,
        expectedFiles: [String]
    ) {
        self.modelID = modelID
        self.displayName = displayName
        self.platform = platform
        self.version = version
        self.sourceURL = sourceURL
        self.expectedFiles = expectedFiles
    }
}

struct InstalledModelMetadata: Codable, Equatable, Sendable {
    let modelID: String
    let displayName: String
    let platform: String
    let version: String
    let installedAt: Date
    let sourceURL: URL
}

enum ModelCacheError: LocalizedError, Equatable {
    case manifestModelMismatch(expected: String, actual: String)
    case manifestPlatformMismatch(expected: String, actual: String)
    case sourceDirectoryMissing(URL)
    case expectedFileMissing(String)

    var errorDescription: String? {
        switch self {
        case .manifestModelMismatch(let expected, let actual):
            "Manifest model mismatch: expected \(expected), got \(actual)."
        case .manifestPlatformMismatch(let expected, let actual):
            "Manifest platform mismatch: expected \(expected), got \(actual)."
        case .sourceDirectoryMissing(let url):
            "Model source directory is missing: \(url.path(percentEncoded: false))"
        case .expectedFileMissing(let file):
            "Model artifact is missing required file: \(file)"
        }
    }
}

struct ModelCache {
    static let baseModelID = "qwen3-0.6b"
    static let baseDisplayName = "Qwen3 0.6B"
    static let metadataFileName = "tinychat-model.json"

    static var platformDirectoryName: String {
#if os(iOS)
        "iOS"
#else
        "macOS"
#endif
    }

    private let fileManager: FileManager
    private let appSupportOverride: URL?

    init(fileManager: FileManager = .default, appSupportOverride: URL? = nil) {
        self.fileManager = fileManager
        self.appSupportOverride = appSupportOverride
    }

    var appSupportDirectory: URL {
        if let appSupportOverride { return appSupportOverride }

        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                .appending(path: "Application Support", directoryHint: .isDirectory)
        return base.appending(path: "tinychat", directoryHint: .isDirectory)
    }

    var baseModelDirectory: URL {
        appSupportDirectory
            .appending(path: "Models", directoryHint: .isDirectory)
            .appending(path: Self.baseModelID, directoryHint: .isDirectory)
            .appending(path: Self.platformDirectoryName, directoryHint: .isDirectory)
    }

    var baseModelMetadataURL: URL {
        baseModelDirectory.appending(path: Self.metadataFileName, directoryHint: .notDirectory)
    }

    func baseModelStatus() -> ModelCacheStatus {
        let url = baseModelDirectory
        let exists = fileManager.fileExists(atPath: url.path(percentEncoded: false))
        let state: ModelCacheStatus.State = exists ? .installed(url) : .missing
        return ModelCacheStatus(modelID: Self.baseModelID, displayName: Self.baseDisplayName, state: state)
    }

    func installBaseModel(from manifest: ModelArtifactManifest, installedAt: Date = .now) throws {
        try validate(manifest)

        let parent = baseModelDirectory.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)

        let stagingDirectory = parent.appending(
            path: ".installing-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let backupDirectory = parent.appending(
            path: ".replaced-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )

        try fileManager.copyItem(at: manifest.sourceURL, to: stagingDirectory)
        try writeMetadata(for: manifest, installedAt: installedAt, into: stagingDirectory)

        let destinationExists = fileManager.fileExists(atPath: baseModelDirectory.path(percentEncoded: false))
        if destinationExists {
            try fileManager.moveItem(at: baseModelDirectory, to: backupDirectory)
        }

        do {
            try fileManager.moveItem(at: stagingDirectory, to: baseModelDirectory)
            if destinationExists {
                try? fileManager.removeItem(at: backupDirectory)
            }
        } catch {
            if destinationExists, fileManager.fileExists(atPath: backupDirectory.path(percentEncoded: false)) {
                try? fileManager.moveItem(at: backupDirectory, to: baseModelDirectory)
            }
            try? fileManager.removeItem(at: stagingDirectory)
            throw error
        }
    }

    func removeBaseModel() throws {
        if fileManager.fileExists(atPath: baseModelDirectory.path(percentEncoded: false)) {
            try fileManager.removeItem(at: baseModelDirectory)
        }
    }

    private func validate(_ manifest: ModelArtifactManifest) throws {
        guard manifest.modelID == Self.baseModelID else {
            throw ModelCacheError.manifestModelMismatch(expected: Self.baseModelID, actual: manifest.modelID)
        }
        guard manifest.platform == Self.platformDirectoryName else {
            throw ModelCacheError.manifestPlatformMismatch(
                expected: Self.platformDirectoryName,
                actual: manifest.platform
            )
        }
        guard fileManager.fileExists(atPath: manifest.sourceURL.path(percentEncoded: false)) else {
            throw ModelCacheError.sourceDirectoryMissing(manifest.sourceURL)
        }

        for file in manifest.expectedFiles {
            let url = manifest.sourceURL.appending(path: file, directoryHint: .notDirectory)
            guard fileManager.fileExists(atPath: url.path(percentEncoded: false)) else {
                throw ModelCacheError.expectedFileMissing(file)
            }
        }
    }

    private func writeMetadata(
        for manifest: ModelArtifactManifest,
        installedAt: Date,
        into directory: URL
    ) throws {
        let metadata = InstalledModelMetadata(
            modelID: manifest.modelID,
            displayName: manifest.displayName,
            platform: manifest.platform,
            version: manifest.version,
            installedAt: installedAt,
            sourceURL: manifest.sourceURL
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(metadata)
        try data.write(to: directory.appending(path: Self.metadataFileName, directoryHint: .notDirectory))
    }
}
