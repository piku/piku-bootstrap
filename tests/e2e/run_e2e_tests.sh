#!/bin/bash
# E2E Test Runner for piku-bootstrap
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

COMPOSE_PROJECT="piku-e2e-tests"
KEEP_CONTAINERS=false
NO_BUILD=false
TEST_FILTER=""
PIKU_REPO="${PIKU_REPO:-piku/piku}"
PIKU_BRANCH="${PIKU_BRANCH:-master}"

RED='[0;31m'
GREEN='[0;32m'
YELLOW='[1;33m'
NC='[0m'

usage() {
    cat << 'USAGE'
Usage: ./run_e2e_tests.sh [OPTIONS] [TEST_PATTERN]

Run E2E tests for piku-bootstrap in Docker containers.

OPTIONS:
    -h, --help          Show this help message
    -k, --keep          Keep containers running after tests (for debugging)
    -n, --no-build      Skip Docker image build
    --piku-repo=REPO    GitHub repo to install piku from (default: piku/piku)
    --piku-branch=BRANCH Branch to install from (default: master)

EXAMPLES:
    ./run_e2e_tests.sh                          # Run all tests
    ./run_e2e_tests.sh --keep                 # Keep containers for debugging
    ./run_e2e_tests.sh python                 # Run only Python-related tests
USAGE
}

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

cleanup() {
    if [ "$KEEP_CONTAINERS" = false ]; then
        log_info "Cleaning up containers..."
        docker compose -p "$COMPOSE_PROJECT" down -v --remove-orphans 2>/dev/null || true
    else
        log_warn "Containers kept running. Clean up with:"
        echo "  docker compose -p $COMPOSE_PROJECT down -v"
    fi
}

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help) usage; exit 0 ;;
        -k|--keep) KEEP_CONTAINERS=true; shift ;;
        -n|--no-build) NO_BUILD=true; shift ;;
        --piku-repo=*) PIKU_REPO="${1#*=}"; shift ;;
        --piku-branch=*) PIKU_BRANCH="${1#*=}"; shift ;;
        -*) log_error "Unknown option: $1"; usage; exit 1 ;;
        *) TEST_FILTER="$1"; shift ;;
    esac
done

trap cleanup EXIT

log_info "=== Piku E2E Test Suite ==="
log_info "Piku Repository: $PIKU_REPO"
log_info "Piku Branch: $PIKU_BRANCH"

export PIKU_REPO PIKU_BRANCH COMPOSE_PROJECT

# Build images
if [ "$NO_BUILD" = false ]; then
    log_info "Building Docker images..."
    DOCKER_BUILDKIT=0 COMPOSE_DOCKER_CLI_BUILD=0 docker compose -p "$COMPOSE_PROJECT" build --no-cache
fi

# Start piku-server only first
log_info "Starting piku-server container..."
docker compose -p "$COMPOSE_PROJECT" up -d piku-server

# Wait for systemd to be ready
log_info "Waiting for systemd to start..."
for i in $(seq 1 60); do
    if docker compose -p "$COMPOSE_PROJECT" exec -T piku-server systemctl is-system-running --wait 2>/dev/null | grep -qE "(running|degraded)"; then
        log_info "Systemd is ready"
        break
    fi
    sleep 2
done

# Run piku-bootstrap
log_info "Running piku-bootstrap first-run..."
docker compose -p "$COMPOSE_PROJECT" exec -T piku-server bash -c 'cd /root && ./piku-bootstrap first-run --no-interactive'

log_info "Installing piku from $PIKU_REPO @ $PIKU_BRANCH..."
docker compose -p "$COMPOSE_PROJECT" exec -T piku-server bash -c "cd /root && ./piku-bootstrap install --piku-repo=$PIKU_REPO --piku-branch=$PIKU_BRANCH"

# Set up SSH keys
log_info "Setting up SSH keys..."
docker compose -p "$COMPOSE_PROJECT" exec -T piku-server bash -c '
    mkdir -p /root/.ssh
    ssh-keygen -t ed25519 -f /root/.ssh/id_ed25519 -N "" -q
    cat /root/.ssh/id_ed25519.pub >> /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys
    mkdir -p /shared-keys
    cp /root/.ssh/id_ed25519 /shared-keys/
    cp /root/.ssh/id_ed25519.pub /shared-keys/
    chmod 644 /shared-keys/id_ed25519.pub
    chmod 600 /shared-keys/id_ed25519
    cat /root/.ssh/id_ed25519.pub > /tmp/test_key.pub
    sudo -u piku python3 /home/piku/piku.py setup:ssh /tmp/test_key.pub
    rm /tmp/test_key.pub'
# Wait for SSH to be fully ready
# Remove nologin file to allow SSH logins (Docker systemd workaround)
log_info "Enabling user logins..."
docker compose -p "$COMPOSE_PROJECT" exec -T piku-server rm -f /run/nologin /var/run/nologin /etc/nologin 2>/dev/null || true
sleep 5

# Now start test-client
log_info "Starting test-client container..."
docker compose -p "$COMPOSE_PROJECT" up -d test-client
sleep 3

# Check if test-client is running
if ! docker compose -p "$COMPOSE_PROJECT" ps test-client --format "{{.Status}}" | grep -qE "Up|running"; then
    log_error "test-client container failed to start!"
    log_info "Container logs:"
    docker compose -p "$COMPOSE_PROJECT" logs test-client
    exit 1
fi

# Set up SSH on the client
log_info "Configuring test client..."
docker compose -p "$COMPOSE_PROJECT" exec -T test-client bash -c '
    cp /shared-keys/id_ed25519 /root/.ssh/
    chmod 600 /root/.ssh/id_ed25519
    ssh-keyscan -H piku-server >> /root/.ssh/known_hosts 2>/dev/null
    git config --global user.email "test@piku.test"
    git config --global user.name "Piku Test"
'
# Run tests
log_info "Running tests..."
TESTS_PASSED=0
TESTS_FAILED=0
FAILED_TESTS=""

if [ -n "$TEST_FILTER" ]; then
    TEST_FILES=$(find tests -name "test_*.sh" | grep -i "$TEST_FILTER" || true)
else
    TEST_FILES=$(find tests -name "test_*.sh" 2>/dev/null || true)
fi

if [ -z "$TEST_FILES" ]; then
    log_warn "No test files found"
    exit 0
fi

for test_file in $TEST_FILES; do
    test_name=$(basename "$test_file" .sh)
    log_info "Running: $test_name"
    
    if docker compose -p "$COMPOSE_PROJECT" exec -T test-client bash -c "source /test-lib/test_helpers.sh && bash /$test_file"; then
        log_info "PASSED: $test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "FAILED: $test_name"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        FAILED_TESTS="$FAILED_TESTS $test_name"
    fi
done

echo
log_info "=== Test Summary ==="
log_info "Passed: $TESTS_PASSED"
[ $TESTS_FAILED -gt 0 ] && log_error "Failed: $TESTS_FAILED ($FAILED_TESTS)"

exit $TESTS_FAILED
