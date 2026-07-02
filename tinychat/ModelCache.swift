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

struct ModelCache {
    static let baseModelID = "qwen3-0.6b"
    static let baseDisplayName = "Qwen3 0.6B"

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

    func baseModelStatus() -> ModelCacheStatus {
        let url = baseModelDirectory
        let exists = fileManager.fileExists(atPath: url.path(percentEncoded: false))
        let state: ModelCacheStatus.State = exists ? .installed(url) : .missing
        return ModelCacheStatus(modelID: Self.baseModelID, displayName: Self.baseDisplayName, state: state)
    }
}
