#!/bin/bash

set -euo pipefail

DEFAULT_SETTINGS_JSON="/etc/transmission/default-settings.json"

if [ "${#}" -gt 0 ]; then
    for arg in "$@"; do
        case "$arg" in
            -h | --help)
                echo "Available Transmission environment variables:"
                echo "[Documentation]: https://github.com/transmission/transmission/blob/${TRANSMISSION_VERSION}/docs/Editing-Configuration-Files.md#options"
                jq -r 'keys[]' "$DEFAULT_SETTINGS_JSON" | awk '{ gsub(/-/, "_"); print "TRANSMISSION_" toupper($0) }'
                exit 0
                ;;
            *)
                echo "Error: Unknown argument '$arg'" >&2
                exit 1
                ;;
        esac
    done
fi

transmission-daemon -f
