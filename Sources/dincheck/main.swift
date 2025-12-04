#!/usr/bin/env swift

import Foundation

#if canImport(CryptoKit)
import CryptoKit
typealias SHA256Hash = CryptoKit.SHA256
#else
import Crypto
typealias SHA256Hash = Crypto.SHA256
#endif

let version = "1.0.0"
let manifestFileName = ".checksums.sha256"

struct ManifestEntry {
    let relativePath: String
    let hash: String
}

// MARK: - Hashing

func sha256(forFileAt url: URL) throws -> String {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }

    var hasher = SHA256Hash()

    while true {
        let data = handle.readData(ofLength: 64 * 1024)
        if data.count == 0 { break }
        hasher.update(data: data)
    }

    let digest = hasher.finalize()
    return digest.map { String(format: "%02x", $0) }.joined()
}

// MARK: - File collection

func collectFiles(under root: URL) -> [URL] {
    var files: [URL] = []
    let fm = FileManager.default

    guard let enumerator = fm.enumerator(
        at: root,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsPackageDescendants],
        errorHandler: { url, error in
            fputs("Error traversing \(url.path): \(error.localizedDescription)\n", stderr)
            return true
        }
    ) else {
        return files
    }

    for case let fileURL as URL in enumerator {
        if fileURL.lastPathComponent == manifestFileName {
            continue
        }

        do {
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            if values.isRegularFile == true {
                files.append(fileURL)
            }
        } catch {
            fputs("Error reading attributes for \(fileURL.path): \(error.localizedDescription)\n", stderr)
        }
    }

    return files
}

// MARK: - Manifest I/O

func loadManifest(from url: URL) -> [String: String] {
    var result: [String: String] = [:]

    guard let data = try? Data(contentsOf: url),
          let content = String(data: data, encoding: .utf8) else {
        return result
    }

    content.enumerateLines { line, _ in
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return }

        let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        if parts.count == 2 {
            let hash = String(parts[0])
            let path = String(parts[1]).trimmingCharacters(in: .whitespaces)
            result[path] = hash
        }
    }

    return result
}

func writeManifest(at url: URL, entries: [ManifestEntry]) throws {
    let sorted = entries.sorted { $0.relativePath < $1.relativePath }
    var lines: [String] = []
    for entry in sorted {
        lines.append("\(entry.hash)  \(entry.relativePath)")
    }
    let content = lines.joined(separator: "\n") + "\n"
    guard let data = content.data(using: .utf8) else {
        throw NSError(domain: "dincheck", code: 1, userInfo: [NSLocalizedDescriptionKey: "UTF-8 encoding failed"])
    }
    try data.write(to: url, options: .atomic)
}

// MARK: - Common helpers

func normalizeRoot(from path: String) -> URL {
    let fm = FileManager.default
    let rootURL = URL(fileURLWithPath: path).standardizedFileURL
    var isDir: ObjCBool = false
    guard fm.fileExists(atPath: rootURL.path, isDirectory: &isDir), isDir.boolValue else {
        fputs("Root path is not a directory: \(rootURL.path)\n", stderr)
        exit(1)
    }
    return rootURL
}

func computeEntries(under rootURL: URL) -> [ManifestEntry] {
    let fileURLs = collectFiles(under: rootURL)
    print("Scanning \(fileURLs.count) files under \(rootURL.path)")

    var entries: [ManifestEntry] = []

    for fileURL in fileURLs {
        let fullPath = fileURL.path
        var relPath = fullPath
        if fullPath.hasPrefix(rootURL.path + "/") {
            relPath = String(fullPath.dropFirst(rootURL.path.count + 1))
        } else if fullPath == rootURL.path {
            relPath = "."
        }

        do {
            let hash = try sha256(forFileAt: fileURL)
            entries.append(ManifestEntry(relativePath: relPath, hash: hash))
        } catch {
            fputs("Error hashing \(fileURL.path): \(error.localizedDescription)\n", stderr)
        }
    }

    return entries
}

// MARK: - Operations

func createManifest(rootPath: String) {
    let fm = FileManager.default
    let rootURL = normalizeRoot(from: rootPath)
    let manifestURL = rootURL.appendingPathComponent(manifestFileName)

    if fm.fileExists(atPath: manifestURL.path) {
        fputs("Manifest already exists at \(manifestURL.path). Use 'update' instead.\n", stderr)
        exit(1)
    }

    print("Creating new manifest at \(manifestURL.path)")
    let entries = computeEntries(under: rootURL)

    do {
        try writeManifest(at: manifestURL, entries: entries)
        print("Created manifest with \(entries.count) entries.")
    } catch {
        fputs("Failed to write manifest: \(error.localizedDescription)\n", stderr)
        exit(1)
    }
}

