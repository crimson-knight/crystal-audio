# crystal-audio

Cross-platform audio library for Crystal. Record microphone input, system audio, or both simultaneously on macOS and iOS.

## Library Skills

| Skill | Description |
|-------|-------------|
| `/getting-started` | Installation, platform setup, basic recording |
| `/microphone-recording` | Mic recording API, AudioQueue, WAV output |
| `/ios-integration` | Cross-compile Crystal for iOS, Xcode setup, linker fixes |
| `/system-audio` | System audio capture via ProcessTap/ScreenCaptureKit |

## Build

```bash
make ext          # Compile C/ObjC extensions (required first)
make record       # CLI recorder sample
make macos-app    # macOS desktop GUI
make ios-app      # iOS Simulator app (needs crystal-alpha + xcodegen)
make spec         # Run tests
```

## Key Architecture Decisions

- ObjC runtime called directly via `objc_msgSend` wrappers (no ObjC compiler needed for Crystal)
- C extensions handle AudioBufferList (flexible array member) and ObjC block ABI
- iOS uses `-force_load` linker flag to prevent Xcode dead-stripping Crystal runtime
- System audio: ProcessTap on macOS 14.2+, ScreenCaptureKit on 13.0+

---

# Shards-Alpha: Supply Chain Compliance for Crystal

This project uses shards-alpha, a Crystal package manager with built-in supply chain compliance tools.

## Available Commands

| Command | Description |
|---------|-------------|
| `shards-alpha install` | Install dependencies from shard.yml |
| `shards-alpha update` | Update dependencies to latest compatible versions |
| `shards-alpha audit` | Scan dependencies for known vulnerabilities (OSV database) |
| `shards-alpha licenses` | List dependency licenses with SPDX compliance checking |
| `shards-alpha policy check` | Check dependencies against policy rules |
| `shards-alpha diff` | Show dependency changes between lockfile states |
| `shards-alpha compliance-report` | Generate unified compliance report |
| `shards-alpha sbom` | Generate Software Bill of Materials (SPDX/CycloneDX) |
| `shards-alpha assistant status` | Show assistant config version and state |
| `shards-alpha assistant update` | Update skills, agents, and settings to latest |

## Quick Compliance Check

```sh
shards-alpha audit                    # Check for vulnerabilities
shards-alpha licenses --check         # Verify license compliance
shards-alpha policy check             # Enforce dependency policies
```

## Key Files

| File | Purpose |
|------|---------|
| `shard.yml` | Dependency specification |
| `shard.lock` | Locked dependency versions |
| `.shards-policy.yml` | Dependency policy rules (optional) |
| `.shards-audit-ignore` | Suppressed vulnerability IDs (optional) |

## MCP Compliance Server

An MCP server exposes all compliance tools for AI agent integration:

```sh
shards-alpha mcp-server              # Start stdio MCP server
shards-alpha mcp-server --interactive # Manual testing mode
```

Supports MCP protocol versions: 2025-11-25, 2025-06-18, 2025-03-26, 2024-11-05.
