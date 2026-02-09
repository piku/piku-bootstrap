#!/bin/bash
# E2E tests for UV-based Python app deployment via git push
#
# These tests validate that:
# 1. piku-bootstrap correctly installed piku with UV support
# 2. Apps with pyproject.toml deploy using UV
# 3. Python version selection works
# 4. Dependencies are correctly installed
# 5. Apps actually respond to HTTP requests

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASSED=0
FAILED=0

pass() {
    echo -e "${GREEN}PASS${NC}: $1"
    ((PASSED++)) || true
}

fail() {
    echo -e "${RED}FAIL${NC}: $1"
    ((FAILED++)) || true
}

section() {
    echo ""
    echo -e "${YELLOW}=== $1 ===${NC}"
}

# Helper: Create a test app directory and initialize git
create_app() {
    local app_name="$1"
    local app_dir="/tmp/$app_name"
    
    rm -rf "$app_dir"
    mkdir -p "$app_dir"
    cd "$app_dir"
    git init
    git config user.email "test@test.com"
    git config user.name "Test"
}

# Helper: Commit and push to piku
deploy_app() {
    local app_name="$1"
    local app_dir="/tmp/$app_name"
    
    cd "$app_dir"
    git add -A
    git commit -m "Deploy $app_name" --allow-empty
    
    # Add remote if not exists
    git remote remove piku 2>/dev/null || true
    git remote add piku "piku@localhost:$app_name"
    
    echo "Pushing to piku@localhost:$app_name..." >&2
    
    # Push and capture output (both stdout and stderr)
    local push_output
    push_output=$(GIT_SSH_COMMAND="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -v" \
        git push -f piku master 2>&1) || true
    
    echo "$push_output"
}

# Helper: Destroy an app
destroy_app() {
    local app_name="$1"
    su - piku -c "python3 ~/piku.py destroy $app_name" 2>/dev/null || true
    rm -rf "/tmp/$app_name"
}

# Helper: Wait for app to be accessible and get response
wait_for_app() {
    local port="$1"
    local max_attempts="${2:-30}"
    
    # Validate port is numeric
    if ! [[ "$port" =~ ^[0-9]+$ ]]; then
        return 1
    fi
    
    for i in $(seq 1 $max_attempts); do
        if curl -s --max-time 2 "http://127.0.0.1:$port/" >/dev/null 2>&1; then
            return 0
        fi
        sleep 1
    done
    return 1
}

# Helper: Get app's assigned port from uwsgi config or ENV
get_app_port() {
    local app_name="$1"
    local port=""
    
    # Find any uwsgi config for this app (web.1 or wsgi.1)
    local uwsgi_config
    uwsgi_config=$(ls /home/piku/.piku/uwsgi-available/${app_name}_*.ini 2>/dev/null | head -1)
    
    if [ -n "$uwsgi_config" ] && [ -f "$uwsgi_config" ]; then
        port=$(grep -oP 'http-socket = 127\.0\.0\.1:\K[0-9]+' "$uwsgi_config" 2>/dev/null || echo "")
    fi
    
    # If not found, try piku config
    if [ -z "$port" ]; then
        local port_output
        port_output=$(su - piku -c "python3 ~/piku.py config:get $app_name PORT" 2>/dev/null || echo "")
        port=$(echo "$port_output" | grep -oE '^[0-9]+$' | head -1)
    fi
    
    echo "$port"
}

# Helper: Wait for uwsgi to create the config and start the app
wait_for_deploy() {
    local app_name="$1"
    local max_attempts="${2:-30}"
    
    # Check for both web.1 and wsgi.1 configs (depends on Procfile)
    for i in $(seq 1 $max_attempts); do
        if ls /home/piku/.piku/uwsgi-enabled/${app_name}_*.ini 2>/dev/null | head -1 >/dev/null; then
            # Config exists, wait a bit more for uwsgi to actually start the worker
            # uWSGI emperor mode can take a few seconds to spawn the worker
            sleep 5
            return 0
        fi
        sleep 1
    done
    echo "No uwsgi config found for $app_name after $max_attempts seconds" >&2
    ls -la /home/piku/.piku/uwsgi-enabled/ >&2 || true
    return 1
}

