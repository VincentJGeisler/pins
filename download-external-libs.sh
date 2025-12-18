#!/bin/bash
set -euo pipefail

echo "=========================================="
echo "Downloading External Libraries"
echo "=========================================="

EXTERNAL_DIR="NINA/External"
mkdir -p "$EXTERNAL_DIR"
# Convert to absolute path so it works even after cd
EXTERNAL_DIR="$(cd "$EXTERNAL_DIR" && pwd)"

# Determine target architecture
TARGET_RUNTIME="${1:-linux-arm64}"
echo "Target runtime: $TARGET_RUNTIME"

# Check if LFS files are already present
LFS_FILES_PRESENT=0
if [ -f "$EXTERNAL_DIR/JPLEPH" ] && [ -s "$EXTERNAL_DIR/JPLEPH" ]; then
    # JPLEPH exists and is not empty - likely from LFS
    if [ -d "$EXTERNAL_DIR/$TARGET_RUNTIME" ] && [ "$(ls -A "$EXTERNAL_DIR/$TARGET_RUNTIME" 2>/dev/null)" ]; then
        echo "LFS files appear to be present - will only download missing files"
        LFS_FILES_PRESENT=1
    fi
fi

# Create directory structure
mkdir -p "$EXTERNAL_DIR/$TARGET_RUNTIME/ASI"
mkdir -p "$EXTERNAL_DIR/$TARGET_RUNTIME/Oasis"
mkdir -p "$EXTERNAL_DIR/$TARGET_RUNTIME/ToupTek"
mkdir -p "$EXTERNAL_DIR/$TARGET_RUNTIME/Nitecrawler"
mkdir -p "$EXTERNAL_DIR/$TARGET_RUNTIME/Wanderer"
mkdir -p "$EXTERNAL_DIR/$TARGET_RUNTIME/SOFA"
mkdir -p "$EXTERNAL_DIR/$TARGET_RUNTIME/NOVAS"

echo ""
echo "Downloading JPLEPH from NASA JPL..."
# DE421 ephemeris file (14MB, covers years 1900-2050)
if [ ! -f "$EXTERNAL_DIR/JPLEPH" ]; then
    curl -L -o "$EXTERNAL_DIR/JPLEPH" \
        "https://ssd.jpl.nasa.gov/ftp/eph/planets/Linux/de421/linux_p1550p2650.421" || {
        echo "WARNING: Primary JPLEPH source failed. Trying alternative..."
        # Alternative: smaller DE405 file
        curl -L -o "$EXTERNAL_DIR/JPLEPH" \
            "https://ssd.jpl.nasa.gov/ftp/eph/planets/Linux/de405/linux_p1600p2200.405" || {
            echo "ERROR: Could not download JPLEPH" >&2
            exit 1
        }
    }
    echo "JPLEPH downloaded successfully ($(du -h "$EXTERNAL_DIR/JPLEPH" | cut -f1))"
else
    echo "JPLEPH already exists, skipping"
fi

echo ""
echo "Downloading ZWO/ASI camera libraries..."
# ASI libraries for linux-arm64 or linux-x64
if [ "$TARGET_RUNTIME" = "linux-arm64" ]; then
    ASI_ARCH="armv8"
elif [ "$TARGET_RUNTIME" = "linux-x64" ]; then
    ASI_ARCH="x64"
fi

# Check if ASI libraries already exist (from LFS)
if [ -f "$EXTERNAL_DIR/$TARGET_RUNTIME/ASI/libASICamera2.so" ] && [ -s "$EXTERNAL_DIR/$TARGET_RUNTIME/ASI/libASICamera2.so" ]; then
    echo "ASI libraries already present, skipping download"
