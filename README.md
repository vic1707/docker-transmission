# Transmission Container

[Transmission](https://www.transmissionbt.com/) is designed for easy, powerful use.
Transmission has the features you want from a BitTorrent client: encryption, a web interface, peer exchange, magnet links, DHT, µTP, UPnP and NAT-PMP port forwarding, webseed support, watch directories, tracker editing, global and per-torrent speed limits, and more.

## Features

This repo provides 2 containers `transmission-cli` and `transmission-daemon`.
The cli, as its name implies provides you with the Transmission Command Line Tool.
The daemon is the tool used by other popular transmission containers such as `linuxserver`'s and `haugene`'s.

## Getting Started

### Prerequisites

- `Docker`/`Podman`/`Lilipod`/or any other container manager must be installed on your system.

### Usage

To start a container with `transmission-daemon`, run:

```bash
docker run -d \
    -p 9091:9091 \
    -v ./config:/config \
    -v ./downloads:/data \
    vic1707/transmission-daemon
```

To run the container with `transmission-cli`, use:

```bash
docker run -it \
    vic1707/transmission-cli \
    --help
```

### Environment Variables (daemon)

Daemon settings can be set via environment variables.
Any variable listed [here](https://github.com/transmission/transmission/blob/main/docs/Editing-Configuration-Files.md) can be set by using `TRANSMISSION_<capitalized _prop_name>` (ie: `rpc_password` becomes `TRANSMISSION_RPC_PASSWORD`).

Custom UIs can be installed by setting `TRANSMISSION_WEB_UI` to

- [`combustion`](https://github.com/Secretmapper/combustion)
- [`kettu`](https://github.com/endor/kettu)
- [`transmission-web-control`](https://github.com/ronggang/transmission-web-control)
- [`flood`](https://github.com/johman10/flood-for-transmission)
- [`shift`](https://github.com/killemov/Shift)
- [`transmissionic`](https://github.com/6c65726f79/Transmissionic)

Other available env variables are:

- `TRANSMISSION_LOG_LEVEL`: 'critical', 'error', 'warn', 'info', 'debug' or 'trace' (default: info).
- `TRANSMISSION_WEB_HOME`: sets where transmission's custom web-ui lives (default if UI is set: '/tmp/web-ui').
- `TRANSMISSION_HOME`: sets where transmission's config lives (default: '/config').

The default configuration can be seen by running the container with the `--show-config` flag:

```sh
docker run --rm vic1707/transmission-daemon --show-config
```

To see the complete list of available env vars check the `--help` flag.

### Volumes

By default the folder storing the configuration for transmission is `/config` (can be set by `TRANSMISSION_HOME`).
Output folder for torrents files are under `/data`.

### Ports

- `9091`: Web interface port for `transmission-daemon` (can be overwritten by `TRANSMISSION_RPC_PORT`)
- `51413`: Transmission peer port (can be overwritten by `TRANSMISSION_PEER_PORT`), portforwarding is disabled by default.

### Security (daemon)

The container can be run in readonly mode if you don't set a custom web-ui, else you'll need to add `--tmpfs /tmp/web-ui` so the daemon can download and extract the custom ui.
During testing it looked like the container can be run with `--cap-drop all`, I don't know if all torrents will be fine with this setting so use with caution (and please report if you encountered an issue!).

For context, I was able to run the container successfuly with the following compose:

```yaml
services:
    transmission:
        container_name: transmission
        image: transmission
        build:
            context: .
            target: ALPINE_DAEMON
            dockerfile: Containerfile
            args:
                TRANSMISSION_VERSION: 4.0.6
                JOBS: 4
        read_only: true
        cap_drop:
            - all
        security_opt:
            - no-new-privileges
        environment:
            TRANSMISSION_WEB_UI: flood
        tmpfs:
            - /tmp/web-ui
            - /config
        volumes:
            - ./downloads:/data:rw
        ports:
            - 9091:9091
```

### Troubleshooting

- **Access Issues**: Ensure ports are correctly mapped and accessible.
- **Permission Denied**: Verify directory permissions, especially for mounted volumes.
- **Configuration Not Applied**: Check that `settings.json` changes are saved and `transmission-daemon` is restarted if running as a service.