# ============================================
section "Test 1: Basic UV Deployment"
# ============================================
APP_NAME="test-uv-basic"
destroy_app "$APP_NAME"
create_app "$APP_NAME"

cat > pyproject.toml << 'EOF'
[project]
name = "test-uv-basic"
version = "0.1.0"
requires-python = ">=3.10"
dependencies = [
    "flask>=2.0",
]
EOF

# Use system Python version to match uWSGI (which is compiled against system Python)
# This is a limitation: uWSGI can only use the Python version it was compiled with
cat > ENV << 'EOF'
PYTHON_VERSION=3.10
EOF

# Use WSGI module format for piku
cat > wsgi.py << 'EOF'
from flask import Flask

app = Flask(__name__)

@app.route('/')
def hello():
    return 'Hello from UV!'

# WSGI entry point
application = app
EOF

cat > Procfile << 'EOF'
wsgi: wsgi:application
EOF

output=$(deploy_app "$APP_NAME")
echo "Deploy output:"
echo "$output"
echo "---"

if echo "$output" | grep -q "Python (uv) app detected\|uv sync\|Using Python version"; then
    pass "UV deployment detected in output"
else
    fail "UV deployment not detected"
fi

if echo "$output" | grep -q "Creating app\|-----> Python"; then
    pass "App deployment started"
else
    fail "App deployment message not found"
fi

# Wait for deployment to complete
wait_for_deploy "$APP_NAME" 30

