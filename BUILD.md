# Building PI.N.S. for Raspberry Pi

This document explains how to build PI.N.S. Debian packages for Raspberry Pi.

## Prerequisites

### On Linux
- **.NET 10 SDK** - Download from [dotnet.microsoft.com](https://dotnet.microsoft.com/download)
- **Git** with LFS support
- **dpkg-deb** - Usually pre-installed on Debian/Ubuntu
- **Node.js 20.x** - Optional, only for Touch-N-Stars plugin

### On macOS
**Option A:** Install dependencies locally
```bash
brew install dotnet dpkg
```

**Option B (Recommended):** Use Docker (no local .NET install needed)
- **Docker Desktop** - Download from [docker.com](https://www.docker.com/products/docker-desktop)

### On Windows
- Use **WSL2** with Ubuntu, then follow Linux instructions
- Or use **Docker Desktop** with WSL2 backend

## Quick Start

### On macOS/Windows (Docker Method - Recommended)

```bash
./docker-build.sh
```

This runs the entire build inside a Linux container. No .NET installation needed on your host machine.

### On Linux (or macOS with Homebrew dependencies)

### Build Main Application

```bash
./build-pi-package.sh
```

This will:
1. Update git submodules
2. Restore dependencies
3. Build the application for ARM64
4. Create a Debian package in `artifacts/`
5. Generate SHA256 checksum

**Output:** `artifacts/pins_<version>_arm64_<date>.deb`

### Build Plugins (Optional)

```bash
./build-plugins.sh
```

This builds all available plugins:
- HocusFocus
- LiveStack
- ninaAPI
- PolarAlignment
- Touch-N-Stars

**Output:** Plugin .deb files in `artifacts/plugins/`

## Installing on Raspberry Pi

### 1. Transfer Files

Copy the .deb file(s) to your Raspberry Pi:

```bash
scp artifacts/pins_*.deb pi@raspberrypi.local:~
scp artifacts/plugins/pins-plugin-*.deb pi@raspberrypi.local:~
```

### 2. Install Main Package

```bash
ssh pi@raspberrypi.local
sudo dpkg -i pins_*.deb
```

The service will automatically:
- Install to `/home/pi/pins/`
- Create a systemd service `pins.service`
- Start automatically on boot

### 3. Install Plugins (Optional)

```bash
sudo dpkg -i pins-plugin-*.deb
```

Plugins install to `/home/pi/.local/share/NINA/Plugins/3.0.0/`

### 4. Check Status

```bash
# Check if service is running
sudo systemctl status pins.service

# View logs
sudo journalctl -u pins.service -f

# Restart service
sudo systemctl restart pins.service
```

## Manual Service Control

```bash
# Start service
sudo systemctl start pins.service

# Stop service
sudo systemctl stop pins.service

# Disable auto-start
sudo systemctl disable pins.service

# Enable auto-start
sudo systemctl enable pins.service
```

## Uninstalling

```bash
# Remove main package
sudo dpkg -r pins

# Remove a plugin
sudo dpkg -r pins-plugin-joko
```

## Troubleshooting

### Build fails with "dotnet not found"

Install .NET 10 SDK for your platform:
- Ubuntu: Follow [Microsoft's instructions](https://learn.microsoft.com/en-us/dotnet/core/install/linux-ubuntu)
- macOS: `brew install dotnet@10`

### Submodule update fails

The build script will fall back to pinned commits automatically. If you want to force an update:

```bash
git submodule update --init --recursive --remote --force
```

### Plugin build fails

- Check that the plugin's submodule is properly initialized
- For Touch-N-Stars: Ensure Node.js 20.x and npm are installed
- Check `artifacts/plugin-build-failures.log` for details

### Service won't start on Pi

Check logs and permissions:

```bash
sudo journalctl -u pins.service -n 50
ls -la /home/pi/pins/NINA
```

Ensure the binary is executable:

```bash
chmod +x /home/pi/pins/NINA
```

## Build Artifacts

After successful builds, you'll find:

```
artifacts/
├── pins_<version>_arm64_<date>.deb          # Main package
├── pins_<version>_arm64_<date>.deb.sha256   # Checksum
└── plugins/
    ├── pins-plugin-joko_<version>_arm64_<date>.deb
    ├── pins-plugin-livestack_<version>_arm64_<date>.deb
    ├── pins-plugin-ninaapi_<version>_arm64_<date>.deb
    ├── pins-plugin-polaralignment_<version>_arm64_<date>.deb
    └── pins-plugin-touch-n-stars_<version>_arm64_<date>.deb
```

## Notes

- The build targets **linux-arm64** specifically for Raspberry Pi
- Building on ARM64 is recommended but x64 cross-compilation works
- The GitHub Actions workflow uses these same steps for automated releases
- Version numbers are extracted from `CommonAssemblyInfo.cs`
