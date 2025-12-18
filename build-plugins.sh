#!/bin/bash
set -euo pipefail

# Configuration
BUILD_CONFIGURATION="Release"
DEB_ARCH="arm64"
PLUGINS_INSTALL_BASE="/home/pi/.local/share/NINA/Plugins/3.0.0"
PLUGIN_DEB_BASE="artifacts/plugin-debroot"
PLUGIN_ARTIFACT_DIR="artifacts/plugins"
PLUGIN_MSBUILD_ARGS="-p:DisableImplicitSystemDrawingReference=true"
PLUGIN_FAILURES_FILE="artifacts/plugin-build-failures.log"

echo "=========================================="
echo "PI.N.S. Plugin Package Builder"
echo "=========================================="
echo ""

# Check prerequisites
if ! command -v dotnet >/dev/null 2>&1; then
    echo "ERROR: dotnet CLI not found. Please install .NET 10 SDK" >&2
    exit 1
fi

if ! command -v npm >/dev/null 2>&1; then
    echo "WARNING: npm not found. Touch-N-Stars plugin will fail to build" >&2
fi

# Determine release date
release_date=$(date +%d%m%Y)
echo "Release date: $release_date"

# Prepare workspace
echo ""
echo "Preparing plugin packaging workspace..."
rm -rf "$PLUGIN_DEB_BASE"
mkdir -p "$PLUGIN_ARTIFACT_DIR"
mkdir -p "$(dirname "$PLUGIN_FAILURES_FILE")"
rm -f "$PLUGIN_FAILURES_FILE"

# Function to build a plugin
build_plugin() {
    local project_path="$1"
    local install_folder="$2"
    local deb_package="$3"
    local needs_frontend="${4:-false}"

    echo ""
    echo "=========================================="
    echo "Building plugin: $deb_package"
    echo "=========================================="

    local plugin_dir=$(dirname "$project_path")

    # Get plugin version
    local assembly_info="$plugin_dir/Properties/AssemblyInfo.cs"
    if [ ! -f "$assembly_info" ]; then
        assembly_info=$(find "$plugin_dir" -name AssemblyInfo.cs 2>/dev/null | head -n 1)
    fi

    if [ -z "$assembly_info" ] || [ ! -f "$assembly_info" ]; then
        echo "ERROR: AssemblyInfo.cs not found for $deb_package" >&2
        echo "$deb_package" >> "$PLUGIN_FAILURES_FILE"
        return 1
    fi

    local assembly_version_line=$(grep -E 'AssemblyVersion' "$assembly_info" || true)
    local plugin_version=$(echo "$assembly_version_line" | sed -E 's/.*"([^"]+)".*/\1/')

    if [ -z "$plugin_version" ]; then
        echo "ERROR: AssemblyVersion not found in $assembly_info" >&2
        echo "$deb_package" >> "$PLUGIN_FAILURES_FILE"
        return 1
    fi

    echo "Plugin version: $plugin_version"

    # Build frontend if needed (Touch-N-Stars)
    if [ "$needs_frontend" = "true" ]; then
        echo "Building frontend..."
        local tmp_dir="$plugin_dir/frontend-build"
        rm -rf "$tmp_dir" "$plugin_dir/app"

        if ! command -v npm >/dev/null 2>&1; then
            echo "ERROR: npm required for $deb_package but not found" >&2
            echo "$deb_package" >> "$PLUGIN_FAILURES_FILE"
            return 1
        fi

        GIT_LFS_SKIP_SMUDGE=1 git clone --branch pins --single-branch https://github.com/Touch-N-Stars/Touch-N-Stars.git "$tmp_dir"
        pushd "$tmp_dir" >/dev/null
        npm install
        npm run build
        popd >/dev/null
        mv "$tmp_dir/dist" "$plugin_dir/app"
    fi

    # Build plugin
    echo "Restoring dependencies..."
    dotnet restore "$project_path"

    echo "Building plugin..."
    dotnet build "$project_path" -c "$BUILD_CONFIGURATION" --no-restore $PLUGIN_MSBUILD_ARGS

    # Find build output
    local build_root="$plugin_dir/bin/$BUILD_CONFIGURATION"
    local tfm_dir=$(find "$build_root" -maxdepth 1 -type d -name 'net*' 2>/dev/null | head -n 1)

    if [ -z "$tfm_dir" ]; then
        echo "ERROR: Could not locate target framework output under $build_root" >&2
        echo "$deb_package" >> "$PLUGIN_FAILURES_FILE"
        return 1
    fi

    # Prepare deb structure
    local deb_root="$PLUGIN_DEB_BASE/$deb_package"
    local install_root="$deb_root$PLUGINS_INSTALL_BASE/$install_folder"
    rm -rf "$deb_root"
    mkdir -p "$install_root"

    echo "Staging files..."
    rsync -a "$tfm_dir/" "$install_root/"

    # Copy extra libs if they exist
    local extra_libs="$plugin_dir/extra-libs"
    if [ -d "$extra_libs" ]; then
        find "$extra_libs" -maxdepth 1 -type f -name '*.dll' -exec cp {} "$install_root/" \;
    fi

    # Copy app directory if it exists
    local app_dir="$plugin_dir/app"
    if [ -d "$app_dir" ]; then
        rm -rf "$install_root/app"
        cp -a "$app_dir" "$install_root/app"
    fi

    # Create Debian control file
    local control_dir="$deb_root/DEBIAN"
    mkdir -p "$control_dir"
    local installed_size=$(du -sk "$deb_root$PLUGINS_INSTALL_BASE" | cut -f1)

    cat > "$control_dir/control" <<EOF
Package: $deb_package
Version: $plugin_version
Section: misc
Priority: optional
Architecture: $DEB_ARCH
Maintainer: N.I.N.A. Team
Installed-Size: $installed_size
Description: NINA plugin package for $install_folder
EOF

    # Build deb package
    local deb_path="$PLUGIN_ARTIFACT_DIR/${deb_package}_${plugin_version}_${DEB_ARCH}_${release_date}.deb"
    echo "Creating package: $deb_path"
    dpkg-deb --build "$deb_root" "$deb_path"

    # Generate checksum
    sha256sum "$deb_path" > "$deb_path.sha256"

    echo "SUCCESS: Built $deb_package"
    return 0
}

