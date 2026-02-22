#!/bin/bash

set -e

setup_src() {
    repo init -u https://github.com/LineageOS/android.git -b lineage-18.1 --groups=all,-notdefault,-darwin,-mips --git-lfs --depth=1
    git clone -q https://github.com/rovars/rom rox
    mkdir -p .repo/local_manifests/
    cp -r rox/script/lineage-18.1/*.xml .repo/local_manifests/
    repo sync -j8 -c --no-clone-bundle --no-tags
    patch -p1 < $PWD/rox/script/permissive.patch
    source $PWD/rox/script/constify.sh
}

build_src() {
    source build/envsetup.sh
    source rovx --env

    export KBUILD_BUILD_USER=nobody
    export KBUILD_BUILD_HOST=android-build
    export BUILD_USERNAME=nobody
    export BUILD_HOSTNAME=android-build

    export OWN_KEYS_DIR="$PWD/rox/keys"
    sudo ln -sf "$OWN_KEYS_DIR/releasekey.pk8" "$OWN_KEYS_DIR/testkey.pk8"
    sudo ln -sf "$OWN_KEYS_DIR/releasekey.x509.pem" "$OWN_KEYS_DIR/testkey.x509.pem"

    lunch lineage_RMX2185-user
    mka bacon
}


main() {
    case "${1:-}" in
        -s|--sync)
            setup_src
            ;;
        -b|--build)
            build_src
            ;;
        *)
            echo "Usage: ./build.sh [FLAGS]"
            echo "Options:"
            echo "  -s, --sync      Sync source"
            echo "  -b, --build     Start build process"
            return 1
            ;;
    esac
}

main "$@"
