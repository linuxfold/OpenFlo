import Foundation

enum SeqtometryDemoDownloadError: Error, LocalizedError {
    case missingCacheDirectory
    case extractionFailed(Int32)
    case matrixNotFound

    var errorDescription: String? {
        switch self {
        case .missingCacheDirectory:
            return "Could not locate the Application Support directory."
        case .extractionFailed(let status):
            return "Could not extract the PBMC3k demo archive. tar exited with status \(status)."
        case .matrixNotFound:
            return "The PBMC3k demo matrix was not found after download."
        }
    }
}

enum SeqtometryDemoDownloader {
    private static let pbmc3kArchiveURL = URL(
        string: "https://s3-us-west-2.amazonaws.com/10x.files/samples/cell/pbmc3k/pbmc3k_filtered_gene_bc_matrices.tar.gz"
    )!

    static func pbmc3kMatrixDirectory() async throws -> URL {
        let cacheDirectory = try demoCacheDirectory()
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        if let existing = findMatrixDirectory(in: cacheDirectory) {
            return existing
        }

        let archiveURL = cacheDirectory.appendingPathComponent("pbmc3k_filtered_gene_bc_matrices.tar.gz")
        if !FileManager.default.fileExists(atPath: archiveURL.path) {
            let (temporaryURL, _) = try await URLSession.shared.download(from: pbmc3kArchiveURL)
            if FileManager.default.fileExists(atPath: archiveURL.path) {
                try FileManager.default.removeItem(at: archiveURL)
            }
            try FileManager.default.moveItem(at: temporaryURL, to: archiveURL)
        }

        try extractArchive(archiveURL, to: cacheDirectory)
        guard let matrixDirectory = findMatrixDirectory(in: cacheDirectory) else {
            throw SeqtometryDemoDownloadError.matrixNotFound
        }
        return matrixDirectory
    }

    private static func demoCacheDirectory() throws -> URL {
        guard let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw SeqtometryDemoDownloadError.missingCacheDirectory
        }
        return applicationSupport
            .appendingPathComponent("OpenFlo", isDirectory: true)
            .appendingPathComponent("SeqtometryDemo", isDirectory: true)
    }

    private static func extractArchive(_ archiveURL: URL, to destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-xzf", archiveURL.path, "-C", destination.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw SeqtometryDemoDownloadError.extractionFailed(process.terminationStatus)
        }
    }

    private static func findMatrixDirectory(in directory: URL) -> URL? {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return nil
        }

        for case let url as URL in enumerator where url.lastPathComponent == "matrix.mtx" {
            return url.deletingLastPathComponent()
        }
        return nil
    }
}
