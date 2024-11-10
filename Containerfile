FROM alpine:3.20.3 as BUILDER

ARG TRANSMISSION_VERSION
RUN test -n "$TRANSMISSION_VERSION"

ARG JOBS=1
RUN test $JOBS -ge 1 || { echo "JOBS should be a positive integer, got '$JOBS'"; exit 1; }

SHELL ["/bin/ash", "-eo", "pipefail", "-c"]

RUN apk add --no-cache git moreutils jq

## Get transmission release
RUN git clone \
    --depth 1 \
    --branch $TRANSMISSION_VERSION \
    https://github.com/transmission/transmission \
    /root/transmission
RUN git -C /root/transmission submodule update --init --recursive

## Build dependencies
RUN apk add --no-cache \
    `# Build tools` \
    cmake make g++ python3 \
    `# build dependencies` \
    curl-dev gettext-dev linux-headers \
    `# static dependencies` \
    brotli-static c-ares-static curl-static gettext-static \
    libidn2-static libunistring-static nghttp2-static \
    openssl-libs-static zlib-static zstd-static

WORKDIR /root/transmission
RUN cmake \
    -B build \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=OFF \
    `# static build settings` \
    -DCMAKE_EXE_LINKER_FLAGS="-static" \
    -DCMAKE_CXX_LINK_EXECUTABLE="<CMAKE_CXX_COMPILER> <FLAGS> <CMAKE_CXX_LINK_FLAGS> <LINK_FLAGS> <OBJECTS> -o <TARGET> <LINK_LIBRARIES> -lbrotlidec -lnghttp2 -lcares -lidn2 -lunistring -lz -lbrotlicommon -lzstd" \
    -DOPENSSL_USE_STATIC_LIBS=TRUE \
    -DCURL_LIBRARY_RELEASE=/usr/lib/libcurl.a \
    -DUSE_SYSTEM_PSL=NO \
    `# builds transmission-cli` \
    -DENABLE_CLI=ON \
    `# builds transmission-daemon` \
    -DENABLE_DAEMON=ON \
    `# builds transmission-remote, transmission-create, transmission-edit and transmission-show cli tools` \
    -DENABLE_UTILS=ON \
    `# Useful things to have here` \
    -DENABLE_UTP=ON \
    -DENABLE_NLS=ON \
    -DINSTALL_WEB=ON \
    -DWITH_INOTIFY=ON \
    `# Disable unneeded options` \
    -DENABLE_GTK=OFF \
    -DENABLE_QT=OFF \
    -DENABLE_MAC=OFF \
    -DREBUILD_WEB=OFF \
    -DENABLE_TESTS=OFF \
    -DENABLE_WERROR=OFF \
    -DINSTALL_DOC=OFF \
    -DINSTALL_LIB=OFF \
    -DENABLE_DEPRECATED=OFF \
    -DRUN_CLANG_TIDY=OFF \
    -DWITH_APPINDICATOR=OFF \
    -DWITH_KQUEUE=OFF \
    -DWITH_SYSTEMD=OFF

RUN cmake --build build -- -j${JOBS}

## To generate the default settings.json used by the daemon
RUN timeout 1s build/daemon/transmission-daemon -f --config-dir /tmp/transmission-daemon

## Add missing keys with defaults for versions <=4.0.6
## see: https://github.com/transmission/transmission/issues/7212
RUN jq < /tmp/transmission-daemon/settings.json \
    | jq '. + { "lazy-bitfield-enabled": "utp" }' \
    | jq '. + { "pidfile": "" }' \
    | jq '. + { "watch-dir": "/root/Downloads" }' \
    | jq '. + { "watch-dir-enabled": false }' \
    | jq --sort-keys \
    | sponge /tmp/transmission-daemon/settings.json

## Custom default settings
RUN cat /tmp/transmission-daemon/settings.json \
    `# prevents login via port forwarding` \
    | jq '. + { "rpc-whitelist-enabled": false }' \
    | jq '. + { "download-dir": "/data/completed" }' \
    | jq '. + { "incomplete-dir": "/data/incomplete" }' \
    | jq '. + { "incomplete-dir-enabled": true }' \
    | jq '. + { "watch-dir": "/data/watch" }' \
    | jq '. + { "port-forwarding-enabled": false }' \
    | jq '. + { "lpd-enabled": false }' \
    | jq '. + { "rename-partial-files": true }' \
    | jq --sort-keys \
    | sponge /tmp/transmission-daemon/settings.json
#########################################################################################################
FROM scratch as SCRATCH_CLI

COPY --from=BUILDER /root/transmission/build/cli/transmission-cli /

ENTRYPOINT [ "/transmission-cli" ]
#########################################################################################################
FROM alpine:3.20.3 AS ALPINE_DAEMON

HEALTHCHECK --interval=30s --timeout=10s --retries=3 \
    CMD (ping -c 1 google.com >/dev/null 2>&1 || { echo "Network is down."; exit 1; }) \
        && (wget --spider --server-response "http://127.0.0.1:${TRANSMISSION_RPC_PORT:-9091}/transmission/web/" 2>&1 \
                | awk '/^  HTTP/{print $2}' | grep -q "200" \
            || { echo "Cannot access the transmission web-ui."; exit 1; }) \
        && { echo "Network OK, http://127.0.0.1:${TRANSMISSION_RPC_PORT:-9091}/transmission/web/ is accessible."; exit 0; }

ARG TRANSMISSION_VERSION
ENV TRANSMISSION_VERSION=$TRANSMISSION_VERSION

RUN apk add --no-cache jq

WORKDIR /etc/transmission

# transmission-remote, transmission-create, transmission-edit and transmission-show
COPY --from=BUILDER /root/transmission/build/utils/transmission-* /usr/bin
# transmission-daemon
COPY --from=BUILDER /root/transmission/build/daemon/transmission-daemon /usr/bin
# default web ui
COPY --from=BUILDER /root/transmission/web/public_html /usr/share/transmission/public_html

## Get default settings.json
COPY --from=BUILDER /tmp/transmission-daemon/settings.json ./default-settings.json

COPY entrypoint.sh .

ENTRYPOINT [ "/etc/transmission/entrypoint.sh" ]
