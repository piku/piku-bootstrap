#!/bin/bash
# Test Helper Library for Piku E2E Tests
# Source this file in test scripts: source /test-lib/test_helpers.sh

set -e

# Configuration
PIKU_SERVER="${PIKU_SERVER:-piku-server}"
PIKU_USER="piku"
SSH_KEY="/root/.ssh/id_ed25519"
TEST_APP_DIR="/tmp/test-apps"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Counters for test results
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

#######################################
# Logging functions
#######################################

log_test() {
    echo -e "${BLUE}[TEST]${NC} $1"
}

log_pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
}

log_info() {
    echo -e "${YELLOW}[INFO]${NC} $1"
}

#######################################
# SSH/Piku command helpers
#######################################

# Run a command on the piku server as root
ssh_server() {
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        root@"$PIKU_SERVER" "$@" 2>/dev/null
}

# Run a piku command via SSH
run_piku() {
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        "$PIKU_USER@$PIKU_SERVER" "$@" 2>/dev/null
}

#######################################
# App deployment helpers
#######################################

# Create a new test app directory
# Usage: create_app <app_name>
create_app() {
    local app_name="$1"
    local app_dir="$TEST_APP_DIR/$app_name"
    
    rm -rf "$app_dir"
    mkdir -p "$app_dir"
    cd "$app_dir"
    git init > /dev/null 2>&1
    
    echo "$app_dir"
}

# Deploy an app to piku via git push
# Usage: deploy_app <app_name>
deploy_app() {
    local app_name="$1"
    local app_dir="$TEST_APP_DIR/$app_name"
    
    cd "$app_dir"
    git add -A
    git commit -m "Deploy $app_name" --allow-empty
    
    # Set up remote and push
    git remote remove piku 2>/dev/null || true
    git remote add piku "$PIKU_USER@$PIKU_SERVER:$app_name"
    
    GIT_SSH_COMMAND="ssh -i $SSH_KEY -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null" \
        git push -f piku master 2>&1
}

# Wait for an app to be ready (uwsgi config exists)
# Usage: wait_for_app <app_name> [timeout_seconds]
wait_for_app() {
    local app_name="$1"
    local timeout="${2:-120}"
    local elapsed=0
    
    log_info "Waiting for $app_name to be ready..."
    
    # First wait for uwsgi config to exist
    while [ $elapsed -lt $timeout ]; do
        if ssh_server "ls /home/piku/.piku/uwsgi-enabled/${app_name}*.ini >/dev/null 2>&1"; then
            break
        fi
        sleep 5
        elapsed=$((elapsed + 5))
    done
    
    if [ $elapsed -ge $timeout ]; then
        log_fail "Timeout waiting for $app_name uwsgi config"
        return 1
    fi
    
    # Give uwsgi time to start the process
    sleep 10
    
    # Now wait for the app to actually respond (not 403)
    while [ $elapsed -lt $timeout ]; do
        local http_code
        http_code=$(ssh_server "curl -s -o /dev/null -w '%{http_code}' http://localhost -H 'Host: $app_name'" 2>/dev/null || echo "000")
        if [ "$http_code" != "403" ] && [ "$http_code" != "000" ] && [ "$http_code" != "502" ]; then
            log_info "$app_name is ready (HTTP $http_code)"
            return 0
        fi
        sleep 5
        elapsed=$((elapsed + 5))
    done
    
    log_fail "Timeout waiting for $app_name"
    # Debug output on timeout
    log_info "=== Debug info for $app_name ==="
    ssh_server "ls -la /home/piku/.piku/uwsgi-enabled/" || true
    ssh_server "ls -la /home/piku/.piku/nginx/" || true
    ssh_server "systemctl status uwsgi-piku" || true
    ssh_server "cat /home/piku/.piku/uwsgi/uwsgi.log | tail -30" || true
    ssh_server "cat /home/piku/.piku/logs/${app_name}/*.log | tail -20" 2>/dev/null || true
    log_info "=== End debug info ==="
    return 1
}

# Test HTTP response from an app
# Usage: test_http <app_name> <expected_content> [path] [port]
test_http() {
    local app_name="$1"
    local expected="$2"
    local path="${3:-/}"
    local port="${4:-80}"
    
    log_info "Testing HTTP response for $app_name..."
    
    # Make request via the server's nginx
    local response
    response=$(ssh_server "curl -s http://localhost:$port$path -H 'Host: $app_name'" 2>/dev/null || echo "CURL_FAILED")
    
    if echo "$response" | grep -q "$expected"; then
        log_pass "HTTP response contains: $expected"
        return 0
    else
        log_fail "Expected '$expected' but got: $response"
        return 1
    fi
}

