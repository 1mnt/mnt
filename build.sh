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
    if [[ ! -d "reclient" ]]; then
        git clone -q https://github.com/rovars/reclient
    fi

    cat > "$PWD/reclient_helper.sh" << 'EOF'
#!/bin/bash
apikey="${RBE_API_KEY}"
expiry=$(date +'%a %b %d %H:%M:%S %Z %Y' --date '+6 hours')
echo "{ \"headers\": { \"x-buildbuddy-api-key\": \"$apikey\" }, \"expiry\": \"$expiry\" }"
EOF
    chmod +x "$PWD/reclient_helper.sh"

    export ANDROID_BUILD_ENVIRONMENT_CONFIG="buildbuddy_rbe"
    export ANDROID_BUILD_ENVIRONMENT_CONFIG_DIR="build/soong/docs"
    export RBE_service="rovx.buildbuddy.io:443"
    export RBE_instance="default"
    export RBE_automatic_auth="false"
    export RBE_use_gce_credentials="false"
    export RBE_use_application_default_credentials="false"
    export RBE_use_rpc_credentials="true"
    export RBE_credentials_helper="$PWD/reclient_helper.sh"
    export RBE_cas_concurrency="100"
    export RBE_use_unified_cas_ops="true"
    export RBE_use_unified_downloads="true"
    export RBE_use_unified_uploads="true"
    export RBE_use_batches="true"
    export RBE_cas_rpc_timeout="10m"
    export RBE_compression_threshold="100"
    export RBE_noremote_upload_local_results="true"
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

    local rbex_logs="/tmp/rbelogs"
    mkdir -p "$rbex_logs"
    export RBE_log_dir="$rbex_logs"
    export RBE_output_dir="$rbex_logs"
    export RBE_proxy_log_dir="$rbex_logs"

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