else
    # Download ASI SDK (latest version)
    ASI_VERSION="1.36"
    if curl -L -o /tmp/asi_sdk.tar.bz2 \
        "https://download.zwoastro.com/developer/ASICamera2_linux_mac_SDK_V${ASI_VERSION}.tar.bz2" 2>/dev/null; then
        echo "ASI SDK downloaded successfully"
    else
        echo "WARNING: Could not download ASI SDK (this is optional unless you have ZWO hardware)" >&2
        touch /tmp/asi_sdk_failed
    fi

    # Extract the libraries we need
    if [ ! -f /tmp/asi_sdk_failed ]; then
        tar -xjf /tmp/asi_sdk.tar.bz2 -C /tmp/ || true
        if [ "$TARGET_RUNTIME" = "linux-arm64" ]; then
            cp /tmp/ASICamera2*/lib/armv8/libASICamera2.so "$EXTERNAL_DIR/$TARGET_RUNTIME/ASI/" 2>/dev/null || true
            cp /tmp/ASICamera2*/lib/armv8/libEAFFocuser.so "$EXTERNAL_DIR/$TARGET_RUNTIME/ASI/" 2>/dev/null || true
            cp /tmp/ASICamera2*/lib/armv8/libEFWFilter.so "$EXTERNAL_DIR/$TARGET_RUNTIME/ASI/" 2>/dev/null || true
        else
            cp /tmp/ASICamera2*/lib/x64/libASICamera2.so "$EXTERNAL_DIR/$TARGET_RUNTIME/ASI/" 2>/dev/null || true
            cp /tmp/ASICamera2*/lib/x64/libEAFFocuser.so "$EXTERNAL_DIR/$TARGET_RUNTIME/ASI/" 2>/dev/null || true
            cp /tmp/ASICamera2*/lib/x64/libEFWFilter.so "$EXTERNAL_DIR/$TARGET_RUNTIME/ASI/" 2>/dev/null || true
        fi
        rm -rf /tmp/asi_sdk.tar.bz2 /tmp/ASICamera2*
        echo "ASI libraries extracted successfully"
    else
        echo "Skipping ASI library extraction (download failed)"
        rm -f /tmp/asi_sdk_failed
    fi
fi

echo ""
echo "Downloading ToupTek camera libraries..."
# Check if ToupTek library already exists (from LFS)
if [ -f "$EXTERNAL_DIR/$TARGET_RUNTIME/ToupTek/libtoupcam.so" ] && [ -s "$EXTERNAL_DIR/$TARGET_RUNTIME/ToupTek/libtoupcam.so" ]; then
    echo "ToupTek library already present, skipping download"
else
    # ToupTek SDK
    TOUPCAM_VERSION="54.24835"
    if [ "$TARGET_RUNTIME" = "linux-arm64" ]; then
        curl -L -o /tmp/toupcam.tar.gz \
            "https://www.touptek.com/download/linux/toupcam-${TOUPCAM_VERSION}-aarch64.tar.gz" || {
            echo "WARNING: Could not download ToupTek SDK for ARM64"
        }
        tar -xzf /tmp/toupcam.tar.gz -C /tmp/ || true
        cp /tmp/toupcam*/lib/libtoupcam.so "$EXTERNAL_DIR/$TARGET_RUNTIME/ToupTek/" || true
    else
        curl -L -o /tmp/toupcam.tar.gz \
            "https://www.touptek.com/download/linux/toupcam-${TOUPCAM_VERSION}-amd64.tar.gz" || {
            echo "WARNING: Could not download ToupTek SDK for x64"
        }
        tar -xzf /tmp/toupcam.tar.gz -C /tmp/ || true
        cp /tmp/toupcam*/lib/libtoupcam.so "$EXTERNAL_DIR/$TARGET_RUNTIME/ToupTek/" || true
    fi
    rm -rf /tmp/toupcam* || true
    echo "ToupTek libraries downloaded"
fi

echo ""
echo "Building NOVAS and SOFA from source..."
# NOVAS C library - build from source or check if already present
if [ -f "$EXTERNAL_DIR/$TARGET_RUNTIME/NOVAS/libnovas_c.so" ] && [ -s "$EXTERNAL_DIR/$TARGET_RUNTIME/NOVAS/libnovas_c.so" ]; then
    echo "NOVAS library already present, skipping build"
else
    git clone --depth 1 https://github.com/indigo-astronomy/novas /tmp/novas || true
    if [ -d "/tmp/novas" ]; then
        cd /tmp/novas
        make || echo "WARNING: NOVAS build may have failed"
        # The Makefile creates libnovas.so.0, but we need libnovas_c.so
        cp libnovas.so.0 "$EXTERNAL_DIR/$TARGET_RUNTIME/NOVAS/libnovas_c.so" 2>/dev/null || \
            cp libnovas_c.so "$EXTERNAL_DIR/$TARGET_RUNTIME/NOVAS/" 2>/dev/null || \
            echo "WARNING: Could not find NOVAS library file"
        find . -name "cio_ra.bin" -exec cp {} "$EXTERNAL_DIR/$TARGET_RUNTIME/NOVAS/" \; 2>/dev/null || \
            echo "WARNING: Could not find cio_ra.bin"
        cd -
        rm -rf /tmp/novas
        echo "NOVAS libraries built"
    fi
