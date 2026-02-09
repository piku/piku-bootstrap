#!/bin/bash
# E2E tests for piku-bootstrap with UV support
# 
# This script:
# 1. Builds a Docker image with piku-bootstrap
# 2. Starts a container with systemd
# 3. Runs piku-bootstrap to install piku from the UV support branch
# 4. Sets up SSH for git push
# 5. Runs the E2E test suite
#
# Usage: ./run_tests.sh [--no-cache] [--keep]
#   --no-cache: Force rebuild of Docker image
#   --keep: Keep container running after tests (for debugging)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Configuration - can be overridden via environment
PIKU_REPO="${PIKU_REPO:-clusterfudge/piku}"
PIKU_BRANCH="${PIKU_BRANCH:-claude/fix-piku-uv-support-ILtq9}"
CONTAINER_NAME="piku-e2e-test"
IMAGE_NAME="piku-bootstrap-e2e-test"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Parse args
NO_CACHE=""
KEEP_CONTAINER=""
for arg in "$@"; do
    case $arg in
        --no-cache|-f)
            NO_CACHE="--no-cache"
            ;;
        --keep|-k)
            KEEP_CONTAINER="1"
            ;;
    esac
done

cleanup() {
    if [ -z "$KEEP_CONTAINER" ]; then
        echo -e "${YELLOW}Cleaning up...${NC}"
        docker stop "$CONTAINER_NAME" 2>/dev/null || true
        docker rm "$CONTAINER_NAME" 2>/dev/null || true
    else
        echo -e "${YELLOW}Keeping container running (use 'docker exec -it $CONTAINER_NAME bash' to inspect)${NC}"
    fi
}

trap cleanup EXIT

echo -e "${YELLOW}=== Building test image ===${NC}"
cd "$BOOTSTRAP_ROOT"
docker build $NO_CACHE -t "$IMAGE_NAME" -f tests/e2e-uv/Dockerfile .

echo ""
echo -e "${YELLOW}=== Starting container with systemd ===${NC}"
docker stop "$CONTAINER_NAME" 2>/dev/null || true
docker rm "$CONTAINER_NAME" 2>/dev/null || true

docker run -d \
    --name "$CONTAINER_NAME" \
    --privileged \
    -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
    --cgroupns=host \
    "$IMAGE_NAME"

# Wait for systemd to be ready
echo "Waiting for systemd to start..."
for i in {1..30}; do
    if docker exec "$CONTAINER_NAME" systemctl is-system-running --wait 2>/dev/null | grep -qE "(running|degraded)"; then
        echo "Systemd is ready"
        break
    fi
    sleep 1
done

echo ""
echo -e "${YELLOW}=== Running piku-bootstrap first-run ===${NC}"
docker exec "$CONTAINER_NAME" bash -c './piku-bootstrap first-run --no-interactive 2>&1 | tail -20'

# Override the cloned playbooks with the ones from the Docker image (which came from this repo)
# This ensures we test the current version of the playbooks, not what's on GitHub
echo -e "${YELLOW}=== Overriding playbooks with local version ===${NC}"
docker exec "$CONTAINER_NAME" bash -c 'cp -r /root/playbooks/* ~/.piku-bootstrap/piku-bootstrap/playbooks/'

echo ""
echo -e "${YELLOW}=== Installing piku from $PIKU_REPO @ $PIKU_BRANCH ===${NC}"
docker exec "$CONTAINER_NAME" bash -c "./piku-bootstrap install --piku-repo=$PIKU_REPO --piku-branch=$PIKU_BRANCH 2>&1 | tail -30"

echo ""
echo -e "${YELLOW}=== Installing UV for piku user ===${NC}"
docker exec "$CONTAINER_NAME" bash -c 'su - piku -c "curl -LsSf https://astral.sh/uv/install.sh | sh"'
docker exec "$CONTAINER_NAME" bash -c 'su - piku -c "/home/piku/.local/bin/uv python install 3.11 3.12"'

echo ""
echo -e "${YELLOW}=== Setting up SSH ===${NC}"
# Remove nologin files that prevent SSH
docker exec "$CONTAINER_NAME" bash -c 'rm -f /var/run/nologin /etc/nologin'
# Start SSH server
docker exec "$CONTAINER_NAME" bash -c '/usr/sbin/sshd'
# Generate SSH key
docker exec "$CONTAINER_NAME" bash -c 'ssh-keygen -t rsa -N "" -f /root/.ssh/id_rsa'
# Add key to piku user via piku.py setup:ssh
docker exec "$CONTAINER_NAME" bash -c 'cat /root/.ssh/id_rsa.pub > /tmp/key.pub && su - piku -c "python3 ~/piku.py setup:ssh /tmp/key.pub"'

echo ""
echo -e "${YELLOW}=== Verifying piku installation ===${NC}"
docker exec "$CONTAINER_NAME" bash -c 'ls -la /home/piku/piku.py'
docker exec "$CONTAINER_NAME" bash -c 'su - piku -c "python3 ~/piku.py --version"' || true
docker exec "$CONTAINER_NAME" bash -c 'systemctl status uwsgi-piku --no-pager' || true

echo ""
echo -e "${YELLOW}=== Running E2E tests ===${NC}"
docker exec "$CONTAINER_NAME" bash /root/test_uv_e2e.sh

echo ""
echo -e "${GREEN}=== All tests completed ===${NC}"
