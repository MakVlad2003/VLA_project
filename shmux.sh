#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
SHARED_DIR=$(readlink -f "$PROJECT_DIR/storage")
CACHE_DIR="$HOME/.cache/vla-course"
IMAGE=vla-course:sim5.1.0-lab2.3.0
CONTAINER=vla-course-sim
SOCKET=vla-course
SESSION=isaac
SERVER_IP=${VLA_SERVER_IP:-100.98.47.185}
SIGNAL_PORT=49100
STREAM_PORT=47998
LOG_FILE="$SHARED_DIR/runs/isaac-sim.log"
ACTION=${1:-start}

show_status() {
    docker ps -a --filter "name=^/${CONTAINER}$" --format '{{.Names}} {{.Status}} {{.Image}}'
    if tmux -L "$SOCKET" has-session -t "$SESSION" 2>/dev/null; then
        printf 'tmux session %s/%s exists\n' "$SOCKET" "$SESSION"
    fi
    printf 'WebRTC server %s, signal %s/TCP, stream %s/UDP\n' "$SERVER_IP" "$SIGNAL_PORT" "$STREAM_PORT"
    printf 'Log %s\n' "$LOG_FILE"
}

if [[ "$ACTION" == _run ]]; then
    docker run --rm --init --name "$CONTAINER" \
        --label vla.project=VLA_project \
        --gpus all --network host --shm-size 2g --group-add 1234 \
        -e ACCEPT_EULA=Y -e NVIDIA_DRIVER_CAPABILITIES=all \
        --mount "type=bind,src=$PROJECT_DIR,dst=/workspace/VLA_project" \
        --mount "type=bind,src=$SHARED_DIR,dst=$SHARED_DIR" \
        --mount "type=bind,src=$CACHE_DIR/home,dst=/home/vla" \
        --mount "type=bind,src=$CACHE_DIR/kit,dst=/isaac-sim/kit/cache" \
        --mount "type=bind,src=$SHARED_DIR/runtime/logs,dst=/home/vla/.nvidia-omniverse/logs" \
        "$IMAGE" \
        --/app/livestream/publicEndpointAddress="$SERVER_IP" \
        --/app/livestream/port="$SIGNAL_PORT" \
        --/app/livestream/allowDynamicResize=true \
        --exec /workspace/VLA_project/runtime_check.py \
        2>&1 | tee -a "$LOG_FILE"
    exit
fi

case "$ACTION" in
    attach)
        exec tmux -L "$SOCKET" attach-session -t "$SESSION"
        ;;
    logs)
        exec tail -n 80 -F "$LOG_FILE"
        ;;
    status)
        show_status
        exit
        ;;
    shell)
        exec docker exec -it "$CONTAINER" bash
        ;;
    start|stop|build) ;;
    *)
        echo 'Usage: ./shmux.sh [start|attach|logs|status|shell|stop|build]' >&2
        exit 2
        ;;
esac

mkdir -p "$CACHE_DIR"
exec 9>"$CACHE_DIR/launcher.lock"
flock 9

if [[ "$ACTION" == stop ]]; then
    if [[ $(docker ps -q --filter "name=^/${CONTAINER}$") ]]; then
        [[ $(docker inspect -f '{{index .Config.Labels "vla.project"}}' "$CONTAINER") == VLA_project ]]
        docker stop --timeout 30 "$CONTAINER"
    fi
    if tmux -L "$SOCKET" has-session -t "$SESSION" 2>/dev/null; then
        tmux -L "$SOCKET" kill-session -t "$SESSION"
    fi
    exit
fi

findmnt -T "$SHARED_DIR" -n -o FSTYPE | grep -Eq '^nfs4?$'

if [[ "$ACTION" == build ]]; then
    BASE_IMAGE=nvcr.io/nvidia/isaac-lab:2.3.2
    EXPECTED_BASE=sha256:b746967f76f21f351dae0a910067faad55741fd731ab41bdb4eba585d8e232d3
    [[ $(docker image inspect "$BASE_IMAGE" -f '{{.Id}}') == "$EXPECTED_BASE" ]]
    BUILD_DIR=$(mktemp -d /tmp/vla-course-build.XXXXXX)
    trap 'rm -rf -- "$BUILD_DIR"' EXIT
    cp "$SHARED_DIR/runtime/downloads/IsaacLab-v2.3.0.tar.gz" "$BUILD_DIR/"
    DOCKER_BUILDKIT=0 docker build --network host \
        --build-arg "BASE_IMAGE=$BASE_IMAGE" \
        --build-arg "PROJECT_UID=$(id -u)" --build-arg "PROJECT_GID=$(id -g)" \
        -t "$IMAGE" -f "$PROJECT_DIR/Dockerfile" "$BUILD_DIR"
    exit
fi

if [[ $(docker ps -q --filter "name=^/${CONTAINER}$") ]]; then
    show_status
    exit
fi
if tmux -L "$SOCKET" has-session -t "$SESSION" 2>/dev/null; then
    echo 'The tmux launcher session is still active. Inspect ./shmux.sh attach.' >&2
    exit 1
fi
docker image inspect "$IMAGE" >/dev/null
python3 - "$SERVER_IP" "$SIGNAL_PORT" "$STREAM_PORT" <<'PY'
import socket
import sys

for kind, port in [(socket.SOCK_STREAM, int(sys.argv[2])), (socket.SOCK_DGRAM, int(sys.argv[3]))]:
    with socket.socket(socket.AF_INET, kind) as listener:
        if kind == socket.SOCK_STREAM:
            listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        listener.bind((sys.argv[1], port))
PY
mkdir -p "$CACHE_DIR/home/.nvidia-omniverse/logs" "$CACHE_DIR/kit" "$SHARED_DIR/runtime/logs" "$SHARED_DIR/runs"
printf -v LAUNCH 'exec bash %q _run' "$PROJECT_DIR/shmux.sh"
tmux -L "$SOCKET" new-session -d -s "$SESSION" "$LAUNCH" 9>&-
show_status
echo 'Starting. Wait for Isaac Sim Full Streaming App is loaded. in ./shmux.sh logs.'