# Build plugins
echo ""
echo "Building plugins..."

# HocusFocus
build_plugin \
    "NINA.Plugins/joko.nina.plugins/Joko.NINA.Plugins/Joko.NINA.Plugins.HocusFocus/Joko.NINA.Plugins.HocusFocus.csproj" \
    "joko.nina.plugins" \
    "pins-plugin-joko" \
    || true

# LiveStack
build_plugin \
    "NINA.Plugins/LiveStack/nina.plugin.livestack.csproj" \
    "LiveStack" \
    "pins-plugin-livestack" \
    || true

# ninaAPI
build_plugin \
    "NINA.Plugins/ninaAPI/ninaAPI/ninaAPI.csproj" \
    "ninaAPI" \
    "pins-plugin-ninaapi" \
    || true

# PolarAlignment
build_plugin \
    "NINA.Plugins/PolarAlignment/PolarAlignment/NINA.Plugins.PolarAlignment.csproj" \
    "PolarAlignment" \
    "pins-plugin-polaralignment" \
    || true

# Touch-N-Stars (requires frontend build)
build_plugin \
    "NINA.Plugins/Touch-N-Stars/Touch-N-Stars/Touch-N-Stars.csproj" \
    "Touch-N-Stars" \
    "pins-plugin-touch-n-stars" \
    "true" \
    || true

# Summarize results
echo ""
echo "=========================================="
if [ -s "$PLUGIN_FAILURES_FILE" ]; then
    echo "Build completed with failures"
    echo "=========================================="
    echo ""
    echo "The following plugins failed to build:"
    cat "$PLUGIN_FAILURES_FILE"
    echo ""
    echo "Successfully built plugins are in: $PLUGIN_ARTIFACT_DIR"
    exit 1
else
    echo "All plugins built successfully!"
    echo "=========================================="
    echo ""
    echo "Plugin packages are in: $PLUGIN_ARTIFACT_DIR"
    echo ""
    echo "To install on Raspberry Pi:"
    echo "  sudo dpkg -i pins-plugin-*.deb"
fi
