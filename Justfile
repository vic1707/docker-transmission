#### ENV ####
ARCH := env_var_or_default("ARCH", arch())
TRANSMISSION_VERSION := env("TRANSMISSION_VERSION")
## Waiting for https://github.com/casey/just/pull/2440 to get a cleaner conditonal
CONTAINER_RUNTIME := env_var_or_default(
    "CONTAINER_RUNTIME",
    if `which docker || true` =~ '.*/docker' { "docker" } 
    else if `which podman || true` =~ '.*/podman' { "podman" } 
    else { error("Error: Neither Podman nor Docker is installed. Please ensure one is installed and available in $PATH to proceed.") }
)

#### AUTOMATIC ####
GITHUB_TAGS_API := "https://api.github.com/repos/transmission/transmission/git/refs/tags"
GITHUB_BRANCHES_API := "https://api.github.com/repos/transmission/transmission/branches"
GITHUB_COMMITS_API := "https://api.github.com/repos/transmission/transmission/commits"
IMAGE_NAME := "transmission"
PLATFORM := 'linux/' + ARCH
## Yup, that's disgusting
SPECIAL_TAG := (
    if TRANSMISSION_VERSION == 'main' {
        'nightly'
    } else if semver_matches(TRANSMISSION_VERSION, '>0.0.0') == 'true' {
        'latest'
    } else {
        error("Provided TRANSMISSION_VERSION is unsupported for now.")
    }
)
## Tags are either :<semver release version> or :<branch name>-<short sha>
IMAGE_TAG := (
    if shell('curl -fso /dev/null -w "%{http_code}" $1/$2 || true', GITHUB_TAGS_API, TRANSMISSION_VERSION) == '200' { 
        TRANSMISSION_VERSION
    } else if shell('curl -fso /dev/null -w "%{http_code}" $1/$2 || true', GITHUB_BRANCHES_API, TRANSMISSION_VERSION) == '200' {
        shell("echo $1-$2", TRANSMISSION_VERSION, shell('curl -fs $1/$2 | jq -r ".sha" | cut -c 1-7', GITHUB_COMMITS_API, TRANSMISSION_VERSION))
    } else {
        error("Provided TRANSMISSION_VERSION doesn't exists.")
    }
)

@get-tag:
    echo {{ IMAGE_TAG }}
@get-special-tag:
    echo {{ SPECIAL_TAG }}
@get-tags:
    echo {{ IMAGE_TAG }} {{ SPECIAL_TAG }}

build-cli:
    {{ CONTAINER_RUNTIME }} build --target SCRATCH_CLI \
        -t {{ IMAGE_NAME }}-cli:{{ IMAGE_TAG }} \
        -t {{ IMAGE_NAME }}-cli:{{ SPECIAL_TAG }} \
        --platform {{ PLATFORM }} \
        --build-arg JOBS={{ num_cpus() }} \
        --build-arg TRANSMISSION_VERSION={{ TRANSMISSION_VERSION }} .

build-daemon:
    {{ CONTAINER_RUNTIME }} build --target ALPINE_DAEMON \
        -t {{ IMAGE_NAME }}-daemon:{{ IMAGE_TAG }} \
        -t {{ IMAGE_NAME }}-daemon:{{ SPECIAL_TAG }} \
        --platform {{ PLATFORM }} \
        --build-arg JOBS={{ num_cpus() }} \
        --build-arg TRANSMISSION_VERSION={{ TRANSMISSION_VERSION }} .

clean:
    {{ CONTAINER_RUNTIME }} rmi {{ IMAGE_NAME }}-cli:{{ IMAGE_TAG }} {{ IMAGE_NAME }}-daemon:{{ IMAGE_TAG }}

@debug:
    echo "Image tag: '{{ IMAGE_TAG }}'"
    echo "Container runtime: '{{ CONTAINER_RUNTIME }}'"
    echo "Transmission verion: '{{ TRANSMISSION_VERSION }}'"

default:
    just --list

all-build: build-cli build-daemon
