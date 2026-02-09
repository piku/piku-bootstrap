#!/bin/bash
# Test Python UV deployments with pyproject.toml
# Migrated from original test_uv_e2e.sh
source /test-lib/test_helpers.sh

#######################################
# Test 1: Basic UV deployment
#######################################
test_basic_uv() {
    local app_name="test-uv-basic"
    
    log_info "Creating basic UV Flask app..."
    local app_dir=$(create_app "$app_name")
    create_uv_flask_app "$app_dir" "3.10"
    
    log_info "Deploying app..."
    deploy_app "$app_name"
    
    log_info "Waiting for app to be ready..."
    wait_for_app "$app_name" 180
    sleep 5
    
    log_info "Testing HTTP response..."
    test_http "$app_name" "Hello from UV Flask"
    
    local result=$?
    destroy_app "$app_name"
    return $result
}

#######################################
# Test 2: Python version via ENV file
#######################################
test_uv_python_version_env() {
    local app_name="test-uv-env"
    
    log_info "Creating UV app with PYTHON_VERSION in ENV..."
    local app_dir=$(create_app "$app_name")
    
    cat > "$app_dir/pyproject.toml" << 'EOF'
[project]
name = "test-app"
version = "0.1.0"
requires-python = ">=3.10"
dependencies = ["flask"]
EOF

    cat > "$app_dir/wsgi.py" << 'EOF'
from flask import Flask
import sys
app = Flask(__name__)

@app.route('/')
def hello():
    return f'Python {sys.version_info.major}.{sys.version_info.minor}'

application = app
EOF

    cat > "$app_dir/Procfile" << 'EOF'
wsgi: wsgi:app
EOF

    cat > "$app_dir/ENV" << EOF
PYTHON_VERSION=3.10
NGINX_SERVER_NAME=$app_name
EOF
    
    log_info "Deploying app..."
    deploy_app "$app_name"
    wait_for_app "$app_name" 180
    sleep 5
    
    log_info "Testing HTTP response..."
    test_http "$app_name" "Python 3.10"
    
    local result=$?
    destroy_app "$app_name"
    return $result
}

#######################################
# Test 3: Python version via .python-version
#######################################
test_uv_python_version_file() {
    local app_name="test-uv-pyver"
    
    log_info "Creating UV app with .python-version file..."
    local app_dir=$(create_app "$app_name")
    
    cat > "$app_dir/pyproject.toml" << 'EOF'
[project]
name = "test-app"
version = "0.1.0"
requires-python = ">=3.10"
dependencies = ["flask"]
EOF

    cat > "$app_dir/wsgi.py" << 'EOF'
from flask import Flask
import sys
app = Flask(__name__)

@app.route('/')
def hello():
    return f'Python {sys.version_info.major}.{sys.version_info.minor}'

application = app
EOF

    cat > "$app_dir/Procfile" << 'EOF'
wsgi: wsgi:app
EOF

    echo "3.10" > "$app_dir/.python-version"

    cat > "$app_dir/ENV" << EOF
NGINX_SERVER_NAME=$app_name
EOF
    
    log_info "Deploying app..."
    deploy_app "$app_name"
    wait_for_app "$app_name" 180
    sleep 5
    
    log_info "Testing HTTP response..."
    test_http "$app_name" "Python 3.10"
    
    local result=$?
    destroy_app "$app_name"
    return $result
}

#######################################
# Test 4: Multiple dependencies
#######################################
test_uv_multiple_deps() {
    local app_name="test-uv-deps"
    
    log_info "Creating UV app with multiple dependencies..."
    local app_dir=$(create_app "$app_name")
    
    cat > "$app_dir/pyproject.toml" << 'EOF'
[project]
name = "test-app"
version = "0.1.0"
requires-python = ">=3.10"
dependencies = [
    "flask",
    "requests",
    "click",
]
EOF

    cat > "$app_dir/wsgi.py" << 'EOF'
from flask import Flask
import requests
import click
app = Flask(__name__)

@app.route('/')
def hello():
    return f'UV deps: requests={requests.__version__}, click={click.__version__}'

application = app
EOF

    cat > "$app_dir/Procfile" << 'EOF'
wsgi: wsgi:app
EOF

    cat > "$app_dir/ENV" << EOF
PYTHON_VERSION=3.10
NGINX_SERVER_NAME=$app_name
EOF
    
    log_info "Deploying app..."
    deploy_app "$app_name"
    wait_for_app "$app_name" 180
    sleep 5
    
    log_info "Testing HTTP response..."
    test_http "$app_name" "requests="
    
    local result=$?
    destroy_app "$app_name"
    return $result
}