func verifyManifest(rootPath: String) {
    let fm = FileManager.default
    let rootURL = normalizeRoot(from: rootPath)
    let manifestURL = rootURL.appendingPathComponent(manifestFileName)

    guard fm.fileExists(atPath: manifestURL.path) else {
        fputs("No manifest found at \(manifestURL.path). Run 'create' first.\n", stderr)
        exit(1)
    }

    let oldManifest = loadManifest(from: manifestURL)
    print("Loaded manifest with \(oldManifest.count) entries.")

    let currentEntries = computeEntries(under: rootURL)
    var currentMap: [String: String] = [:]
    for e in currentEntries {
        currentMap[e.relativePath] = e.hash
    }

    var okFiles: [String] = []
    var changedFiles: [String] = []
    var missingFiles: [String] = []
    var newFiles: [String] = []

    for (path, oldHash) in oldManifest {
        if let currentHash = currentMap[path] {
            if currentHash == oldHash {
                okFiles.append(path)
            } else {
                changedFiles.append(path)
                print("CHANGED: \(path)")
            }
        } else {
            missingFiles.append(path)
            print("MISSING: \(path)")
        }
    }

    for (path, _) in currentMap where oldManifest[path] == nil {
        newFiles.append(path)
        print("NEW: \(path)")
    }

    print("")
    print("Summary:")
    print("  OK:       \(okFiles.count)")
    print("  CHANGED:  \(changedFiles.count)")
    print("  MISSING:  \(missingFiles.count)")
    print("  NEW:      \(newFiles.count)")

    if changedFiles.isEmpty && missingFiles.isEmpty && newFiles.isEmpty {
        print("Verification: CLEAN (no differences).")
    } else {
        print("Verification: differences detected.")
        exit(2)
    }
}

func updateManifest(rootPath: String) {
    let fm = FileManager.default
    let rootURL = normalizeRoot(from: rootPath)
    let manifestURL = rootURL.appendingPathComponent(manifestFileName)

    let oldManifest: [String: String]
    if fm.fileExists(atPath: manifestURL.path) {
        oldManifest = loadManifest(from: manifestURL)
        print("Loaded existing manifest with \(oldManifest.count) entries.")
    } else {
        oldManifest = [:]
        print("No existing manifest found; will create a new one.")
    }

    let currentEntries = computeEntries(under: rootURL)
    var currentMap: [String: String] = [:]
    for e in currentEntries {
        currentMap[e.relativePath] = e.hash
    }

    var changedFiles: [String] = []
    var missingFiles: [String] = []
    var newFiles: [String] = []

    for (path, oldHash) in oldManifest {
        if let currentHash = currentMap[path] {
            if currentHash != oldHash {
                changedFiles.append(path)
                print("CHANGED: \(path)")
            }
        } else {
            missingFiles.append(path)
            print("MISSING: \(path)")
        }
    }

    for (path, _) in currentMap where oldManifest[path] == nil {
        newFiles.append(path)
        print("NEW: \(path)")
    }

    print("")
    print("Updating manifest at \(manifestURL.path)")
    do {
        try writeManifest(at: manifestURL, entries: currentEntries)
    } catch {
        fputs("Failed to write updated manifest: \(error.localizedDescription)\n", stderr)
        exit(1)
    }

    print("Update complete.")
    print("  Total entries: \(currentEntries.count)")
    print("  CHANGED:       \(changedFiles.count)")
    print("  MISSING:       \(missingFiles.count)")
    print("  NEW:           \(newFiles.count)")
}

// MARK: - Argument parsing

func usage(prog: String) -> String {
    return """
Usage:
  \(prog) create <directory>
  \(prog) verify <directory>
  \(prog) update <directory>
  \(prog) --version

Description:
  create  - create a new .checksums.sha256 manifest at the directory root (fails if it exists)
  verify  - verify current files against existing manifest, report differences
  update  - recompute hashes, report differences vs old manifest, then rewrite manifest
  --version - print the current dincheck version
"""
}

func printUsageAndExit(prog: String) -> Never {
    fputs(usage(prog: prog), stderr)
    exit(1)
}

func main() {
    let args = CommandLine.arguments
    let prog = (args.first as NSString?)?.lastPathComponent ?? "dincheck"

    if args.count == 2 && (args[1] == "--help" || args[1] == "-h") {
        fputs(usage(prog: prog), stderr)
        exit(0)
    }

    if args.count == 2 && (args[1] == "--version" || args[1] == "-V") {
        print("\(prog) \(version)")
        exit(0)
    }

    guard args.count >= 3 else {
        printUsageAndExit(prog: prog)
    }

    let command = args[1]
    let rootPath = args[2]

    switch command {
    case "create":
        createManifest(rootPath: rootPath)
    case "verify":
        verifyManifest(rootPath: rootPath)
    case "update":
        updateManifest(rootPath: rootPath)
    default:
        fputs("Unknown command: \(command)\n", stderr)
        printUsageAndExit(prog: prog)
    }
}

main()
