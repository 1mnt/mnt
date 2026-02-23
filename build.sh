#!/bin/bash

setup_src() {
    repo init -u https://github.com/LineageOS/android.git -b lineage-18.1 --groups=all,-notdefault,-darwin,-mips --git-lfs --depth=1
    git clone -q https://github.com/rovars/rom "$PWD/rox"


    echo "xx" > xxxx.txt
    local release_file=$PWD/xxx*.txt

    mkdir -p ~/.config
    unzip -q "$PWD/rox/config.zip" -d ~/.config
    rovx --post "Uploading build result to Telegram..."
   timeout 15m telegram-upload "$release_file" --to "$TG_CHAT_ID" --caption "$CIRRUS_COMMIT_MESSAGE"
    echo anu && exit 1

    mkdir -p "$PWD/.repo/local_manifests/"
    cp -r "$PWD/rox/script/lineage-18.1/"*.xml "$PWD/.repo/local_manifests/"
    repo sync -j8 -c --no-clone-bundle --no-tags
    patch -p1 < "$PWD/rox/script/permissive.patch"
    source "$PWD/rox/script/constify.sh"
}

build_src() {
    source "$PWD/build/envsetup.sh"
    source rovx --env

    export OWN_KEYS_DIR="$PWD/rox/keys"
    sudo ln -sf "$OWN_KEYS_DIR/releasekey.pk8" "$OWN_KEYS_DIR/testkey.pk8"
    sudo ln -sf "$OWN_KEYS_DIR/releasekey.x509.pem" "$OWN_KEYS_DIR/testkey.x509.pem"

    lunch lineage_RMX2185-user
    source "$PWD/rox/script/mmm.sh" systemui || exit 1
    # mka bacon
}

upload_rom() {
    local release_file=$(find "$PWD/out/target/product" -name "*-RMX*.zip" -print -quit)
    local release_name=$(basename "$release_file" .zip)
    local release_tag=$(date +%Y%m%d)
    local repo_releases="bimuafaq/releases"
    local UPLOAD_GH=false

    if [[ -f "$release_file" ]]; then
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
    else
        rovx --post "Build file not found"
        exit 0
    fi
}

upload_tele() {
    local ROOT_DIR="$PWD"
    cd "$ROOT_DIR/out/target/product/RMX2185"
    mkdir -p ~/.config
    unzip -q "$ROOT_DIR/rox/config.zip" -d ~/.config
    rovx --post "Uploading build result to Telegram..."
    timeout 15m telegram-upload *-RMX*.zip --to "$TG_CHAT_ID" --caption "$CIRRUS_COMMIT_MESSAGE"
}

main() {
    case "${1:-}" in
        -s|--sync)
            setup_src
            ;;
        -b|--build)
            build_src
            ;;
        -u|--upload)
            upload_rom
            ;;
        -t|--tele)
            upload_tele
            ;;
        *)
            echo "Usage: ./build.sh [FLAGS]"
            echo "Options:"
            echo "  -s, --sync      Sync source"
            echo "  -b, --build     Start build process"
            echo "  -u, --upload    Upload build to GitHub"
            echo "  -t, --tele      Upload build to Telegram"
            return 1
            ;;
    esac
}

main "$@"