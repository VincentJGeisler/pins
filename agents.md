# AI Agent Guide for PI.N.S.

## Quick Start

If you're an AI agent working with this codebase, **start by reading** [`architecture.md`](./architecture.md) for comprehensive understanding of:

- Project structure and component relationships
- Build process and toolchain
- Why Docker is required
- External dependencies and how they're managed
- Cross-platform compilation details
- Deployment architecture

---

## Key Files for Agents

### Build System
- **[`architecture.md`](./architecture.md)** - Complete architecture documentation (READ THIS FIRST)
- **[`BUILD.md`](./BUILD.md)** - User-facing build instructions
- **[`docker-build.sh`](./docker-build.sh)** - Docker build wrapper
- **[`Dockerfile.build`](./Dockerfile.build)** - Docker build environment
- **[`build-pi-package.sh`](./build-pi-package.sh)** - Main build orchestrator
- **[`download-external-libs.sh`](./download-external-libs.sh)** - External dependency fetcher

### Project Configuration
- **[`NINA/NINA.csproj`](./NINA/NINA.csproj)** - Main application project
- **[`CommonAssemblyInfo.cs`](./CommonAssemblyInfo.cs)** - Version information
- **[`.gitmodules`](./.gitmodules)** - Git submodules (plugins)

### Packaging
- **[`packaging/debian/`](./packaging/debian/)** - Debian maintainer scripts
- **[`packaging/systemd/`](./packaging/systemd/)** - Systemd service definition

---

## Common Agent Tasks

### Task: Understanding the Build Process
1. Read [`architecture.md`](./architecture.md) → "Build Process" section
2. Review [`build-pi-package.sh`](./build-pi-package.sh) for implementation
3. Check [`download-external-libs.sh`](./download-external-libs.sh) for dependency handling

### Task: Debugging Build Failures
1. Check error message context:
   - **"LFS quota"** → See [`architecture.md`](./architecture.md) → "External Dependencies"
   - **".so file not found"** → Check [`download-external-libs.sh`](./download-external-libs.sh) stub creation
   - **"dotnet not found"** → Verify Docker environment in [`Dockerfile.build`](./Dockerfile.build)
   - **"dpkg-deb failed"** → Check [`build-pi-package.sh`](./build-pi-package.sh) packaging section

2. Review recent changes to relevant files
3. Verify Docker build environment is up to date

### Task: Adding New External Dependencies
1. Read [`architecture.md`](./architecture.md) → "External Dependencies"
2. Modify [`download-external-libs.sh`](./download-external-libs.sh):
   - Add download logic (with error handling)
   - Add to stub library list if optional
   - Ensure absolute paths are used
3. Update [`NINA/NINA.csproj`](./NINA/NINA.csproj) if new files need copying
4. Test with full Docker build

### Task: Modifying Build Scripts
**IMPORTANT**: Build scripts must be compatible with Docker environment

- Use **absolute paths** or paths relative to `/build`
- Handle **errors gracefully** (vendors may be unavailable)
- Avoid **interactive prompts** (fully automated)
- Use **`set -euo pipefail`** for proper error handling (but with error catching for optional operations)
- Test **inside Docker container**, not just on host

### Task: Understanding Plugin Architecture
1. Read [`architecture.md`](./architecture.md) → "Plugin Architecture"
2. Review [`NINA.Plugin/`](./NINA.Plugin/) for plugin interface
3. Check [`.gitmodules`](./.gitmodules) for plugin submodules
4. Examine [`build-plugins.sh`](./build-plugins.sh) for plugin build process

### Task: Version Management
- Version defined in [`CommonAssemblyInfo.cs`](./CommonAssemblyInfo.cs)
- Extracted during build via `grep` in [`build-pi-package.sh`](./build-pi-package.sh):72
- Format: `3.3.0.1000-nightly`
- Used in .deb filename: `pins_{version}_arm64_{date}.deb`

---

## Critical Context for Agents

### Git LFS Fallback Strategy

**Problem**: The `NINA/External` submodule contains 140MB of binary files tracked in Git LFS. GitHub's LFS quota may be exceeded, preventing builds.

**Solution** (Intelligent Fallback):
1. **Try LFS First**: Attempt normal submodule update with LFS enabled
2. **Verify Files**: Check if JPLEPH exists and is not empty (proves LFS worked)
3. **Detect Errors**: Parse output for LFS quota/error messages
4. **Fallback Only If Needed**: If LFS fails, THEN skip it and use alternative sources
5. **Skip Redundant Downloads**: Each library in [`download-external-libs.sh`](./download-external-libs.sh) checks if files already exist before downloading

