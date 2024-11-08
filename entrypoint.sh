#!/bin/sh

set \
    -o errexit \
    -o notify \
    -o nounset

DEFAULT_SETTINGS_JSON="/etc/transmission/default-settings.json"
TRANSMISSION_HOME=${TRANSMISSION_HOME:-"/config"}
TRANSMISSION_LOG_FILE=${TRANSMISSION_LOG_FILE:-"/dev/stdout"}
TRANSMISSION_LOG_LEVEL=${TRANSMISSION_LOG_LEVEL:-"info"}
SETTINGS_FILE="$TRANSMISSION_HOME/settings.json"
# Define the sensitive keys as a space-separated string
SENSITIVE_SETTINGS="rpc-password"

mkdir -p "$TRANSMISSION_HOME"

## Some utility function
err_exit() { echo "[ERROR] - $*" >&2 && exit 1; }
string_contains() { case $1 in *$2*) return 0 ;; *) return 1 ;; esac }
is_number() { case $1 in '' | *[!0-9]*) return 1 ;; *) return 0 ;; esac }

if [ "${#}" -gt 0 ]; then
    for arg in "$@"; do
        case "$arg" in
            -h | --help)
                echo "To see current config: '--show-config'."
                echo "Custom variables:"
                echo "TRANSMISSION_LOG_LEVEL: 'critical', 'error', 'warn', 'info', 'debug' or 'trace' (default: info)."
                echo "TRANSMISSION_WEB_HOME: sets where transmission's custom web-ui lives (default if UI is set: '/etc/transmission/web')."
                echo "TRANSMISSION_WEB_UI: optional - if set the container will download the selected ui to TRANSMISSION_WEB_HOME path. Options: 'combustion', 'kettu', 'transmission-web-control', 'flood', 'shift' or 'transmissionic'."
                echo "TRANSMISSION_HOME: sets where transmission's config lives (default: '/config')."
                echo "Available Transmission environment variables:"
                echo "[Documentation]: https://github.com/transmission/transmission/blob/${TRANSMISSION_VERSION}/docs/Editing-Configuration-Files.md#options"
                jq -r '[keys[]] | join(" ")' "$DEFAULT_SETTINGS_JSON" | awk '{ gsub(/-/, "_"); print "TRANSMISSION_" toupper($0) }'
                exit 0
                ;;
            --show-config)
                if test -f "$SETTINGS_FILE"; then
                    jq < "$SETTINGS_FILE"
                else
                    jq < "$DEFAULT_SETTINGS_JSON"
                fi
                exit 0
                ;;
            *)
                err_exit "Error: Unknown argument '$arg'"
                ;;
        esac
    done
fi

if ! string_contains "critical error warn info debug trace" "$TRANSMISSION_LOG_LEVEL"; then
    err_exit "Invalid log-level, should be 'critical', 'error', 'warn', 'info', 'debug' or 'trace'."
fi

if
    test -n "${TRANSMISSION_WEB_UI+x}" \
        && {
            export TRANSMISSION_WEB_HOME="${TRANSMISSION_WEB_HOME:-"/etc/transmission/web"}"
            mkdir -p "$TRANSMISSION_WEB_HOME"
            ! [ "$(ls -A "$TRANSMISSION_WEB_HOME")" ]
        }
then
    case "$TRANSMISSION_WEB_UI" in
        combustion)
            echo "Installing combustion UI !"
            wget -O- https://github.com/Secretmapper/combustion/archive/release.tar.gz \
                | tar xz --strip-components=1 -C "$TRANSMISSION_WEB_HOME"
            ;;
        flood)
            echo "Installing flood UI !"
            wget -O- https://github.com/johman10/flood-for-transmission/releases/download/latest/flood-for-transmission.tar.gz \
                | tar xz --strip-components=1 -C "$TRANSMISSION_WEB_HOME"
            cp "$TRANSMISSION_WEB_HOME"/config.json.defaults "$TRANSMISSION_WEB_HOME"/config.json
            ;;
        kettu)
            echo "Installing kettu UI !"
            wget -O- https://github.com/endor/kettu/archive/master.tar.gz \
                | tar xz --strip-components=1 -C "$TRANSMISSION_WEB_HOME"
            cp "$TRANSMISSION_WEB_HOME"/config/locations.js.example "$TRANSMISSION_WEB_HOME"/config/locations.js
            ;;
        shift)
            echo "Installing shift UI !"
            wget -O- https://github.com/killemov/Shift/archive/master.tar.gz \
                | tar xz --strip-components=1 -C "$TRANSMISSION_WEB_HOME"
            ;;
        transmissionic)
            echo "Installing transmissionic UI !"
            wget -O- https://github.com/6c65726f79/Transmissionic/releases/download/v1.8.0/Transmissionic-webui-v1.8.0.zip \
                | unzip -q -d "$TRANSMISSION_WEB_HOME" -
            mv "$TRANSMISSION_WEB_HOME/web"/* "$TRANSMISSION_WEB_HOME"
            rmdir "$TRANSMISSION_WEB_HOME/web"
            touch "$TRANSMISSION_WEB_HOME"/default.json
            ;;
        transmission-web-control)
            echo "Installing transmission-web-control UI !"
            wget -O- https://github.com/ronggang/transmission-web-control/archive/refs/heads/master.tar.gz \
                | tar xz --strip-components=2 -C "$TRANSMISSION_WEB_HOME"
            ;;
        *)
            err_exit "Unsupported ui name, should be 'combustion', 'kettu', 'transmission-web-control', 'flood', 'shift' or 'transmissionic'."
            ;;
    esac
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
        printenv "$env" > /dev/null 2>&1 || continue

        value=$(printenv "$env")

        custom_settings=$(echo "$custom_settings" | jq ". + $(generate_jq_argument "$settings_key" "$value")")

        if string_contains "$SENSITIVE_SETTINGS" "$settings_key"; then
            value='[REDACTED]'
        fi

        echo "[ENV] Set '$settings_key' to new value of '$value'."
    done

    jq ". + $custom_settings " $DEFAULT_SETTINGS_JSON > "$SETTINGS_FILE"
fi

exec transmission-daemon \
    --foreground \
    --config-dir "$TRANSMISSION_HOME" \
    --logfile "$TRANSMISSION_LOG_FILE" \
    --log-level "$TRANSMISSION_LOG_LEVEL"
