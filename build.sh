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
    if [[ ! -d "reclient" ]]; then
        git clone -q https://github.com/rovars/reclient
    fi

    unset USE_CCACHE CCACHE_EXEC USE_GOMA
    unset RBE_use_rpc_credentials
    unset RBE_service_no_auth

    export CCACHE_DIR="/tmp/ccache"

    export USE_RBE="1"
    export RBE_DIR="$PWD/reclient"
    export RBE_exec_root="$PWD"

    export RBE_CXX_EXEC_STRATEGY="remote"
    export RBE_JAVAC_EXEC_STRATEGY="remote"
    export RBE_R8_EXEC_STRATEGY="remote"
    export RBE_D8_EXEC_STRATEGY="remote"

    export RBE_JAVAC="1"
    export RBE_R8="1"
    export RBE_D8="1"

    export RBE_use_unified_cas_ops="true"
    export RBE_use_unified_downloads="true"
    export RBE_use_unified_uploads="true"

    export RBE_use_application_default_credentials="false"
    export RBE_use_gce_credentials="false"

    export RBE_instance="rovx.buildbuddy.io"
    export RBE_service="grpcs://rovx.buildbuddy.io:443"
    export RBE_remote_headers="$ROVBE"

    local rbex_logs="/tmp/rbelogs"
    mkdir -p "$rbex_logs"
    export RBE_log_dir="$rbex_logs"
    export RBE_output_dir="$rbex_logs"
    export RBE_proxy_log_dir="$rbex_logs"

    export OWN_KEYS_DIR="$PWD/rox/keys"
    sudo ln -sf "$OWN_KEYS_DIR/releasekey.pk8" "$OWN_KEYS_DIR/testkey.pk8"
    sudo ln -sf "$OWN_KEYS_DIR/releasekey.x509.pem" "$OWN_KEYS_DIR/testkey.x509.pem"

    source build/envsetup.sh
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