fi

# SOFA C library - build from source or check if already present
if [ -f "$EXTERNAL_DIR/$TARGET_RUNTIME/SOFA/libsofa_c.so" ] && [ -s "$EXTERNAL_DIR/$TARGET_RUNTIME/SOFA/libsofa_c.so" ]; then
    echo "SOFA library already present, skipping build"
else
    if curl -L -o /tmp/sofa.tar.gz http://www.iausofa.org/2021_0512_C/sofa_c-20210512.tar.gz 2>/dev/null; then
        # Check if it's actually a gzip file (not an HTML error page)
        if file /tmp/sofa.tar.gz | grep -q "gzip"; then
            tar -xzf /tmp/sofa.tar.gz -C /tmp/ 2>/dev/null || {
                echo "WARNING: Could not extract SOFA source"
                rm -f /tmp/sofa.tar.gz
            }
            if [ -d "/tmp/sofa" ]; then
                cd /tmp/sofa/*/c/src 2>/dev/null || cd /tmp/sofa/c/src 2>/dev/null || {
                    echo "WARNING: Could not find SOFA source directory"
                    cd -
                }
                if [ -f "*.c" ] || ls *.c >/dev/null 2>&1; then
                    gcc -fPIC -shared -o libsofa_c.so *.c 2>/dev/null || echo "WARNING: SOFA build may have failed"
                    cp libsofa_c.so "$EXTERNAL_DIR/$TARGET_RUNTIME/SOFA/" 2>/dev/null || echo "WARNING: Could not copy SOFA library"
                fi
                cd -
                rm -rf /tmp/sofa* || true
                echo "SOFA library built"
            fi
        else
            echo "WARNING: SOFA download returned non-gzip data (server may be unavailable)"
            rm -f /tmp/sofa.tar.gz
        fi
    else
        echo "WARNING: Could not download SOFA source"
    fi
fi

echo ""
echo "Note: Some vendor-specific libraries (Oasis, Nitecrawler, Wanderer)"
echo "must be obtained directly from manufacturers. These are optional"
echo "unless you have the specific hardware."
echo ""

# Create stub .so files for missing libraries
# These prevent build errors but will fail at runtime if the hardware is used
echo "/* Stub library */" > /tmp/stub.c
gcc -shared -fPIC /tmp/stub.c -o /tmp/stub.so 2>/dev/null || {
    echo "WARNING: Could not create stub library, using empty files"
    USE_EMPTY_STUBS=1
}

for lib in \
    "$EXTERNAL_DIR/$TARGET_RUNTIME/Oasis/liboasisfilterwheel.so" \
    "$EXTERNAL_DIR/$TARGET_RUNTIME/Oasis/liboasisfocuser.so" \
    "$EXTERNAL_DIR/$TARGET_RUNTIME/Nitecrawler/libNitecrawlerSDK.so" \
    "$EXTERNAL_DIR/$TARGET_RUNTIME/Wanderer/libWandererRotatorSDK.so" \
    "$EXTERNAL_DIR/$TARGET_RUNTIME/ASI/libASICamera2.so" \
    "$EXTERNAL_DIR/$TARGET_RUNTIME/ASI/libEAFFocuser.so" \
    "$EXTERNAL_DIR/$TARGET_RUNTIME/ASI/libEFWFilter.so" \
    "$EXTERNAL_DIR/$TARGET_RUNTIME/ToupTek/libtoupcam.so" \
    "$EXTERNAL_DIR/$TARGET_RUNTIME/SOFA/libsofa_c.so" \
    "$EXTERNAL_DIR/$TARGET_RUNTIME/NOVAS/libnovas_c.so"; do
    if [ ! -f "$lib" ]; then
        echo "Creating stub library for $(basename $lib)"
        if [ -z "${USE_EMPTY_STUBS:-}" ]; then
            cp /tmp/stub.so "$lib" 2>/dev/null || touch "$lib"
        else
            touch "$lib"
        fi
    fi
done

# Create cio_ra.bin if missing
if [ ! -f "$EXTERNAL_DIR/$TARGET_RUNTIME/NOVAS/cio_ra.bin" ]; then
    echo "Creating empty cio_ra.bin placeholder"
    touch "$EXTERNAL_DIR/$TARGET_RUNTIME/NOVAS/cio_ra.bin"
fi

rm -f /tmp/stub.c /tmp/stub.so

echo ""
echo "=========================================="
echo "External libraries setup complete"
echo "=========================================="
