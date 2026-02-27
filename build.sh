#!/usr/bin/env bash

setup_src() {
    repo init -u https://github.com/LineageOS/android.git -b lineage-18.1 --groups=all,-notdefault,-darwin,-mips --git-lfs --depth=1
    git clone -q https://github.com/rovars/rom "$PWD/rox"
    mkdir -p "$PWD/.repo/local_manifests/"
    cp -r "$PWD/rox/script/lineage-18.1/device.xml" "$PWD/.repo/local_manifests/"

    repo sync -j8 -c --no-clone-bundle --no-tags

    cp "$PWD/rox/script/ca/f82fe8ed.0" "$PWD/system/ca-certificates/files/"

    sed -i 's/\$(error SELINUX_IGNORE_NEVERALLOWS/\$(warning SELINUX_IGNORE_NEVERALLOWS/g' system/sepolicy/Android.mk
    patch -p1 < "$PWD/rox/script/permissive.patch"
    source "$PWD/rox/script/constify.sh"

    git clone https://github.com/bimuafaq/android_vendor_extra vendor/extra

    # rm -rf kernel/realme/RMX2185
    # git clone https://github.com/rovars/kernel_realme_RMX2185 kernel/realme/RMX2185 --depth=5
    # cd kernel/realme/RMX2185
    # git revert --no-edit 6d93885db7cd5ba4cfe32f29edd44a967993e566
    # cd -
}

fix_sepolicy_local() {
    local _my_dev_path="device/realme/RMX2185"
    local _my_target_file="$_my_dev_path/sepolicy/private/audit2allow.te"
    local _my_build_log
    local _my_err_line

    for i in {1..10}
    do
        _my_build_log=$(mka selinux_policy 2>&1)
        
        if [[ $? -eq 0 ]]; then
            break
        fi

        _my_err_line=$(echo "$_my_build_log" | grep -oP "$_my_target_file:\K[0-9]+")

        if [[ -z "$_my_err_line" ]]; then
            break
        fi

        sed -i "${_my_err_line}d" "$_my_target_file"

        cd "$_my_dev_path"
        git add sepolicy/private/audit2allow.te
        git commit -m "fix: remove unknown type line $_my_err_line"
        git push
        cd -
    done
}

build_src() {
    source "$PWD/build/envsetup.sh"
    source rovx --ccache

    export OWN_KEYS_DIR="$PWD/rox/keys"
    sudo ln -sf "$OWN_KEYS_DIR/releasekey.pk8" "$OWN_KEYS_DIR/testkey.pk8"
    sudo ln -sf "$OWN_KEYS_DIR/releasekey.x509.pem" "$OWN_KEYS_DIR/testkey.x509.pem"

    lunch lineage_RMX2185-user
    # source "$PWD/rox/script/mmm.sh" icons
    fix_sepolicy_local

}

upload_build() {
    local release_file=$(find "$PWD/out/target/product/RMX2185" -maxdepth 1 -name "*-RMX*.zip" -print -quit)
    local release_name=$(basename "$release_file" .zip)
    local release_tag=$(date +%Y%m%d)
    local repo_releases="bimuafaq/releases"
    local UPLOAD_GH=false

    if [[ -n "$release_file" && -f "$release_file" ]]; then
        if [[ "${UPLOAD_GH}" == "true" && -n "$GITHUB_TOKEN" ]]; then
            echo "$GITHUB_TOKEN" > rox.txt
            gh auth login --with-token < rox.txt
            rovx --post "Uploading to GitHub Releases..."
            gh release create "$release_tag" -t "$release_name" -R "$repo_releases" -F "$PWD/rox/script/notes.txt" || true

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