# Destroy an app
# Usage: destroy_app <app_name>
destroy_app() {
    local app_name="$1"
    
    log_info "Destroying app: $app_name"
    run_piku destroy "$app_name" 2>/dev/null || true
    rm -rf "$TEST_APP_DIR/$app_name"
}

#######################################
# Test framework helpers
#######################################

# Run a single test
# Usage: run_test <test_name> <test_function>
run_test() {
    local test_name="$1"
    local test_func="$2"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    log_test "Running: $test_name"
    
    if $test_func; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        log_pass "$test_name"
        return 0
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        log_fail "$test_name"
        return 1
    fi
}

# Print test summary and exit with appropriate code
test_summary() {
    echo
    echo "========================================"
    echo "Test Results: $TESTS_PASSED/$TESTS_RUN passed"
    if [ $TESTS_FAILED -gt 0 ]; then
        echo "FAILED: $TESTS_FAILED tests"
        return 1
    else
        echo "All tests passed!"
        return 0
    fi
}

#######################################
# App template helpers
#######################################

# Create a basic Flask WSGI app with requirements.txt
# Usage: create_flask_app <app_dir> [extra_deps]
create_flask_app() {
    local app_dir="$1"
    local extra_deps="${2:-}"
    
    # Extract app name from path (last component)
    local app_name=$(basename "$app_dir")
    
    cat > "$app_dir/requirements.txt" << EOF
flask
$extra_deps
EOF

    # Add ENV file with SERVER_NAME for nginx virtual host
    cat > "$app_dir/ENV" << EOF
NGINX_SERVER_NAME=$app_name
EOF

    cat > "$app_dir/wsgi.py" << 'EOF'
from flask import Flask
app = Flask(__name__)

@app.route('/')
def hello():
    return 'Hello from Flask!'

@app.route('/health')
def health():
    return 'OK'

# WSGI entry point for uwsgi
application = app
EOF

    cat > "$app_dir/Procfile" << 'EOF'
wsgi: wsgi:app
EOF
}

# Create a basic Flask app with pyproject.toml (UV)
# Usage: create_uv_flask_app <app_dir> [python_version]
create_uv_flask_app() {
    local app_dir="$1"
    local python_version="${2:-3.10}"
    local app_name=$(basename "$app_dir")
    
    cat > "$app_dir/pyproject.toml" << EOF
[project]
name = "test-app"
version = "0.1.0"
requires-python = ">=$python_version"
dependencies = [
    "flask",
]
EOF

    cat > "$app_dir/wsgi.py" << 'EOF'
from flask import Flask
app = Flask(__name__)

@app.route('/')
def hello():
    return 'Hello from UV Flask!'

# WSGI entry point for uwsgi
application = app
EOF

    cat > "$app_dir/Procfile" << 'EOF'
wsgi: wsgi:app
EOF

    cat > "$app_dir/ENV" << EOF
PYTHON_VERSION=$python_version
NGINX_SERVER_NAME=$app_name
EOF
}

# Create a basic Node.js Express app
# Usage: create_node_app <app_dir> [node_version]
create_node_app() {
    local app_dir="$1"
    local node_version="${2:-18}"
    local app_name=$(basename "$app_dir")
    
    cat > "$app_dir/package.json" << EOF
{
  "name": "test-app",
  "version": "1.0.0",
  "main": "index.js",
  "scripts": {
    "start": "node index.js"
  },
  "dependencies": {
    "express": "^4.18.0"
  },
  "engines": {
    "node": ">=$node_version"
  }
}
EOF

    cat > "$app_dir/index.js" << 'EOF'
const express = require('express');
const app = express();
const port = process.env.PORT || 3000;

app.get('/', (req, res) => {
  res.send('Hello from Node.js!');
});

app.get('/health', (req, res) => {
  res.send('OK');
});

app.listen(port, '0.0.0.0', () => {
  console.log(`Server running on port ${port}`);
});
EOF

    cat > "$app_dir/Procfile" << 'EOF'
web: node index.js
EOF

    cat > "$app_dir/ENV" << EOF
NGINX_SERVER_NAME=$app_name
EOF
}

# Initialize test environment
mkdir -p "$TEST_APP_DIR"
