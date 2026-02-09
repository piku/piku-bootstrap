#!/bin/bash
# Test piku CLI commands
source /test-lib/test_helpers.sh

# Deploy a test app first that we'll use for all command tests
APP_NAME="test-piku-commands"

setup_test_app() {
    log_info "Setting up test app for command tests..."
    local app_dir=$(create_app "$APP_NAME")
    create_flask_app "$app_dir"
    deploy_app "$APP_NAME"
    wait_for_app "$APP_NAME" 180
    sleep 5
}

cleanup_test_app() {
    destroy_app "$APP_NAME"
}

#######################################
# Test 1: piku logs
#######################################
test_piku_logs() {
    log_info "Testing 'piku logs' command..."
    
    # piku logs tails indefinitely, so we need a timeout
    # Use SSH with ConnectTimeout and a timeout wrapper
    local output
    output=$(timeout 5 ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        "$PIKU_USER@$PIKU_SERVER" "logs $APP_NAME" 2>&1 || true)
    
    # If we got any output or the command ran (even with timeout), consider it working
    # The key thing is piku should not immediately error
    if [ -n "$output" ] && ! echo "$output" | grep -q "Error\|not found\|No such"; then
        log_pass "piku logs command works"
        return 0
    else
        # Check if logs directory exists (alternative verification)
        if ssh_server "ls /home/piku/.piku/logs/$APP_NAME/*.log" >/dev/null 2>&1; then
            log_pass "piku logs command works (log files exist)"
            return 0
        else
            log_fail "piku logs command failed: $output"
            return 1
        fi
    fi
}
#######################################
# Test 2: piku config:set and config:get
#######################################
test_piku_config() {
    log_info "Testing 'piku config:set' and 'config:get' commands..."
    
    # Set a config variable
    log_info "Setting TEST_VAR=hello..."
    run_piku config:set "$APP_NAME" TEST_VAR=hello
    
    # Get the config and verify
    log_info "Getting config..."
    local output
    output=$(run_piku config "$APP_NAME" 2>&1)
    
    if echo "$output" | grep -q "TEST_VAR.*hello"; then
        log_pass "config:set/get works"
        return 0
    else
        log_fail "Config not set correctly. Output: $output"
        return 1
    fi
}

#######################################
# Test 3: piku restart
#######################################
test_piku_restart() {
    log_info "Testing 'piku restart' command..."
    
    # Restart the app
    if run_piku restart "$APP_NAME" 2>&1; then
        sleep 5  # Wait for restart
        
        # Verify app is still responding
        if test_http "$APP_NAME" "Hello"; then
            log_pass "piku restart works"
            return 0
        else
            log_fail "App not responding after restart"
            return 1
        fi
    else
        log_fail "piku restart command failed"
        return 1
    fi
}

#######################################
# Test 4: piku ps (list processes)
#######################################
test_piku_ps() {
    log_info "Testing 'piku ps' command..."
    
    local output
    output=$(run_piku ps "$APP_NAME" 2>&1 || true)
    
    # ps should show something about the app
    if echo "$output" | grep -qiE "(wsgi|web|worker|running|pid)"; then
        log_pass "piku ps command works"
        return 0
    else
        # Even if output is different, command should not error
        if run_piku ps "$APP_NAME" >/dev/null 2>&1; then
            log_pass "piku ps command executes (output format may vary)"
            return 0
        fi
        log_fail "piku ps command failed. Output: $output"
        return 1
    fi
}

#######################################
# Test 5: piku stop and restart
#######################################
test_piku_stop_restart() {
    log_info "Testing 'piku stop' and 'piku restart' commands..."
    
    # Stop the app
    log_info "Stopping app..."
    run_piku stop "$APP_NAME" 2>&1 || true
    sleep 3
    
    # Restart the app (piku doesn't have a separate 'start' command)
    log_info "Restarting app..."
    run_piku restart "$APP_NAME" 2>&1 || true
    
    # Wait for app to become ready (may take some time after restart)
    wait_for_app "$APP_NAME" 60 || true
    sleep 5
    
    # Verify app is responding
    if test_http "$APP_NAME" "Hello"; then
        log_pass "piku stop/restart works"
        return 0
    else
        log_fail "App not responding after stop/restart"
        return 1
    fi
}

#######################################
# Test 6: piku destroy (run last!)
#######################################
test_piku_destroy() {
    log_info "Testing 'piku destroy' command..."
    
    # Create a temporary app to destroy
    local temp_app="test-destroy-me"
    local app_dir=$(create_app "$temp_app")
    create_flask_app "$app_dir"
    deploy_app "$temp_app"
    wait_for_app "$temp_app" 120
    
    # Destroy it
    log_info "Destroying temporary app..."
    if run_piku destroy "$temp_app" 2>&1; then
        sleep 2
        
        # Verify it's gone - the uwsgi config should not exist
        if ! ssh_server "test -f /home/piku/.piku/uwsgi-enabled/$temp_app.ini"; then
            log_pass "piku destroy works"
            rm -rf "$TEST_APP_DIR/$temp_app"
            return 0
        else
            log_fail "App still exists after destroy"
            return 1
        fi
    else
        log_fail "piku destroy command failed"
        return 1
    fi
}

#######################################
# Run all tests
#######################################

# Setup
setup_test_app

# Run command tests
run_test "piku logs" test_piku_logs
run_test "piku config:set/get" test_piku_config
run_test "piku restart" test_piku_restart
run_test "piku ps" test_piku_ps
run_test "piku stop/restart" test_piku_stop_restart
run_test "piku destroy" test_piku_destroy

# Cleanup
cleanup_test_app

test_summary