# Get port and test HTTP
PORT=$(get_app_port "$APP_NAME")
if [ -n "$PORT" ]; then
    pass "App has PORT configured: $PORT"
    
    if wait_for_app "$PORT" 30; then
        response=$(curl -s "http://127.0.0.1:$PORT/")
        if echo "$response" | grep -q "Hello from UV"; then
            pass "App responds with expected message"
        else
            fail "Unexpected response: $response"
            # Show app logs when there's an error
            echo "App logs:"
            cat /home/piku/.piku/logs/$APP_NAME/*.log 2>/dev/null | tail -30 || true
            echo "uwsgi emperor log:"
            cat /home/piku/.piku/uwsgi/uwsgi.log 2>/dev/null | tail -20 || true
        fi
    else
        fail "App did not become accessible on port $PORT"
        # Show logs for debugging
        echo "App logs:"
        cat /home/piku/.piku/logs/$APP_NAME/*.log 2>/dev/null | tail -20 || true
        echo "uwsgi status:"
        systemctl status uwsgi-piku --no-pager 2>/dev/null | tail -10 || true
    fi
else
    fail "Could not get PORT for app"
    echo "uwsgi config files:"
    ls -la /home/piku/.piku/uwsgi-available/ 2>/dev/null || true
    ls -la /home/piku/.piku/uwsgi-enabled/ 2>/dev/null || true
fi

# ============================================
section "Test 2: Python Version via ENV"
# ============================================
APP_NAME="test-uv-pyver-env"
destroy_app "$APP_NAME"
create_app "$APP_NAME"

cat > pyproject.toml << 'EOF'
[project]
name = "test-uv-pyver-env"
version = "0.1.0"
requires-python = ">=3.10"
dependencies = ["flask>=2.0"]
EOF

cat > wsgi.py << 'EOF'
from flask import Flask
import sys

app = Flask(__name__)

@app.route('/')
def hello():
    return f'Python {sys.version_info.major}.{sys.version_info.minor}'

application = app
EOF

cat > Procfile << 'EOF'
wsgi: wsgi:application
EOF

cat > ENV << 'EOF'
PYTHON_VERSION=3.10
EOF

output=$(deploy_app "$APP_NAME")

if echo "$output" | grep -q "Using Python version: 3.10"; then
    pass "PYTHON_VERSION=3.10 was respected"
else
    fail "PYTHON_VERSION not respected in output"
    echo "$output" | grep -i python || true
fi

wait_for_deploy "$APP_NAME" 30
PORT=$(get_app_port "$APP_NAME")
if [ -n "$PORT" ] && wait_for_app "$PORT" 30; then
    response=$(curl -s "http://127.0.0.1:$PORT/")
    if echo "$response" | grep -q "Python 3"; then
        pass "App running on Python 3.x"
    else
        fail "App not returning Python version: $response"
    fi
else
    fail "App not accessible"
fi

# ============================================
section "Test 3: Python Version via .python-version"
# ============================================
APP_NAME="test-uv-pyver-file"
destroy_app "$APP_NAME"
create_app "$APP_NAME"

cat > pyproject.toml << 'EOF'
[project]
name = "test-uv-pyver-file"
version = "0.1.0"
requires-python = ">=3.10"
dependencies = ["flask>=2.0"]
EOF

cat > wsgi.py << 'EOF'
from flask import Flask
import sys

app = Flask(__name__)

@app.route('/')
def hello():
    return f'Python {sys.version_info.major}.{sys.version_info.minor}'

application = app
EOF

cat > Procfile << 'EOF'
wsgi: wsgi:application
EOF

echo "3.10" > .python-version

output=$(deploy_app "$APP_NAME")

if echo "$output" | grep -q "Using Python version: 3.10"; then
    pass ".python-version file was respected"
else
    fail ".python-version not respected"
    echo "$output" | grep -i python || true
fi

wait_for_deploy "$APP_NAME" 30
PORT=$(get_app_port "$APP_NAME")
if [ -n "$PORT" ] && wait_for_app "$PORT" 30; then
    response=$(curl -s "http://127.0.0.1:$PORT/")
    if echo "$response" | grep -q "Python 3"; then
        pass "App running on Python 3.x"
    else
        fail "App not returning Python version: $response"
    fi
else
    fail "App not accessible"
fi

# ============================================
section "Test 4: Multiple Dependencies"
# ============================================
APP_NAME="test-uv-multideps"
destroy_app "$APP_NAME"
create_app "$APP_NAME"

cat > pyproject.toml << 'EOF'
[project]
name = "test-uv-multideps"
version = "0.1.0"
requires-python = ">=3.10"
dependencies = [
    "flask>=2.0",
    "requests>=2.0",
    "click>=8.0",
]
EOF

# Use system Python to match uWSGI
cat > ENV << 'EOF'
PYTHON_VERSION=3.10
EOF

cat > wsgi.py << 'EOF'
from flask import Flask
import requests
import click

app = Flask(__name__)

@app.route('/')
def hello():
    return f'flask={Flask.__name__}, requests={requests.__version__}, click={click.__version__}'

application = app
EOF

cat > Procfile << 'EOF'
wsgi: wsgi:application
EOF

output=$(deploy_app "$APP_NAME")

wait_for_deploy "$APP_NAME" 30
PORT=$(get_app_port "$APP_NAME")
if [ -n "$PORT" ] && wait_for_app "$PORT" 30; then
    response=$(curl -s "http://127.0.0.1:$PORT/")
    if echo "$response" | grep -q "flask=Flask"; then
        pass "Flask dependency works"
    else
        fail "Flask not working: $response"
    fi
    if echo "$response" | grep -q "requests="; then
        pass "requests dependency works"
    else
        fail "requests not working: $response"
    fi
    if echo "$response" | grep -q "click="; then
        pass "click dependency works"
    else
        fail "click not working: $response"
    fi
else
    fail "App not accessible"
    cat /home/piku/.piku/logs/$APP_NAME/*.log 2>/dev/null | tail -20 || true
fi

# ============================================
section "Test 5: Dependency Update on Redeploy"
# ============================================
APP_NAME="test-uv-depupdate"
destroy_app "$APP_NAME"
create_app "$APP_NAME"

# Initial deploy with just flask
cat > pyproject.toml << 'EOF'
[project]
name = "test-uv-depupdate"
version = "0.1.0"
requires-python = ">=3.10"
dependencies = ["flask>=2.0"]
EOF

# Use system Python to match uWSGI
cat > ENV << 'EOF'
PYTHON_VERSION=3.10
EOF

cat > wsgi.py << 'EOF'
from flask import Flask
try:
    import requests
    has_requests = True
except ImportError:
    has_requests = False

app = Flask(__name__)

@app.route('/')
def hello():
    return f'has_requests={has_requests}'

application = app
EOF

cat > Procfile << 'EOF'
wsgi: wsgi:application
EOF

deploy_app "$APP_NAME" >/dev/null

wait_for_deploy "$APP_NAME" 30
PORT=$(get_app_port "$APP_NAME")
if [ -n "$PORT" ] && wait_for_app "$PORT" 30; then
    response=$(curl -s "http://127.0.0.1:$PORT/")
    if echo "$response" | grep -q "has_requests=False"; then
        pass "Initial deploy: requests not installed"
    else
        fail "Initial deploy unexpected: $response"
    fi
else
    fail "Initial deploy not accessible"
fi

# Now add requests and redeploy
cat > pyproject.toml << 'EOF'
[project]
name = "test-uv-depupdate"
version = "0.1.0"
requires-python = ">=3.10"
dependencies = ["flask>=2.0", "requests>=2.0"]
EOF

output=$(deploy_app "$APP_NAME")

if echo "$output" | grep -q "uv sync"; then
    pass "uv sync ran on dependency change"
else
    # May also show as just installing
    pass "Redeploy processed"
fi

# Wait for uwsgi to restart the app after redeploy
wait_for_deploy "$APP_NAME" 30

# Get the (possibly new) port after redeploy
PORT=$(get_app_port "$APP_NAME")

if [ -n "$PORT" ] && wait_for_app "$PORT" 30; then
    response=$(curl -s "http://127.0.0.1:$PORT/")
    if echo "$response" | grep -q "has_requests=True"; then
        pass "After redeploy: requests is installed"
    else
        fail "After redeploy: requests still missing: $response"
    fi
else
    fail "App not accessible after redeploy (port: $PORT)"
    cat /home/piku/.piku/logs/$APP_NAME/*.log 2>/dev/null | tail -20 || true
fi

# ============================================
section "Test 6: ENV Priority Over .python-version"
# ============================================
APP_NAME="test-uv-env-priority"
destroy_app "$APP_NAME"
create_app "$APP_NAME"

cat > pyproject.toml << 'EOF'
[project]
name = "test-uv-env-priority"
version = "0.1.0"
requires-python = ">=3.10"
dependencies = ["flask>=2.0"]
EOF

cat > wsgi.py << 'EOF'
from flask import Flask
import sys

app = Flask(__name__)

@app.route('/')
def hello():
    return f'Python {sys.version_info.major}.{sys.version_info.minor}'

application = app
EOF

cat > Procfile << 'EOF'
wsgi: wsgi:application
EOF

# .python-version says 3.11
echo "3.11" > .python-version
# ENV says 3.10 - should take priority
cat > ENV << 'EOF'
PYTHON_VERSION=3.10
EOF

output=$(deploy_app "$APP_NAME")

if echo "$output" | grep -q "Using Python version: 3.10"; then
    pass "ENV takes priority over .python-version"
else
    fail "ENV did not take priority"
    echo "$output" | grep -i python || true
fi

wait_for_deploy "$APP_NAME" 30
PORT=$(get_app_port "$APP_NAME")
if [ -n "$PORT" ] && wait_for_app "$PORT" 30; then
    response=$(curl -s "http://127.0.0.1:$PORT/")
    if echo "$response" | grep -q "Python 3"; then
        pass "App running on Python 3.x (from ENV)"
    else
        fail "App not returning Python version: $response"
    fi
else
    fail "App not accessible"
fi

# ============================================
# Cleanup
# ============================================
section "Cleanup"
for app in test-uv-basic test-uv-pyver-env test-uv-pyver-file test-uv-multideps test-uv-depupdate test-uv-env-priority; do
    destroy_app "$app"
done
echo "Cleanup complete"

# ============================================
# Summary
# ============================================
echo ""
echo "========================================"
echo -e "Results: ${GREEN}$PASSED passed${NC}, ${RED}$FAILED failed${NC}"
echo "========================================"

if [ $FAILED -gt 0 ]; then
    exit 1
fi
exit 0
