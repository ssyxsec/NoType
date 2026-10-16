#!/bin/bash
set -euo pipefail

# User-invoked setup only. NoType itself never runs this or downloads models.
readonly revision='5359861c739e955e79d9a303bcbc70fb988958b1'
readonly expected='1be3a9b2063867b937e64e2ec7483364a79917e157fa98c5d94b5c1fffea987b'
readonly model_dir="${HOME}/Library/Application Support/NoType/Models"
readonly model_path="${model_dir}/ggml-small.bin"
readonly model_url="https://huggingface.co/ggerganov/whisper.cpp/resolve/${revision}/ggml-small.bin"

if ! command -v brew >/dev/null 2>&1; then
    echo '需要已安装的 Homebrew。本脚本不会安装 Homebrew。' >&2
    exit 1
fi
brew info whisper.cpp
if ! brew list --versions whisper.cpp >/dev/null 2>&1; then
    HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_CLEANUP=1 brew install whisper.cpp
fi
readonly executable="$(brew --prefix whisper.cpp)/bin/whisper-cli"
if [[ ! -x "$executable" ]]; then
    echo "找不到 whisper-cli：$executable" >&2
    exit 1
fi

mkdir -p "$model_dir"
download=''
trap 'if [[ -n "$download" ]]; then rm -f "$download"; fi' EXIT
if [[ ! -f "$model_path" ]] || [[ "$(shasum -a 256 "$model_path" | cut -d ' ' -f 1)" != "$expected" ]]; then
    download="$(mktemp "${model_dir}/.ggml-small.download.XXXXXX")"
    curl --fail --location --retry 3 --connect-timeout 20 "$model_url" --output "$download"
    printf '%s  %s\n' "$expected" "$download" | shasum -a 256 -c -
    mv -f "$download" "$model_path"
    download=''
fi
printf '\nWhisper executable: %s\nModel: %s\nSHA256: %s\n' "$executable" "$model_path" "$expected"
