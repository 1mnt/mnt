#!/usr/bin/env bash

setup_src() {
    repo init -u https://github.com/LineageOS/android.git -b lineage-18.1 --groups=all,-notdefault,-darwin,-mips --git-lfs --depth=1
    git clone -q https://github.com/rovars/rom "$PWD/rox"
    mkdir -p "$PWD/.repo/local_manifests/"
    cp -r "$PWD/rox/script/lineage-18.1/"*.xml "$PWD/.repo/local_manifests/"
    repo sync -j8 -c --no-clone-bundle --no-tags
    patch -p1 < "$PWD/rox/script/permissive.patch"
    source "$PWD/rox/script/constify.sh"
}

build_src() {
    source "$PWD/build/envsetup.sh"
    source rovx --ccache

    export OWN_KEYS_DIR="$PWD/rox/keys"
    sudo ln -sf "$OWN_KEYS_DIR/releasekey.pk8" "$OWN_KEYS_DIR/testkey.pk8"
    sudo ln -sf "$OWN_KEYS_DIR/releasekey.x509.pem" "$OWN_KEYS_DIR/testkey.x509.pem"

    lunch lineage_RMX2185-user
    # source "$PWD/rox/script/mmm.sh" icons
    m bacon -j$(nproc --all)
}

upload_build() {
    local release_file=$(find "$PWD/out/target/product/RMX2185" -maxdepth 1 -name "*-RMX*.zip" -print -quit)
    local release_name=$(basename "$release_file" .zip)
    local release_tag=$(date +%Y%m%d)
    local repo_releases="bimuafaq/releases"
    local UPLOAD_GH=false

    if [[ -n "$release_file" && -f "$release_file" ]]; then
        if [[ "${UPLOAD_GH}" == "true" && -n "$GITHUB_TOKEN" ]]; then
            echo "$GITHUB_TOKEN" | gh auth login --with-token
            rovx --post "Uploading to GitHub Releases..."
            gh release create "$release_tag" -t "$release_name" -R "$repo_releases" -F "$PWD/rovx/script/notes.txt" || true

            if gh release upload "$release_tag" "$release_file" -R "$repo_releases" --clobber; then
                rovx --post "GitHub Release upload successful: <a href='https://github.com/$repo_releases/releases/tag/$release_tag'>$release_name</a>"
            else
                rovx --post "GitHub Release upload failed"
            fi
        fi

        mkdir -p ~/.config
        unzip -q "$PWD/rox/config.zip" -d ~/.config
        rovx --post "Uploading build result to Telegram..."
        timeout 15m telegram-upload "$release_file" --to "$TG_CHAT_ID" --caption "$CIRRUS_COMMIT_MESSAGE"
    else
        rovx --post "Build file not found for upload"
        exit 0
    fi
}

case "$1" in
    --sync) setup_src ;;
    --build) build_src ;;
    --upload) upload_build ;;
    *) echo "Unknown: $1"; exit 1 ;;
esac