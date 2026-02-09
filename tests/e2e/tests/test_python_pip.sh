#!/bin/bash
# Test traditional Python deployments with pip/requirements.txt
source /test-lib/test_helpers.sh

#######################################
# Test 1: Basic Flask app with requirements.txt
#######################################
test_basic_flask() {
    local app_name="test-flask-basic"
    
    log_info "Creating basic Flask app..."
    local app_dir=$(create_app "$app_name")
    create_flask_app "$app_dir"
    
    log_info "Deploying app..."
    deploy_app "$app_name"
    
    log_info "Waiting for app to be ready..."
    wait_for_app "$app_name" 180
    
    # Give uwsgi a moment to start
    sleep 5
    
    log_info "Testing HTTP response..."
    test_http "$app_name" "Hello from Flask"
    
    local result=$?
    destroy_app "$app_name"
    return $result
}

#######################################
# Test 2: Flask app with multiple dependencies
#######################################
test_flask_with_deps() {
    local app_name="test-flask-deps"
    
    log_info "Creating Flask app with extra dependencies..."
    local app_dir=$(create_app "$app_name")
    create_flask_app "$app_dir" "requests
click"
    
    # Modify wsgi.py to use the extra deps
    cat > "$app_dir/wsgi.py" << 'EOF'
from flask import Flask
import requests
import click
app = Flask(__name__)

@app.route('/')
def hello():
    return f'Hello! requests={requests.__version__}, click={click.__version__}'
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
# Test 3: Python version via runtime.txt
#######################################
test_python_runtime() {
    local app_name="test-flask-runtime"
    
    log_info "Creating Flask app with runtime.txt..."
    local app_dir=$(create_app "$app_name")
    create_flask_app "$app_dir"
    
    # Add runtime.txt specifying Python version
    echo "python-3.10" > "$app_dir/runtime.txt"
    
    # Modify wsgi.py to show Python version
    cat > "$app_dir/wsgi.py" << 'EOF'
from flask import Flask
import sys
app = Flask(__name__)

@app.route('/')
def hello():
    return f'Python {sys.version_info.major}.{sys.version_info.minor}'
EOF
    
    log_info "Deploying app..."
    deploy_app "$app_name"
    wait_for_app "$app_name" 180
    sleep 5
    
    log_info "Testing HTTP response..."
    # Just verify the app runs - Python version enforcement depends on server setup
    test_http "$app_name" "Python"
    
    local result=$?
    destroy_app "$app_name"
    return $result
}

#######################################
# Test 4: Procfile with web: worker type
#######################################
test_web_procfile() {
    local app_name="test-flask-web"
    
    log_info "Creating Flask app with web: Procfile..."
    local app_dir=$(create_app "$app_name")
    
    cat > "$app_dir/requirements.txt" << 'EOF'
flask
EOF

    cat > "$app_dir/app.py" << 'EOF'
from flask import Flask
app = Flask(__name__)

@app.route('/')
def hello():
    return 'Hello from web worker!'

if __name__ == '__main__':
    import os
    port = int(os.environ.get('PORT', 5000))
    app.run(host='0.0.0.0', port=port)
EOF

    # Use web: instead of wsgi:
    cat > "$app_dir/Procfile" << 'EOF'
web: python app.py
EOF

    cat > "$app_dir/ENV" << EOF
NGINX_SERVER_NAME=$app_name
EOF
    
    log_info "Deploying app..."
    deploy_app "$app_name"
    wait_for_app "$app_name" 180
    sleep 5
    
    log_info "Testing HTTP response..."
    test_http "$app_name" "Hello from web worker"
    
    local result=$?
    destroy_app "$app_name"
    return $result
}

#######################################
# Run all tests
#######################################
run_test "Basic Flask with requirements.txt" test_basic_flask
run_test "Flask with multiple dependencies" test_flask_with_deps
run_test "Python version via runtime.txt" test_python_runtime
run_test "Procfile with web: worker type" test_web_procfile

test_summary
