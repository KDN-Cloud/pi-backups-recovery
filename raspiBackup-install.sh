#!/usr/bin/env bash
set -euo pipefail

temp_dir=$(mktemp -d)
trap 'rm -rf -- "$temp_dir"' EXIT

curl --fail --show-error --silent --location \
    https://raw.githubusercontent.com/framps/raspiBackup/master/installation/install.sh \
    --output "$temp_dir/install.sh"
sudo bash "$temp_dir/install.sh"
