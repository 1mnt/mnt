#!/usr/bin/env bash

set -ex

release_file=$(find out/target/product -name "*-RMX*.zip" -print -quit)
release_name=$(basename "$release_file" .zip)
release_tag=$(date +%Y%m%d)
repo_releases="bimuafaq/releases"
UPLOAD_GH=false

if [[ -f "$release_file" ]]; then
    if [[ "${UPLOAD_GH}" == "true" && -n "$GITHUB_TOKEN" ]]; then
        echo "$GITHUB_TOKEN" | gh auth login --with-token
        rovx --post "Uploading to GitHub Releases..."
        gh release create "$release_tag" -t "$release_name" -R "$repo_releases" -F "rovx/script/notes.txt" || true
        
        if gh release upload "$release_tag" "$release_file" -R "$repo_releases" --clobber; then
            rovx --post "GitHub Release upload successful: <a href='https://github.com/$repo_releases/releases/tag/$release_tag'>$release_name</a>"
        else
            rovx --post "GitHub Release upload failed"
        fi
    fi

    mkdir -p ~/.config
    unzip -q rox/config.zip -d ~/.config
    rovx --post "Uploading build result to Telegram..."

    if timeout 15m telegram-upload "$release_file" --to "$TG_CHAT_ID" --caption "$CIRRUS_COMMIT_MESSAGE"; then
        rovx --post "Telegram upload successful"
    else
        rovx --post "telegram-upload failed"
        exit 1
    fi
else
    rovx --post "Build file not found"
    exit 0
fi