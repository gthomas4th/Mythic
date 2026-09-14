import Foundation
import CryptoKit

/// Copies only a selected ROM and its required parts into a new, verified folder.
public enum ROMLocalDownload {
    public static func copy(content: URL, sourceRoot: URL, destinationParent: URL,
                            progress: @Sendable (Int64, Int64) -> Void = { _, _ in }) throws -> URL {
        let fm = FileManager.default
        let root = sourceRoot.resolvingSymlinksInPath()
        let content = content.resolvingSymlinksInPath()
        guard content.path.hasPrefix(root.path + "/") else { throw ROMError.invalid }
        var files = try ROMIndex.parts(of: content, root: root)
        // A PS3 disc requires the whole game directory, not just its boot executable.
        if content.lastPathComponent.uppercased() == "EBOOT.BIN" {
            let usrdir = content.deletingLastPathComponent()
            let ps3 = usrdir.deletingLastPathComponent()
            guard usrdir.lastPathComponent.uppercased() == "USRDIR", ps3.lastPathComponent.uppercased() == "PS3_GAME" else { throw ROMError.invalid }
            let gameRoot = ps3.deletingLastPathComponent()
            guard gameRoot.path.hasPrefix(root.path + "/") else { throw ROMError.invalid }
            var enumerationError: Error?
            guard let iterator = fm.enumerator(at: gameRoot, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], errorHandler: { _, error in enumerationError = error; return false }) else { throw ROMError.missingPart }
            files = []
            for case let file as URL in iterator {
                let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard values.isSymbolicLink != true else { throw ROMError.invalid }
                if values.isRegularFile == true { files.append(file) }
            }
            if let error = enumerationError { throw error }
        }
        files = Array(Set(files)).sorted { $0.path < $1.path }
        let total = try files.reduce(Int64(0)) { try $0 + Int64($1.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) }
        let token = UUID().uuidString
        let stage = destinationParent.appendingPathComponent(".rom-download-" + token)
        let name = String(content.deletingPathExtension().lastPathComponent.prefix(60))
        let result = destinationParent.appendingPathComponent(name + "-" + token.prefix(8))
        try fm.createDirectory(at: stage, withIntermediateDirectories: false)
        var committed = false
        defer { if !committed { try? fm.removeItem(at: stage) } }
        var received: Int64 = 0
        var lastProgress = Date.distantPast
        for file in files {
            try Task.checkCancellation()
            let source = file.resolvingSymlinksInPath()
            guard source.path.hasPrefix(root.path + "/") else { throw ROMError.invalid }
            let relative = String(source.path.dropFirst(root.path.count + 1))
            let destination = stage.appendingPathComponent(relative)
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard fm.createFile(atPath: destination.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
            let before = try source.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let input = try FileHandle(forReadingFrom: source)
            let output = try FileHandle(forWritingTo: destination)
            defer { try? input.close(); try? output.close() }
            var hash = SHA256()
            while let chunk = try input.read(upToCount: 1_048_576), !chunk.isEmpty {
                try Task.checkCancellation()
                try output.write(contentsOf: chunk); hash.update(data: chunk)
                received += Int64(chunk.count)
                if Date().timeIntervalSince(lastProgress) >= 0.25 || received == total {
                    progress(received, total); lastProgress = Date()
                }
            }
            try output.synchronize(); try output.close(); try input.close()
            let verify = try FileHandle(forReadingFrom: destination)
            defer { try? verify.close() }
            var writtenHash = SHA256()
            while let chunk = try verify.read(upToCount: 1_048_576), !chunk.isEmpty {
                try Task.checkCancellation(); writtenHash.update(data: chunk)
            }
            let after = try source.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            guard before.fileSize == after.fileSize, before.contentModificationDate == after.contentModificationDate else { throw ROMError.invalid }
            guard hash.finalize() == writtenHash.finalize() else { throw ROMError.invalid }
        }
        let relative = String(content.path.dropFirst(root.path.count + 1))
        _ = try ROMIndex.parts(of: stage.appendingPathComponent(relative), root: stage)
        try fm.moveItem(at: stage, to: result)
        committed = true
        return result
    }
}
