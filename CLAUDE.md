# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**dincheck** is a Swift command-line utility for long-term file integrity monitoring. It creates SHA-256 hash manifests (`.checksums.sha256`) to detect silent data corruption, damaged sectors, backup glitches, or accidental file modifications.

## Build Commands

### Development Build
```bash
swift build
```

### Release Build (macOS Universal)
```bash
swift build -c release --arch arm64 --arch x86_64
cp .build/apple/Products/Release/dincheck ./dincheck
```

### Release Build (Linux)
```bash
swift build -c release
cp .build/release/dincheck ./dincheck
```

### Strip Binary (Optional)
```bash
strip dincheck
```

## Code Architecture

### Monolithic Design
The entire application is contained in a single file: `Sources/dincheck/main.swift` (~348 lines). This is intentional for simplicity and transparency.

### Core Components (Sequential Flow)

1. **Argument Parsing** (`main` function)
   - Parses command: `create`, `verify`, `update`, `--version`, `--help`
   - Validates directory path

2. **File Collection** (`collectFiles`)
   - Recursively enumerates all regular files
   - Automatically excludes `.checksums.sha256` manifest files
   - Skips package bundles (`.skipsPackageDescendants`)

3. **SHA-256 Hashing** (`sha256`)
   - **Streaming implementation**: Reads files in 64KB chunks
   - Handles arbitrarily large files without loading into memory
   - Cross-platform: Uses `CryptoKit` (macOS) or `swift-crypto` (Linux)

4. **Manifest I/O** (`loadManifest`, `writeManifest`)
   - **Format**: `<hash>  <relative_path>` (two spaces separator)
   - Sorted by relative path for determinism
   - **Atomic writes**: Uses `.atomic` option for crash safety

5. **Commands** (`createManifest`, `verifyManifest`, `updateManifest`)
   - **create**: Fails if manifest exists (prevents overwrites)
   - **verify**: Read-only check, exits with code 2 if differences found
   - **update**: Reports differences, then rewrites manifest

### Cross-Platform Compatibility

Conditional imports handle platform differences:
```swift
#if canImport(CryptoKit)
import CryptoKit
typealias SHA256Hash = CryptoKit.SHA256
#else
import Crypto
typealias SHA256Hash = Crypto.SHA256
#endif
```

**Note**: Path handling uses hardcoded `/` separator (not Windows-compatible).

## CI/CD and Releases

### Automated Release Process

**Trigger**: Push a version tag matching `v*` pattern
```bash
git tag v1.0.1
git push origin v1.0.1
```

### Version Consistency Requirement

The CI pipeline **enforces** that the version in `Sources/dincheck/main.swift` (line 13) matches the git tag:
```swift
let version = "1.0.0"  // Must match git tag (without 'v' prefix)
```

**Before creating a release tag**, update the version string in `main.swift` to match.

### CI Workflow Features

The `.github/workflows/release.yml` pipeline includes:
- **Pinned Swift version**: 6.0.2 (defined in `env.SWIFT_VERSION`)
- **Build caching**: Swift installation and `.build` directory
- **Binary stripping**: Reduces download size by 30-50%
- **Smoke tests**: Verifies `--version`, `--help`, and basic create/verify functionality
- **Checksum validation**: Ensures package integrity before release
- **Version consistency check**: Blocks release if code version ≠ git tag

### Updating Swift Version

To update the Swift version used in CI, modify the `env` section in `.github/workflows/release.yml`:
```yaml
env:
  SWIFT_VERSION: "6.0.2"  # Update this
```

## Manifest Format

### File Structure
```
<sha256_hash>  <relative_path>
```

Example:
```
a1b2c3d4...  photos/IMG_1013.JPG
e5f6g7h8...  docs/report.pdf
```

### Key Properties
- **Two spaces** separate hash from path
- **Relative paths only** (no absolute paths, no parent references `..`)
- **Sorted alphabetically** by path
- **UTF-8 encoded**
- **Newline-terminated** (ends with `\n`)

## Exit Codes

- **0**: Success (clean verification, successful create/update)
- **1**: Error (invalid arguments, manifest issues, file access errors)
- **2**: Differences detected during verify (CHANGED/MISSING/NEW files)

## Dependencies

- **swift-crypto** (≥3.5.0): Provides cross-platform SHA-256 hashing
  - Transitive: swift-asn1

Update dependencies by modifying `Package.swift`.

## Testing Strategy

**Current state**: No automated tests (identified gap in improvement plans).

When implementing tests:
- Test hash correctness against known SHA-256 test vectors
- Test manifest parsing with edge cases (spaces in filenames, Unicode)
- Test all three commands (create, verify, update)
- Verify cross-platform behavior
- Test large file handling (streaming)

## Important Constraints

### Hard-Coded Values
- Manifest filename: `.checksums.sha256` (line 14 in main.swift)
- Chunk size: 64KB for streaming hash computation
- Path separator: `/` (not Windows-compatible)

### Design Decisions
- **No configuration files**: All behavior is hard-coded for simplicity
- **No ignore patterns**: All files are hashed (future: `.dincheckignore` support)
- **No progress reporting**: Silent operation (future: `--verbose` flag)
- **Human-readable output only**: No JSON/machine format (yet)

## Common Development Scenarios

### Adding a New Command
1. Add case to `switch command` in `main()` function
2. Implement new command function following pattern of existing commands
3. Update `usage()` function with new command documentation
4. Update README.md with usage examples

### Modifying Hash Algorithm
- Change `SHA256Hash` typealias and update `sha256()` function
- Update manifest filename convention (currently `.checksums.sha256`)
- Consider migration path for existing manifests

### Adding Command-Line Flags
Currently uses simple `CommandLine.arguments` parsing. For complex flags, consider:
- Keep simple parsing for `--help`, `--version`
- Add optional flags after command: `dincheck verify /path --flag`
- Parse in command-specific functions (not in `main`)

## Release Checklist

Before creating a new release:
1. Update `let version = "X.Y.Z"` in `Sources/dincheck/main.swift` (line 13)
2. Commit the version change
3. Create and push git tag: `git tag vX.Y.Z && git push origin vX.Y.Z`
4. Wait for GitHub Actions to complete (~5-10 minutes)
5. Verify release artifacts on GitHub Releases page

The CI pipeline will automatically:
- Build universal macOS binary (arm64 + x86_64)
- Build Linux x86_64 binary
- Generate SHA-256 checksums
- Create GitHub release with installation instructions
- Fail if version in code doesn't match tag
