#!/bin/bash
# Test Node.js deployments with package.json
source /test-lib/test_helpers.sh

#######################################
# Test 1: Basic Express app
#######################################
test_basic_express() {
    local app_name="test-node-basic"
    
    log_info "Creating basic Express app..."
    local app_dir=$(create_app "$app_name")
    create_node_app "$app_dir"
    
    log_info "Deploying app..."
    deploy_app "$app_name"
    
    log_info "Waiting for app to be ready..."
    wait_for_app "$app_name" 180
    sleep 10  # Node apps may need more startup time
    
    log_info "Testing HTTP response..."
    test_http "$app_name" "Hello from Node.js"
    
    local result=$?
    destroy_app "$app_name"
    return $result
}

#######################################
# Test 2: Express app with multiple npm dependencies
#######################################
test_node_with_deps() {
    local app_name="test-node-deps"
    
    log_info "Creating Express app with dependencies..."
    local app_dir=$(create_app "$app_name")
    
    cat > "$app_dir/package.json" << 'EOF'
{
  "name": "test-app-deps",
  "version": "1.0.0",
  "main": "index.js",
  "scripts": {
    "start": "node index.js"
  },
  "dependencies": {
    "express": "^4.18.0",
    "lodash": "^4.17.21",
    "moment": "^2.29.0"
  }
}
EOF

    cat > "$app_dir/index.js" << 'EOF'
const express = require('express');
const _ = require('lodash');
const moment = require('moment');

const app = express();
const port = process.env.PORT || 3000;

app.get('/', (req, res) => {
  const arr = [1, 2, 3];
  res.send(`Sum: ${_.sum(arr)}, Time: ${moment().format('YYYY-MM-DD')}`);
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

    cat > "$app_dir/ENV" << EOF
NGINX_SERVER_NAME=$app_name
EOF
    
    log_info "Deploying app..."
    deploy_app "$app_name"
    wait_for_app "$app_name" 180
    sleep 10
    
    log_info "Testing HTTP response..."
    test_http "$app_name" "Sum: 6"
    
    local result=$?
    destroy_app "$app_name"
    return $result
}

#######################################
# Test 3: Node version via .nvmrc
#######################################
test_node_version_nvmrc() {
    local app_name="test-node-nvmrc"
    
    log_info "Creating Express app with .nvmrc..."
    local app_dir=$(create_app "$app_name")
    create_node_app "$app_dir"
    
    # Add .nvmrc
    echo "18" > "$app_dir/.nvmrc"
    
    # Modify to show Node version
    cat > "$app_dir/index.js" << 'EOF'
const express = require('express');
const app = express();
const port = process.env.PORT || 3000;

app.get('/', (req, res) => {
  res.send(`Node ${process.version}`);
});

app.listen(port, '0.0.0.0');
EOF
    
    log_info "Deploying app..."
    deploy_app "$app_name"
    wait_for_app "$app_name" 180
    sleep 10
    
    log_info "Testing HTTP response..."
    test_http "$app_name" "Node v"
    
    local result=$?
    destroy_app "$app_name"
    return $result
}

#######################################
# Test 4: Node version via engines in package.json
#######################################
test_node_version_engines() {
    local app_name="test-node-engines"
    
    log_info "Creating Express app with engines specification..."
    local app_dir=$(create_app "$app_name")
    
    cat > "$app_dir/package.json" << 'EOF'
{
  "name": "test-app-engines",
  "version": "1.0.0",
  "main": "index.js",
  "scripts": {
    "start": "node index.js"
  },
  "dependencies": {
    "express": "^4.18.0"
  },
  "engines": {
    "node": ">=18.0.0"
  }
}
EOF

    cat > "$app_dir/index.js" << 'EOF'
const express = require('express');
const app = express();
const port = process.env.PORT || 3000;

app.get('/', (req, res) => {
  res.send(`Engines test: Node ${process.version}`);
});

app.listen(port, '0.0.0.0');
EOF

    cat > "$app_dir/Procfile" << 'EOF'
web: node index.js
EOF

    cat > "$app_dir/ENV" << EOF
NGINX_SERVER_NAME=$app_name
EOF
    
    log_info "Deploying app..."
    deploy_app "$app_name"
    wait_for_app "$app_name" 180
    sleep 10
    
    log_info "Testing HTTP response..."
    test_http "$app_name" "Engines test"
    
    local result=$?
    destroy_app "$app_name"
    return $result
}

#######################################
# Run all tests
#######################################
run_test "Basic Express app" test_basic_express
run_test "Express with npm dependencies" test_node_with_deps
run_test "Node version via .nvmrc" test_node_version_nvmrc
run_test "Node version via engines" test_node_version_engines

test_summary