#######################################
# Test 5: Dependency update on redeploy
#######################################
test_uv_redeploy() {
    local app_name="test-uv-redeploy"
    
    log_info "Creating initial UV app..."
    local app_dir=$(create_app "$app_name")
    
    cat > "$app_dir/pyproject.toml" << 'EOF'
[project]
name = "test-app"
version = "0.1.0"
requires-python = ">=3.10"
dependencies = ["flask"]
EOF

    cat > "$app_dir/wsgi.py" << 'EOF'
from flask import Flask
app = Flask(__name__)

@app.route('/')
def hello():
    try:
        import requests
        return f'Has requests: {requests.__version__}'
    except ImportError:
        return 'No requests'

application = app
EOF

    cat > "$app_dir/Procfile" << 'EOF'
wsgi: wsgi:app
EOF

    cat > "$app_dir/ENV" << EOF
PYTHON_VERSION=3.10
NGINX_SERVER_NAME=$app_name
EOF
    
    log_info "First deploy (without requests)..."
    deploy_app "$app_name"
    wait_for_app "$app_name" 180
    sleep 5
    
    test_http "$app_name" "No requests"
    
    log_info "Adding requests dependency and redeploying..."
    cat > "$app_dir/pyproject.toml" << 'EOF'
[project]
name = "test-app"
version = "0.1.0"
requires-python = ">=3.10"
dependencies = ["flask", "requests"]
EOF
    
    deploy_app "$app_name"
    sleep 10  # Wait for redeploy
    
    log_info "Testing after redeploy..."
    test_http "$app_name" "Has requests"
    
    local result=$?
    destroy_app "$app_name"
    return $result
}

#######################################
# Test 6: ENV takes priority over .python-version
#######################################
test_uv_env_priority() {
    local app_name="test-uv-priority"
    
    log_info "Creating UV app with both ENV and .python-version..."
    local app_dir=$(create_app "$app_name")
    
    cat > "$app_dir/pyproject.toml" << 'EOF'
[project]
name = "test-app"
version = "0.1.0"
requires-python = ">=3.10"
dependencies = ["flask"]
EOF

    cat > "$app_dir/wsgi.py" << 'EOF'
from flask import Flask
import sys
app = Flask(__name__)

@app.route('/')
def hello():
    return f'Python {sys.version_info.major}.{sys.version_info.minor}'

application = app
EOF

    cat > "$app_dir/Procfile" << 'EOF'
wsgi: wsgi:app
EOF

    # .python-version says 3.10
    echo "3.10" > "$app_dir/.python-version"

    cat > "$app_dir/ENV" << EOF
NGINX_SERVER_NAME=$app_name
EOF
    
    # ENV says 3.10 - this should take priority
    cat > "$app_dir/ENV" << EOF
PYTHON_VERSION=3.10
NGINX_SERVER_NAME=$app_name
EOF
    
    log_info "Deploying app..."
    deploy_app "$app_name"
    wait_for_app "$app_name" 180
    sleep 5
    
    log_info "Testing that ENV takes priority (expecting 3.10)..."
    test_http "$app_name" "Python 3.10"
    
    local result=$?
    destroy_app "$app_name"
    return $result
}

#######################################
# Run all tests
#######################################
run_test "Basic UV deployment" test_basic_uv
run_test "Python version via ENV" test_uv_python_version_env
run_test "Python version via .python-version" test_uv_python_version_file
run_test "Multiple UV dependencies" test_uv_multiple_deps
run_test "Dependency update on redeploy" test_uv_redeploy
run_test "ENV priority over .python-version" test_uv_env_priority

test_summary
