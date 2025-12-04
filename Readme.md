# dincheck – Directory Integrity Checker

dincheck is a Swift command-line utility for long-term file integrity. It records SHA-256 hashes in a hidden manifest so it can flag even a single flipped bit: silent corruption, damaged sectors, backup glitches, or accidental edits.

## Features
- Recursive hashing of all regular files
- Detects: `CHANGED` (contents differ), `MISSING` (listed file gone), `NEW` (untracked file present)
- Uses SHA-256 for robust integrity verification
- Skips internal manifest files automatically
- Three modes: create, verify, update
- Human-readable output for monitoring or automation

## Download binaries
Binaries are produced for macOS (universal) and Linux x86_64 via GitHub Actions. From a tagged release, download the asset that matches your OS (replace `<owner>/<repo>` with your GitHub path):

```bash
# macOS universal binary
curl -L https://github.com/<owner>/<repo>/releases/download/v1.0.0/dincheck-macos-universal.tar.gz \
  | tar -xz
chmod +x dincheck
sudo mv dincheck /usr/local/bin

# Linux x86_64 binary
curl -L https://github.com/<owner>/<repo>/releases/download/v1.0.0/dincheck-linux-x86_64.tar.gz \
  | tar -xz
chmod +x dincheck
sudo mv dincheck /usr/local/bin
```

Verify downloads with the accompanying `.sha256` file:

```bash
shasum -a 256 -c dincheck-macos-universal.tar.gz.sha256   # macOS
sha256sum -c dincheck-linux-x86_64.tar.gz.sha256         # Linux
```

## Build from source (SwiftPM)
- macOS (universal):

```bash
swift build -c release --arch arm64 --arch x86_64
cp .build/apple/Products/Release/dincheck ./dincheck
```

- Linux:

```bash
swift build -c release
cp .build/release/dincheck ./dincheck
```

Optionally strip the binary to shrink size (`strip dincheck`).

## Usage

Create a new manifest (fails if one exists):

```bash
dincheck create /path/to/directory
```

Verify against existing manifest (reports differences, does not rewrite):

```bash
dincheck verify /path/to/directory
```

Example verification output:

```
CHANGED: photos/IMG_1013.JPG
MISSING: docs/old_report.pdf
NEW: archive/new.zip

Summary:
  OK:       1283
  CHANGED:  1
  MISSING:  1
  NEW:      1

Verification: differences detected.
```

Update the manifest (report differences, then rewrite manifest):

```bash
dincheck update /path/to/directory
```

Print the version:

```bash
dincheck --version
```

## How it works
Running `dincheck create /path/to/directory` writes a hidden manifest at the directory root:

```
/path/to/directory/.checksums.sha256
```

The manifest lists every regular file (recursively) with its SHA-256 checksum. Subsequent `verify` or `update` runs recompute hashes and compare against the manifest. SHA-256 output changes if even one bit differs, so corruption is reliably detected. Nested `.checksums.sha256` files in subdirectories are ignored automatically.

## Internal behavior
- Files are processed in a streaming manner (handles large files)
- Relative paths (not absolute) are stored in the manifest
- Manifest is rewritten atomically
- Package bundles are not descended into unless they contain regular files

## CI and releases
`.github/workflows/release.yml` builds release binaries for macOS and Linux on every PR and push, and attaches artifacts to tags (`v*`).
