# PI.N.S. Architecture Documentation

## Table of Contents
- [Overview](#overview)
- [Why Docker Build](#why-docker-build)
- [Project Architecture](#project-architecture)
- [Build Process](#build-process)
- [External Dependencies](#external-dependencies)
- [Cross-Platform Considerations](#cross-platform-considerations)
- [Deployment Architecture](#deployment-architecture)

---

## Overview

**PI.N.S. (PI 'N' Stars)** is a Linux port of N.I.N.A. (Nighttime Imaging 'N' Astronomy), designed to run on Raspberry Pi for affordable astrophotography. The project consists of:

- **Core Application**: .NET 10 C# application with WPF UI
- **Plugin System**: Modular architecture supporting multiple plugins
- **External Native Libraries**: Camera SDKs and astronomical calculation libraries
- **Web Interface**: Touch-N-Stars web-based control interface

**Target Platform**: Raspberry Pi (linux-arm64 / aarch64)
**Development Platform**: macOS, Linux, or Windows
**Build Method**: Cross-compilation using Docker

---

## Why Docker Build

### Cross-Compilation Challenge

PI.N.S. targets **linux-arm64** (Raspberry Pi), but developers typically work on **macOS (darwin-arm64/x64)** or **Windows (win-x64)**. This presents several challenges:

1. **.NET Cross-Compilation**: While .NET supports cross-compilation, native library dependencies complicate this
2. **Native Library Compatibility**: Cannot compile or test ARM64 native libraries on macOS/Windows
3. **System Dependencies**: Linux-specific tools (dpkg-deb, systemd) unavailable on other platforms
4. **Vendor SDKs**: Camera manufacturer SDKs are Linux-specific binaries

### Docker Solution

Docker provides a **consistent Linux build environment** regardless of host platform:

```
┌─────────────────────────────────────────────────────┐
│  Host: macOS / Windows / Linux                      │
│  ┌────────────────────────────────────────────┐     │
│  │  Docker Container: Ubuntu Noble (ARM64)    │     │
│  │                                             │     │
│  │  • .NET 10 SDK (linux-arm64)              │     │
│  │  • GCC/Make (native lib compilation)       │     │
│  │  • dpkg-deb (Debian packaging)             │     │
│  │  • Git/curl/wget (dependency fetching)     │     │
│  │                                             │     │
│  │  Volume Mount: /build → Project Directory  │     │
│  └────────────────────────────────────────────┘     │
└─────────────────────────────────────────────────────┘
```

**Benefits:**
- No local .NET installation required on host
- Reproducible builds across all platforms
- Access to Linux-specific build tools
- Isolated build environment prevents conflicts

**Usage:**
```bash
./docker-build.sh  # One command builds everything
```

---

## Project Architecture

### Component Structure

```
pins/
├── NINA/                          # Main application
│   ├── NINA.csproj               # Entry point executable
│   └── External/                 # Native libraries (Git LFS, now alt-sourced)
│
├── NINA.Core/                    # Core business logic
├── NINA.Equipment/               # Hardware drivers (cameras, mounts, etc)
├── NINA.Astrometry/              # Astronomical calculations
├── NINA.Image/                   # Image processing
├── NINA.INDI/                    # INDI device protocol support
├── NINA.Platesolving/            # Plate solving algorithms
├── NINA.Profile/                 # User profile management
├── NINA.Sequencer/               # Imaging sequence automation
├── NINA.WPF.Base/                # WPF UI framework
├── NINA.Plugin/                  # Plugin infrastructure
│
├── System.Windows.Compat/        # WPF → Linux compatibility layer
│
├── NINA.Plugins/                 # Plugin submodules
│   ├── Touch-N-Stars/           # Web UI plugin (Vue.js)
│   ├── ninaAPI/                 # REST API plugin
│   ├── LiveStack/               # Live stacking plugin
│   ├── PolarAlignment/          # Polar alignment assistant
│   └── joko.nina.plugins/       # HocusFocus autofocus plugin
│
├── packaging/                    # Debian packaging metadata
│   ├── debian/                  # postinst, prerm scripts
│   └── systemd/                 # pins.service unit file
│
├── build-pi-package.sh          # Main build orchestrator
├── download-external-libs.sh    # External library fetcher
└── docker-build.sh              # Docker build wrapper
```

### Dependency Graph

```
┌─────────────────────────────────────────────────────────────┐
│                         NINA (Main)                         │
│                    (WPF Application)                        │
└───────────────┬─────────────────────────────────────────────┘
                │
    ┌───────────┼───────────┬──────────────┬─────────────┐
    │           │           │              │             │
    ▼           ▼           ▼              ▼             ▼
┌─────────┐ ┌─────────┐ ┌──────────┐ ┌─────────┐ ┌──────────┐
│  Core   │ │Equipment│ │Astrometry│ │  Image  │ │Sequencer │
└────┬────┘ └────┬────┘ └────┬─────┘ └────┬────┘ └────┬─────┘
     │           │           │             │           │
     │           ▼           ▼             ▼           │
     │      ┌────────┐  ┌─────────┐   ┌───────┐      │
     │      │  INDI  │  │  NOVAS  │   │LibRaw │      │
     │      └────────┘  │  SOFA   │   └───────┘      │
     │                  └─────────┘                   │
     │                                                 │
     └─────────────────────┬───────────────────────────┘
                           ▼
                    ┌─────────────┐
                    │WPF.Base +   │
                    │Compat Layer │
                    └─────────────┘
                           │
                           ▼
                    ┌─────────────┐
                    │   Plugins   │
                    │(Touch-N-Stars│
                    │ ninaAPI, etc)│
                    └─────────────┘
```

### Plugin Architecture

PI.N.S. uses a **modular plugin system** where plugins can extend functionality:

- **Plugin Interface**: Defined in `NINA.Plugin/`
- **Plugin Discovery**: Scans `~/.local/share/NINA/Plugins/3.0.0/`
- **Plugin Types**:
  - Equipment drivers (cameras, focusers, filter wheels)
  - Imaging utilities (autofocus, alignment)
  - User interfaces (web control, API)
  - Image processing (stacking, analysis)

**Plugin Lifecycle:**
1. Built separately via `build-plugins.sh`
2. Packaged as individual .deb files
3. Installed to plugin directory
4. Discovered and loaded at runtime by main application

---

## Build Process

### High-Level Build Flow

```
┌─────────────────────────────────────────────────────────────┐
│ 1. docker-build.sh                                          │
│    └─> Builds Docker image with build tools                │
│    └─> Mounts project directory                            │
│    └─> Executes build-pi-package.sh inside container       │
└─────────────────────────┬───────────────────────────────────┘
                          │
┌─────────────────────────▼───────────────────────────────────┐
│ 2. build-pi-package.sh                                      │
│    ┌──────────────────────────────────────────────────┐    │
│    │ 2a. Update Git Submodules                        │    │
│    │     • Skip LFS files (GIT_LFS_SKIP_SMUDGE=1)    │    │
│    │     • Pull plugin submodules                     │    │
│    └──────────────────────────────────────────────────┘    │
│    ┌──────────────────────────────────────────────────┐    │
│    │ 2b. download-external-libs.sh                    │    │
│    │     • JPLEPH from NASA JPL                       │    │
│    │     • ASI SDK from ZWO (optional)                │    │
│    │     • ToupTek SDK from vendor (optional)         │    │
│    │     • Build NOVAS from source                    │    │
│    │     • Build SOFA from source                     │    │
│    │     • Create stub .so files for missing libs     │    │
│    └──────────────────────────────────────────────────┘    │
│    ┌──────────────────────────────────────────────────┐    │
│    │ 2c. Build System.Windows.Compat                  │    │
│    │     • Custom WPF compatibility layer             │    │
│    └──────────────────────────────────────────────────┘    │
│    ┌──────────────────────────────────────────────────┐    │
│    │ 2d. dotnet restore                               │    │
│    │     • Restore NuGet packages                     │    │
│    │     • Resolve project dependencies               │    │
│    └──────────────────────────────────────────────────┘    │
│    ┌──────────────────────────────────────────────────┐    │
│    │ 2e. dotnet build                                 │    │
│    │     • Compile all NINA.* projects                │    │
│    │     • Target: linux-arm64, Release config        │    │
│    └──────────────────────────────────────────────────┘    │
│    ┌──────────────────────────────────────────────────┐    │
│    │ 2f. dotnet publish                               │    │
│    │     • Create self-contained deployment           │    │
│    │     • Output: artifacts/publish/linux-arm64/     │    │
│    └──────────────────────────────────────────────────┘    │
│    ┌──────────────────────────────────────────────────┐    │
│    │ 2g. Package as .deb                              │    │
│    │     • Stage files to /home/pi/pins layout        │    │
│    │     • Add systemd service file                   │    │
│    │     • Add Debian maintainer scripts              │    │
│    │     • Run dpkg-deb --build                       │    │
│    │     • Generate SHA256 checksum                   │    │
│    └──────────────────────────────────────────────────┘    │
└─────────────────────────┬───────────────────────────────────┘
                          │
┌─────────────────────────▼───────────────────────────────────┐
│ 3. Output                                                   │
│    artifacts/pins_3.3.0.1000-nightly_arm64_18122025.deb    │
│    artifacts/pins_3.3.0.1000-nightly_arm64_18122025.deb.sha256 │
└─────────────────────────────────────────────────────────────┘
```

### Detailed Build Steps

#### 1. Docker Environment Setup

**File**: `Dockerfile.build`

Creates Ubuntu Noble-based container with:
- .NET 10 SDK
- Build tools (gcc, make, git, curl, wget, tar, bzip2, file)
- Packaging tools (dpkg-dev, rsync)
- Node.js (for Touch-N-Stars plugin)

#### 2. Submodule Management

**Challenge**: Git LFS quota may be exceeded on GitHub (140MB of binary files)

**Solution**: Intelligent LFS fallback strategy:
1. **Try LFS First**: Attempt normal submodule update with LFS enabled
2. **Verify Download**: Check if JPLEPH exists and is not empty
3. **Detect Failures**: Parse output for LFS quota/error messages
4. **Fallback**: Only if LFS fails, skip it and use alternative sources

```bash
# First attempt with LFS
if git submodule update --init --recursive --remote 2>&1 | tee /tmp/submodule_update.log; then
    if [ -f "NINA/External/JPLEPH" ] && [ -s "NINA/External/JPLEPH" ]; then
        echo "LFS files downloaded successfully"
    else
        USE_ALT_SOURCES=1  # LFS files missing, use alternatives
    fi
else
    if grep -qi "quota\|lfs.*error" /tmp/submodule_update.log; then
        USE_ALT_SOURCES=1  # LFS quota exceeded, use alternatives
    fi
fi

# Only download from alternative sources if LFS failed
if [ "$USE_ALT_SOURCES" -eq 1 ]; then
    export GIT_LFS_SKIP_SMUDGE=1
    git submodule update --init --recursive --remote
    ./download-external-libs.sh "$TARGET_RUNTIME"
fi
```

This ensures we use official LFS sources when available and only fall back to vendor downloads when necessary.

#### 3. External Library Acquisition

**File**: `download-external-libs.sh`

Downloads native dependencies from alternative sources **only if not already present from LFS**. Each library checks for existing files before downloading:

**JPLEPH (14MB)**: NASA JPL ephemeris data
- Source: `https://ssd.jpl.nasa.gov/ftp/eph/planets/`
- Purpose: Planetary position calculations
- Required by: NINA.Astrometry

**ZWO/ASI SDK (Optional)**: Camera drivers
- Source: `https://download.zwoastro.com/developer/`
- Purpose: ZWO camera support
- Libraries: libASICamera2.so, libEAFFocuser.so, libEFWFilter.so

**ToupTek SDK (Optional)**: Camera drivers
- Source: `https://www.touptek.com/download/linux/`
- Purpose: ToupTek camera support
- Library: libtoupcam.so

**NOVAS (Built from Source)**: Astronomical calculations
- Source: `https://github.com/indigo-astronomy/novas`
- Build: `make` → `libnovas.so.0`
- Purpose: Star positions, precession, nutation

**SOFA (Built from Source)**: Astronomical algorithms
- Source: `http://www.iausofa.org/`
- Build: `gcc -shared *.c -o libsofa_c.so`
- Purpose: IAU SOFA C library

**Stub Libraries**: For missing optional SDKs
- Created as minimal .so files to satisfy build requirements
- Will fail at runtime only if corresponding hardware is used

**Error Handling**:
- All vendor SDK downloads are non-fatal
- Missing libraries replaced with stub .so files
- Absolute paths used to support directory changes during build

#### 4. System.Windows.Compat Build

**Challenge**: WPF (Windows Presentation Foundation) is Windows-only

**Solution**: Custom compatibility layer in `System.Windows.Compat/`
- Provides stub implementations of System.Windows types
- Allows code compilation without full WPF support
- Built first and copied over .NET's System.Windows.dll

#### 5. .NET Build & Publish

**Restore Dependencies**:
```bash
dotnet restore NINA/NINA.csproj -r linux-arm64
```

**Build Application**:
```bash
dotnet build NINA/NINA.csproj -c Release -r linux-arm64
```

**Publish Self-Contained Deployment**:
```bash
dotnet publish NINA/NINA.csproj -c Release -r linux-arm64 \
  -o artifacts/publish/linux-arm64
```

Output includes:
- NINA executable
- All .NET runtime libraries
- Project assemblies
- Native dependencies
- Configuration files

#### 6. Debian Package Creation

**Layout**: `/home/pi/pins/`
```
/home/pi/pins/
├── NINA                    # Main executable
├── *.dll                   # .NET assemblies
├── External/              # Native libraries
│   └── linux-arm64/
│       ├── ASI/
│       ├── ToupTek/
│       ├── NOVAS/
│       ├── SOFA/
│       └── JPLEPH
└── Resources/             # UI resources
```

**Systemd Service**: `/etc/systemd/system/pins.service`
```ini
[Unit]
Description=PI.N.S. Astrophotography Application
After=network.target

[Service]
Type=simple
User=pi
WorkingDirectory=/home/pi/pins
ExecStart=/home/pi/pins/NINA
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

**Maintainer Scripts**:
- `postinst`: Enable and start systemd service
- `prerm`: Stop and disable service before removal

**Package Metadata**: `DEBIAN/control`
```
Package: pins
Version: 3.3.0.1000-nightly
Architecture: arm64
Maintainer: N.I.N.A. Team
Description: Pins build for Raspberry Pi
```

**Build Package**:
```bash
dpkg-deb --build debroot/ artifacts/pins_<version>_arm64_<date>.deb
sha256sum artifacts/*.deb > artifacts/*.deb.sha256
```

---

## External Dependencies

### Required Libraries

| Library | Purpose | Source | Build Method |
|---------|---------|--------|--------------|
| JPLEPH | Planetary ephemeris | NASA JPL | Download binary |
| libnovas_c.so | Astronomical calculations | GitHub | Build from source |
| libsofa_c.so | IAU SOFA algorithms | IAU | Build from source |

### Optional Libraries (Hardware-Specific)

| Library | Purpose | Hardware | Fallback |
|---------|---------|----------|----------|
| libASICamera2.so | ZWO camera driver | ZWO ASI cameras | Stub .so |
| libEAFFocuser.so | ZWO focuser driver | ZWO EAF | Stub .so |
| libtoupcam.so | ToupTek camera driver | ToupTek cameras | Stub .so |
| liboasisfilterwheel.so | Oasis filter wheel | Oasis hardware | Stub .so |
| libNitecrawlerSDK.so | Nitecrawler driver | Nitecrawler hardware | Stub .so |
| libWandererRotatorSDK.so | Wanderer rotator | Wanderer hardware | Stub .so |

**Stub Library Strategy**:
- Allows build to complete without all vendor SDKs
- Application starts successfully
- Only fails at runtime if specific hardware is accessed
- User installs real drivers only for their hardware

### Dependency Resolution Flow

```
┌────────────────────────────────────────────────────────────┐
│ download-external-libs.sh                                  │
│                                                            │
│ For each library:                                          │
│   1. Try download from vendor                              │
│   2. If success: Extract and copy                          │
│   3. If fail: Log warning                                  │
│                                                            │
│ After all downloads:                                       │
│   For each missing library:                                │
│     Create stub .so file                                   │
│                                                            │
│ Result: Build always succeeds                              │
└────────────────────────────────────────────────────────────┘
```

---

## Cross-Platform Considerations

### Platform-Specific Challenges

#### macOS Host
- **Issue**: Cannot run ARM64 Linux binaries
- **Solution**: Docker provides Linux environment
- **Limitation**: No dpkg-dev natively
- **Workaround**: All packaging happens in Docker

#### Windows Host
- **Issue**: Different path separators, no bash
- **Solution**: WSL2 + Docker or Docker Desktop
- **Limitation**: Line ending conversions (CRLF vs LF)
- **Workaround**: Git configured with `autocrlf=input`

#### Linux Host
- **Advantage**: Can build natively without Docker
- **Option 1**: Use Docker for consistency
- **Option 2**: Install dependencies locally with `build-pi-package.sh`

### Architecture Differences

```
Development:             Target:
macOS (darwin-arm64)  →  Raspberry Pi (linux-arm64)
macOS (darwin-x64)    →  Raspberry Pi (linux-arm64)
Windows (win-x64)     →  Raspberry Pi (linux-arm64)
Linux (linux-x64)     →  Raspberry Pi (linux-arm64)
```

**.NET Runtime Identifiers (RID)**:
- Build: `linux-arm64` (always)
- Self-contained: Includes .NET runtime
- No .NET installation required on Raspberry Pi

---

## Deployment Architecture

### Installation Layout

```
Raspberry Pi Filesystem:

/home/pi/pins/                    # Application directory
├── NINA                          # Main executable (chmod +x)
├── *.dll                         # .NET assemblies
├── External/linux-arm64/         # Native libraries
├── Resources/                    # UI resources
└── .install_path                 # Installation metadata

/home/pi/.local/share/NINA/       # User data
├── Plugins/3.0.0/               # Plugin directory
│   ├── Touch-N-Stars/
│   ├── ninaAPI/
│   └── ...
├── Profiles/                     # User profiles
└── Logs/                         # Application logs

/etc/systemd/system/              # System service
└── pins.service                  # Systemd unit file
```

### Runtime Architecture

```
┌────────────────────────────────────────────────────────────┐
│ Raspberry Pi OS (Debian-based, ARM64)                      │
│                                                            │
│  ┌──────────────────────────────────────────────────┐     │
│  │ systemd                                          │     │
│  │   └─> pins.service (auto-start)                 │     │
│  │         └─> /home/pi/pins/NINA                   │     │
│  └──────────────────────────────────────────────────┘     │
│                                                            │
│  ┌──────────────────────────────────────────────────┐     │
│  │ NINA Process                                     │     │
│  │  ├─ WPF UI (via compatibility layer)            │     │
│  │  ├─ INDI Client (astronomy devices)             │     │
│  │  ├─ Plugin Host (loads plugins)                 │     │
│  │  └─ Native Libraries (cameras, calculations)    │     │
│  └──────────────────────────────────────────────────┘     │
│                                                            │
│  ┌──────────────────────────────────────────────────┐     │
│  │ Loaded Plugins                                   │     │
│  │  ├─ Touch-N-Stars (web UI on port 3000)        │     │
│  │  ├─ ninaAPI (REST API on port 5555)            │     │
│  │  ├─ LiveStack (image stacking)                  │     │
│  │  ├─ PolarAlignment (alignment assistant)        │     │
│  │  └─ HocusFocus (autofocus)                      │     │
│  └──────────────────────────────────────────────────┘     │
│                                                            │
│  ┌──────────────────────────────────────────────────┐     │
│  │ External Devices (via INDI/native drivers)      │     │
│  │  ├─ Cameras (ASI, ToupTek, etc.)               │     │
│  │  ├─ Telescope Mounts                            │     │
│  │  ├─ Filter Wheels                                │     │
│  │  ├─ Focusers                                     │     │
│  │  └─ Rotators                                     │     │
│  └──────────────────────────────────────────────────┘     │
│                                                            │
│  ┌──────────────────────────────────────────────────┐     │
│  │ User Access                                      │     │
│  │  ├─ Web Browser → http://raspberrypi:3000      │     │
│  │  ├─ REST API → http://raspberrypi:5555         │     │
│  │  └─ SSH → systemctl status pins.service         │     │
│  └──────────────────────────────────────────────────┘     │
└────────────────────────────────────────────────────────────┘
```

### Monitoring & Management

**Service Status**:
```bash
sudo systemctl status pins.service    # Check status
sudo journalctl -u pins.service -f    # Live logs
sudo systemctl restart pins.service   # Restart
```

**Resource Usage**:
```bash
top                                   # CPU/memory usage
df -h /home/pi/pins                   # Disk usage
```

**Plugin Management**:
- Plugins installed via separate .deb packages
- Discovered automatically in `~/.local/share/NINA/Plugins/3.0.0/`
- Loaded at runtime by plugin host

---

## Summary

PI.N.S. architecture prioritizes:

1. **Portability**: Docker-based builds work on any platform
2. **Modularity**: Plugin system for extensibility
3. **Resilience**: Graceful handling of missing optional dependencies
4. **Automation**: Systemd service for reliable operation
5. **Accessibility**: Web UI for remote control

The build process transforms platform-specific source code into a self-contained ARM64 Debian package, deployable on Raspberry Pi with a single `dpkg -i` command.
