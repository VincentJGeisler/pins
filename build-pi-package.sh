#!/bin/bash
set -euo pipefail

# Configuration
BUILD_CONFIGURATION="Release"
TARGET_RUNTIME="linux-arm64"
INSTALL_DIRECTORY="/home/pi/pins"
PUBLISH_DIRECTORY="artifacts/publish"
PACKAGE_ROOT="artifacts/package"
DEB_ROOT="artifacts/debroot"
DEB_PACKAGE="pins"
DEB_ARCH="arm64"

echo "=========================================="
echo "PI.N.S. Raspberry Pi Package Builder"
echo "=========================================="
echo ""

# Check prerequisites
echo "Checking prerequisites..."
if ! command -v dotnet >/dev/null 2>&1; then
    echo "ERROR: dotnet CLI not found. Please install .NET 10 SDK" >&2
    exit 1
fi

dotnet_version=$(dotnet --version)
echo "Found .NET version: $dotnet_version"

# Update submodules - try with LFS first, fall back to alternative sources if needed
echo ""
echo "Updating submodules..."
USE_ALT_SOURCES=0

# First attempt: Try normal submodule update with LFS
if git submodule update --init --recursive --remote 2>&1 | tee /tmp/submodule_update.log; then
    # Check if LFS files were actually downloaded
    if [ -f "NINA/External/JPLEPH" ] && [ -s "NINA/External/JPLEPH" ]; then
        echo "Submodules updated successfully with LFS files"
    else
        echo "LFS files missing - will use alternative sources"
        USE_ALT_SOURCES=1
    fi
else
    # Check if failure was due to LFS quota
    if grep -qi "quota\|lfs.*error\|lfs.*fail" /tmp/submodule_update.log 2>/dev/null; then
        echo "LFS quota or download issue detected - falling back to alternative sources"
        USE_ALT_SOURCES=1
    else
        echo "Remote submodule update failed; trying pinned commits" >&2
        git submodule update --init --recursive
    fi
fi
rm -f /tmp/submodule_update.log

# If LFS failed, update submodules without LFS and use alternative sources
if [ "$USE_ALT_SOURCES" -eq 1 ]; then
    echo "Updating submodules without LFS files..."
    export GIT_LFS_SKIP_SMUDGE=1
    git submodule update --init --recursive --remote 2>/dev/null || git submodule update --init --recursive
    unset GIT_LFS_SKIP_SMUDGE
fi

# Always run download script to ensure all required files exist
# (creates stubs for missing optional libraries even if LFS succeeded)
echo ""
echo "Checking for missing external libraries..."
./download-external-libs.sh "$TARGET_RUNTIME"

# Restore dependencies
echo ""
echo "Restoring dependencies for $TARGET_RUNTIME..."
dotnet restore NINA/NINA.csproj -r "$TARGET_RUNTIME"
dotnet restore System.Windows.Compat/System.Windows.Compat.csproj

# Build System.Windows.Compat
echo ""
echo "Building System.Windows.Compat..."
dotnet build System.Windows.Compat/System.Windows.Compat.csproj -c "$BUILD_CONFIGURATION" --no-restore

# Build main application
echo ""
echo "Building NINA for $TARGET_RUNTIME..."
dotnet build NINA/NINA.csproj -c "$BUILD_CONFIGURATION" -r "$TARGET_RUNTIME" --no-restore

# Publish binaries
echo ""
echo "Publishing binaries..."
dotnet publish NINA/NINA.csproj -c "$BUILD_CONFIGURATION" -r "$TARGET_RUNTIME" --no-build -o "$PUBLISH_DIRECTORY/$TARGET_RUNTIME"

# Determine package version
echo ""
echo "Determining package version..."
version=$(grep -m1 'AssemblyInformationalVersion' CommonAssemblyInfo.cs | sed -E 's/.*"([^"]+)".*/\1/')
if [ -z "$version" ]; then
    echo "ERROR: Failed to determine version from CommonAssemblyInfo.cs" >&2
    exit 1
fi
echo "Package version: $version"

# Determine release date
release_date=$(date +%d%m%Y)
echo "Release date: $release_date"

# Stage /home/pi/pins layout
echo ""
echo "Staging package layout..."
publish_root="$PUBLISH_DIRECTORY/$TARGET_RUNTIME"
rm -rf "$PACKAGE_ROOT"
mkdir -p "$PACKAGE_ROOT/pins"
rsync -a "$publish_root/" "$PACKAGE_ROOT/pins/"
echo "$INSTALL_DIRECTORY" > "$PACKAGE_ROOT/pins/.install_path"

# Replace System.Windows.dll with compat version
echo ""
echo "Replacing System.Windows.dll with compat version..."
compat_dll="System.Windows.Compat/bin/$BUILD_CONFIGURATION/net10.0/System.Windows.dll"
target_dir="$PACKAGE_ROOT/pins"
if [ ! -f "$compat_dll" ]; then
    echo "ERROR: Compat build missing at $compat_dll" >&2
    exit 1
fi
cp -f "$compat_dll" "$target_dir/System.Windows.dll"

# Prepare Debian filesystem
echo ""
echo "Preparing Debian filesystem..."
install_root="$DEB_ROOT/home/pi/pins"
rm -rf "$DEB_ROOT"
mkdir -p "$install_root"
rsync -a "$PACKAGE_ROOT/pins/" "$install_root/"

# Add systemd service
echo ""
echo "Adding systemd service..."
service_path="$DEB_ROOT/etc/systemd/system/pins.service"
service_dir="$(dirname "$service_path")"
mkdir -p "$service_dir"
cp packaging/systemd/pins.service "$service_path"
chmod 644 "$service_path"

# Add Debian maintainer scripts
echo ""
echo "Adding Debian maintainer scripts..."
control_dir="$DEB_ROOT/DEBIAN"
mkdir -p "$control_dir"
cp packaging/debian/postinst "$control_dir/postinst"
cp packaging/debian/prerm "$control_dir/prerm"
chmod 755 "$control_dir/postinst" "$control_dir/prerm"

# Build Debian package
echo ""
echo "Building Debian package..."
installed_size=$(du -sk "$DEB_ROOT/home/pi/pins" | cut -f1)
cat > "$control_dir/control" <<EOF
Package: $DEB_PACKAGE
Version: $version
Section: misc
Priority: optional
Architecture: $DEB_ARCH
Maintainer: N.I.N.A. Team
Installed-Size: $installed_size
Description: Pins build for Raspberry Pi
EOF

deb_filename="${DEB_PACKAGE}_${version}_${DEB_ARCH}_${release_date}.deb"
dpkg-deb --build "$DEB_ROOT" "artifacts/$deb_filename"

# Generate SHA256 checksum
echo ""
echo "Generating SHA256 checksum..."
sha256sum "artifacts/$deb_filename" > "artifacts/$deb_filename.sha256"

# Success message
echo ""
echo "=========================================="
echo "Build completed successfully!"
echo "=========================================="
echo ""
echo "Output files:"
echo "  - artifacts/$deb_filename"
echo "  - artifacts/$deb_filename.sha256"
echo ""
echo "To install on Raspberry Pi:"
echo "  1. Copy the .deb file to your Raspberry Pi"
echo "  2. Run: sudo dpkg -i $deb_filename"
echo "  3. The service will start automatically"
echo ""
echo "To check service status:"
echo "  sudo systemctl status pins.service"
echo ""
