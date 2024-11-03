#!/bin/bash

set -euo pipefail

DEFAULT_SETTINGS_JSON="/etc/transmission/default-settings.json"
SENSITIVE_SETTINGS=("rpc-password")
TRANSMISSION_HOME=${TRANSMISSION_HOME:-"/config"}
TRANSMISSION_LOG_FILE=${TRANSMISSION_LOG_FILE:-"/dev/stdout"}
SETTINGS_FILE="$TRANSMISSION_HOME/settings.json"

mkdir -p "$TRANSMISSION_HOME"

## Some utility function
err_exit() { echo "[ERROR] - $*" >&2 && exit 1; }
string_contains() { case $1 in *$2*) return 0 ;; *) return 1 ;; esac }
is_number() { case $1 in '' | *[!0-9]*) return 1 ;; *) return 0 ;; esac }

if [ "${#}" -gt 0 ]; then
    for arg in "$@"; do
        case "$arg" in
            -h | --help)
                echo "Custom variables:"
                echo "TRANSMISSION_HOME: sets where transmission's config lives (default: '/config')."
                echo "Available Transmission environment variables:"
                echo "[Documentation]: https://github.com/transmission/transmission/blob/${TRANSMISSION_VERSION}/docs/Editing-Configuration-Files.md#options"
                jq -r 'keys[]' "$DEFAULT_SETTINGS_JSON" | awk '{ gsub(/-/, "_"); print "TRANSMISSION_" toupper($0) }'
                exit 0
                ;;
            *)
                err_exit "Error: Unknown argument '$arg'"
                ;;
        esac
    done
fi

if ! test -f "$SETTINGS_FILE"; then
    generate_jq_argument() {
        settings_key="$1"
        value="$2"

        type=$(jq -r ".\"$settings_key\" | type" "$DEFAULT_SETTINGS_JSON")
        case "$type" in
            boolean)
                if string_contains "true false" "$value"; then
                    echo "{ \"$settings_key\": $value }"
                    return
                fi
                ;;
            number)
                if is_number "$value"; then
                    echo "{ \"$settings_key\": $value }"
                    return
                fi
                ;;
            string)
                echo "{ \"$settings_key\": \"$value\" }"
                return
                ;;
            *)
                err_exit "Unsupported type '$type' for setting '$settings_key'."
                ;;
        esac

        err_exit "Invalid value '$value' for '$settings_key' of type: '$type'."
    }

    custom_settings="{}"
    ## Handle interpolation of provided variables with settings.json
    for settings_key in $(jq -r 'keys[]' "$DEFAULT_SETTINGS_JSON"); do
        env=$(echo "$settings_key" | awk '{ gsub(/-/, "_"); print "TRANSMISSION_" toupper($0) }')

        ## If no env variable of that name we skip
        test -n "${!env+x}" || continue

        value=$(printenv "$env")

        custom_settings=$(echo "$custom_settings" | jq ". + $(generate_jq_argument "$settings_key" "$value")")

        [[ " ${SENSITIVE_SETTINGS[*]} " =~ $settings_key ]] && value='[REDACTED]'
        echo "[ENV] Set '$settings_key' to new value of '$value'."
    done

    jq ". + $custom_settings " $DEFAULT_SETTINGS_JSON > "$SETTINGS_FILE"
fi

transmission-daemon \
    --foreground \
    --config-dir "$TRANSMISSION_HOME" \
    --logfile "$TRANSMISSION_LOG_FILE"
