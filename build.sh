#!/usr/bin/env bash

setup_src() {
    repo init -u https://github.com/LineageOS/android.git -b lineage-18.1 --groups=all,-notdefault,-darwin,-mips --git-lfs --depth=1
    git clone -q https://github.com/rovars/rom "$PWD/rox"
    mkdir -p "$PWD/.repo/local_manifests/"
    cp -r "$PWD/rox/script/lineage-18.1/device.xml" "$PWD/.repo/local_manifests/"

    repo sync -j8 -c --no-clone-bundle --no-tags

    sed -i 's/\$(error SELINUX_IGNORE_NEVERALLOWS/\$(warning SELINUX_IGNORE_NEVERALLOWS/g' system/sepolicy/Android.mk
    patch -p1 < "$PWD/rox/script/permissive.patch"
    source "$PWD/rox/script/constify.sh"

    git clone https://github.com/bimuafaq/android_vendor_extra vendor/extra

    # rm -rf kernel/realme/RMX2185
    # git clone https://github.com/rovars/kernel_realme_RMX2185 kernel/realme/RMX2185 --depth=5
    # cd kernel/realme/RMX2185
    # git revert --no-edit 6d93885db7cd5ba4cfe32f29edd44a967993e566
    # cd -

    # rm -rf device/realme/RMX2185
    # git clone https://github.com/rovars/device_realme_RMX2185 device/realme/RMX2185 --depth=5
}

fix_sepolicy_manual() {
    local _my_dev_path="device/realme/RMX2185"
    local _my_target_file="$_my_dev_path/sepolicy/private/audit2allow.te"
    local _my_error_log="out/error.log"
    local _my_unknown_type

    for i in {1..20}
    do
        echo ">>> Percobaan ke-$i"
        mka selinux_policy
        
        if [[ $? -eq 0 ]]; then
            echo "Build Sukses!"
            return 0
        fi

        if [[ ! -f "$_my_error_log" ]]; then
            return 1
        fi

        _my_unknown_type=$(grep "unknown type" "$_my_error_log" | head -1 | grep -oP "unknown type '\K[^']+")

        if [[ -z "$_my_unknown_type" ]]; then
            _my_unknown_type=$(grep "unknown type" "$_my_error_log" | head -1 | cut -d"'" -f2 | awk '{print $NF}')
        fi

        if [[ -z "$_my_unknown_type" ]]; then
            return 1
        fi

        echo ">>> Fix: $_my_unknown_type"
        sed -i "/$_my_unknown_type/d" "$_my_target_file"

        (
            cd "$_my_dev_path" || exit
            if [[ -n $(git status --porcelain sepolicy/private/audit2allow.te) ]]; then
                git add sepolicy/private/audit2allow.te
                git commit -m "fix: remove unknown type $_my_unknown_type"
                git push
            fi
        )
        
        sleep 2
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
    mka bacon
    # mka selinux_policy
    # fix_sepolicy_manual
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