**When modifying**:
- Always try LFS first (it's the preferred source)
- Only download from vendors if LFS fails
- Each library must check for existing files before downloading
- Maintain error handling for vendor unavailability
- See [`architecture.md`](./architecture.md) → "Submodule Management" for implementation details

### Why Docker is Non-Negotiable

**Quote from developer**: "remember this must be compatible with the docker. we cant compile C# on a mac"

**Reasoning**:
- Target: linux-arm64 (Raspberry Pi)
- Development: macOS (darwin-arm64/x64)
- Cannot compile/test ARM64 native libraries on macOS
- Cannot use Linux-specific tools (dpkg-deb) on macOS
- Docker provides consistent Linux build environment

**Implication**: All build modifications MUST work inside Docker container.

### Why Stub Libraries Are Acceptable

**Quote from developer**: "creating dummies wont work, the compiling docker must pull the real thing at compile time."

**Clarification**: The developer wanted REAL sources, not dummy/placeholder logic. However, stub .so files are acceptable for optional vendor SDKs that may be unavailable.

**Strategy**:
- Download real libraries when available
- Create minimal .so stubs only for missing optional SDKs
- Log warnings for missing downloads
- Application starts successfully
- Only fails at runtime if specific hardware is accessed

### Build Monitoring Requirements

**Quote from developer**: "you cant just start a build and detach, you must guide it and watch for errors"

**Implication**:
- Always run builds synchronously with full output
- Monitor for errors throughout process
- Don't assume success without verification
- Check for expected artifacts (`.deb` file)
- Use high timeout values (600000ms = 10 minutes)

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    Developer Machine                         │
│                   (macOS/Windows/Linux)                      │
│                                                              │
│  ┌────────────────────────────────────────────────────┐     │
│  │            Docker Container                        │     │
│  │           (Ubuntu Noble ARM64)                     │     │
│  │                                                    │     │
│  │  1. Update submodules (skip LFS)                  │     │
│  │  2. Download external libs from alt sources       │     │
│  │  3. Build System.Windows.Compat                   │     │
│  │  4. dotnet restore → build → publish              │     │
│  │  5. Package as .deb with systemd service          │     │
│  │                                                    │     │
│  │  Output: pins_{version}_arm64_{date}.deb          │     │
│  └────────────────────────────────────────────────────┘     │
└─────────────────────────────────────────────────────────────┘
                            │
                            │ Transfer .deb file
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                    Raspberry Pi                              │
│                   (linux-arm64)                              │
│                                                              │
│  Install: sudo dpkg -i pins_*.deb                           │
│                                                              │
│  ┌────────────────────────────────────────────────────┐     │
│  │  systemd → pins.service                           │     │
│  │    └─> /home/pi/pins/NINA (auto-start)           │     │
│  │         ├─ WPF UI (via compat layer)             │     │
│  │         ├─ Plugin host (Touch-N-Stars, API, etc) │     │
│  │         └─ Native libs (cameras, calculations)    │     │
│  └────────────────────────────────────────────────────┘     │
│                                                              │
│  Access: http://raspberrypi:3000 (Touch-N-Stars web UI)    │
└─────────────────────────────────────────────────────────────┘
```

For complete details, see **[`architecture.md`](./architecture.md)**.

---

## Component Quick Reference

| Component | Purpose | Language | Notes |
|-----------|---------|----------|-------|
| NINA | Main application | C# / WPF | Entry point executable |
| NINA.Core | Business logic | C# | Core functionality |
| NINA.Equipment | Hardware drivers | C# | Camera, mount, focuser, etc |
| NINA.Astrometry | Calculations | C# | Uses NOVAS/SOFA |
| NINA.INDI | Device protocol | C# | INDI client implementation |
| System.Windows.Compat | WPF stub layer | C# | Linux compatibility |
| Touch-N-Stars | Web UI | Vue.js | Plugin (submodule) |
| ninaAPI | REST API | C# | Plugin (submodule) |
| LiveStack | Image stacking | C# | Plugin (submodule) |

---

## Error Patterns & Solutions

### "Could not resolve host: download.zwoastro.com"
**Cause**: Vendor server unavailable or DNS issue
**Solution**: Non-fatal, stub library created
**File**: [`download-external-libs.sh`](./download-external-libs.sh):54-59

### "gzip: stdin: not in gzip format"
**Cause**: Server returning HTML error page instead of archive
**Solution**: Validate with `file` command before extraction
**File**: [`download-external-libs.sh`](./download-external-libs.sh):124

### "cp: cannot stat 'libnovas_c.so': No such file or directory"
**Cause**: NOVAS Makefile creates `libnovas.so.0`, not `libnovas_c.so`
**Solution**: Fallback copy logic
**File**: [`download-external-libs.sh`](./download-external-libs.sh):111-113

### "USE_EMPTY_STUBS: unbound variable"
**Cause**: Variable only set on error, `set -u` treats as error
**Solution**: Use `${VAR:-}` parameter expansion
**File**: [`download-external-libs.sh`](./download-external-libs.sh):175

### "error MSB3030: Could not copy the file"
**Cause**: Missing .so file in External directory
**Solution**: Ensure stub creation logic ran
**File**: Check [`download-external-libs.sh`](./download-external-libs.sh):164-181

---

## Testing Changes

### Local Testing (Recommended)
```bash
# Full Docker build
./docker-build.sh

# Verify output
ls -lh artifacts/*.deb

# Check build completed successfully
echo $?  # Should be 0
```

### Manual Container Testing
```bash
# Build container
docker build -f Dockerfile.build -t pins-builder .

# Interactive shell
docker run --rm -it -v "$(pwd):/build" -w /build pins-builder /bin/bash

# Inside container, run build steps manually
./build-pi-package.sh
```

### Deployment Testing
```bash
# Transfer to Raspberry Pi
scp artifacts/pins_*.deb pi@raspberrypi.local:~

# Install on Pi
ssh pi@raspberrypi.local
sudo dpkg -i pins_*.deb
sudo systemctl status pins.service
sudo journalctl -u pins.service -f
```

---

## Best Practices for Agents

### 1. Always Read Architecture First
Before making changes, read **[`architecture.md`](./architecture.md)** to understand context and dependencies.

### 2. Preserve Error Handling
Build scripts have carefully tuned error handling:
- Optional downloads must not fail build
- Missing libraries get stub replacements
- Errors are logged but non-fatal

### 3. Test in Docker
Never assume changes work without testing in Docker:
```bash
./docker-build.sh  # This is the source of truth
```

### 4. Document Changes
When modifying architecture or build process:
- Update **[`architecture.md`](./architecture.md)**
- Update this file (**`agents.md`**) if agent guidance changes
- Update **[`BUILD.md`](./BUILD.md)** if user-facing changes

### 5. Respect Platform Constraints
- macOS cannot compile C# for Linux (requires Docker)
- Vendor SDKs may be unavailable (use stubs)
- Git LFS quota exceeded (use alternative sources)
- Build must be fully automated (no interactive prompts)

### 6. Monitor Build Output
Always check:
- Build exit code (`echo $?`)
- Expected artifacts exist (`ls artifacts/*.deb`)
- File sizes reasonable (`.deb` should be ~40-50MB)
- SHA256 checksum generated

---

## Quick Command Reference

```bash
# Full Docker build
./docker-build.sh

# Build plugins (optional)
./build-plugins.sh

# Check Docker image exists
docker images | grep pins-builder

# Clean build artifacts
rm -rf artifacts/

# View build logs
docker run --rm -v "$(pwd):/build" -w /build pins-builder \
  /bin/bash -c "./build-pi-package.sh" 2>&1 | tee build.log

# List submodules
git submodule status

# Update submodules without LFS
export GIT_LFS_SKIP_SMUDGE=1
git submodule update --init --recursive --remote
```

---

## Getting Help

1. **Read Architecture**: [`architecture.md`](./architecture.md)
2. **Read Build Instructions**: [`BUILD.md`](./BUILD.md)
3. **Check Git History**: Review recent commits to relevant files
4. **Examine Logs**: Look for error messages in build output
5. **Test in Docker**: Reproduce issues in container environment

---

## Summary

This codebase requires understanding of:
- **Cross-compilation**: macOS → linux-arm64 via Docker
- **Git LFS workaround**: Alternative download sources
- **Native dependencies**: Vendor SDKs and astronomical libraries
- **Debian packaging**: dpkg-deb with systemd integration
- **Plugin architecture**: Modular, extensible design

**Start with [`architecture.md`](./architecture.md)** for comprehensive understanding, then use this guide for specific tasks.
