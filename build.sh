#!/bin/bash

set -x

setup_sync() {
    git clone -q https://chromium.googlesource.com/chromium/tools/depot_tools.git "$PWD/depot_tools"
    export PATH="$PWD/depot_tools:$PATH"

    VANADIUM_TAG=$(git ls-remote --tags --sort="v:refname" https://github.com/GrapheneOS/Vanadium.git | tail -n1 | sed 's/.*\///; s/\^{}//')
    echo "$VANADIUM_TAG" > "$PWD/vanadium_tag.txt"
    CHROMIUM_VERSION=$(echo "$VANADIUM_TAG" | cut -d'.' -f1-4)

    git clone -q --depth=1 -b "$VANADIUM_TAG" https://github.com/GrapheneOS/Vanadium.git "$PWD/Vanadium"
    git clone -q https://github.com/rovars/rom "$PWD/rom"
    
    fetch --nohooks --no-history android || true

    cd src
    ./build/install-build-deps.sh --android --no-prompt &>/dev/null
    git fetch --depth=1 origin "refs/tags/$CHROMIUM_VERSION:refs/tags/$CHROMIUM_VERSION"
    git checkout "$CHROMIUM_VERSION"
    git am --whitespace=nowarn --keep-non-patch "$PWD/../Vanadium/patches/"*.patch
    gclient sync -D --no-history --shallow --jobs 8
}

build_src() {
    export PATH="$PWD/depot_tools:$PATH"
    source rovx --ccache
    
    # Linux-specific Chromium optimizations for ccache
    export CCACHE_CPP2=yes
    export CCACHE_SLOPPINESS=include_file_mtime,time_macros
    export CCACHE_BASEDIR="$PWD"

    cd src
    rm -rf out/Default && mkdir -p out/Default
    cp "$PWD/../Vanadium/args.gn" out/Default/args.gn

    CERT_DIGEST="c6adb8b83c6d4c17d292afde56fd488a51d316ff8f2c11c5410223bff8a7dbb3"
    keytool -export-cert -alias rov -keystore "$PWD/../rom/script/rov.keystore" -storepass rovars | sha256sum | cut -d' ' -f1 > cert_digest.txt || echo "$CERT_DIGEST" > cert_digest.txt
    CERT_DIGEST=$(cat cert_digest.txt)

    sed -i "s/trichrome_certdigest = .*/trichrome_certdigest = \"$CERT_DIGEST\"/" out/Default/args.gn
    sed -i "s/config_apk_certdigest = .*/config_apk_certdigest = \"$CERT_DIGEST\"/" out/Default/args.gn
    sed -i "s/symbol_level = 1/symbol_level = 0/" out/Default/args.gn

    cat <<EOF >> out/Default/args.gn
ccache_prefix = "ccache"
blink_symbol_level = 0
v8_symbol_level = 0
EOF

    gn gen out/Default
    ccache -z
    timeout 60m autoninja -C out/Default chrome_public_apk || true
    ccache -s
}

upload_build() {
    VANADIUM_TAG=$(cat "$PWD/vanadium_tag.txt" || echo "unknown")
    
    mkdir -p ~/.config
    [ -f "$PWD/rom/config.zip" ] && unzip -q "$PWD/rom/config.zip" -d ~/.config

    APK_FILE=$(find "$PWD/src/out/Default/apks" -name "ChromePublic.apk" | head -n 1)
    
    if [ -f "$APK_FILE" ]; then
        APKSIGNER=$(find "$PWD/src/third_party/android_sdk/public/build-tools" -name apksigner -type f | head -n 1)
        
        "$APKSIGNER" sign --ks "$PWD/rom/script/rov.keystore" --ks-pass pass:rovars --ks-key-alias rov --in "$APK_FILE" --out "$PWD/Signed-ChromePublic.apk" || cp "$APK_FILE" "$PWD/Signed-ChromePublic.apk"
        
        ARCHIVE_NAME="Vanadium-${VANADIUM_TAG}-arm64-$(date +%Y%m%d).tar.gz"
        tar -czf "$PWD/$ARCHIVE_NAME" -C "$PWD" Signed-ChromePublic.apk
        
        rovx --post "$PWD/$ARCHIVE_NAME" "Build successful: $ARCHIVE_NAME"
        telegram-upload "$PWD/$ARCHIVE_NAME" --to "$TG_CHAT_ID" || true
    else
        rovx --post "Build failed: APK not found."
    fi
}

case "$1" in
    --sync) setup_sync ;;
    --build) build_src ;;
    --upload) upload_build ;;
    *) echo "Unknown: $1"; exit 1 ;;
esac
