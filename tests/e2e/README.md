# Piku E2E Test Suite

End-to-end tests for piku-bootstrap using a multi-container Docker architecture.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│  Docker Compose Network                                              │
│                                                                      │
│  ┌──────────────────────┐         ┌──────────────────────┐          │
│  │    test-client       │   SSH   │    piku-server       │          │
│  │                      │ ──────► │                      │          │
│  │  - Runs test scripts │         │  - Ubuntu 22.04      │          │
│  │  - git push to piku  │         │  - systemd           │          │
│  │  - HTTP validation   │         │  - piku-bootstrap    │          │
│  │                      │         │  - nginx + uwsgi     │          │
│  └──────────────────────┘         └──────────────────────┘          │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

This architecture tests the complete piku deployment flow:
1. Test client creates an app with appropriate files
2. Client pushes to piku via `git push piku@piku-server:app`
3. Piku detects the app type and deploys it
4. Client validates the app responds correctly via HTTP

## Quick Start

```bash
# Run all tests
cd tests/e2e
./run_e2e_tests.sh

# Run specific test suite
./run_e2e_tests.sh python_pip
./run_e2e_tests.sh nodejs

# Test with a custom piku fork
./run_e2e_tests.sh --piku-repo=myuser/piku --piku-branch=my-feature

# Keep containers running for debugging
./run_e2e_tests.sh --keep
```

## Test Suites

| Test File | Description | Tests |
|-----------|-------------|-------|
| `test_python_pip.sh` | Traditional Python with requirements.txt | 4 |
| `test_python_uv.sh` | Python with UV and pyproject.toml | 6 |
| `test_nodejs.sh` | Node.js with package.json | 4 |
| `test_piku_commands.sh` | Piku CLI commands (logs, config, restart, etc.) | 6 |

## Running Tests

### Prerequisites

- Docker and Docker Compose
- Bash shell

### Command Line Options

```
Usage: ./run_e2e_tests.sh [OPTIONS] [TEST_PATTERN]

OPTIONS:
    -h, --help              Show help message
    -k, --keep              Keep containers running after tests
    -n, --no-build          Skip Docker image build
    --piku-repo=REPO        GitHub repo to install piku from (default: piku/piku)
    --piku-branch=BRANCH    Branch to install from (default: master)

TEST_PATTERN:
    Filter which tests to run (e.g., "python", "nodejs", "commands")
```

### Examples

```bash
# Run all tests
./run_e2e_tests.sh

# Run only Node.js tests
./run_e2e_tests.sh nodejs

# Test a piku fork
PIKU_REPO=myuser/piku PIKU_BRANCH=feature-branch ./run_e2e_tests.sh

# Debug mode - keep containers running
./run_e2e_tests.sh --keep
docker exec -it piku-e2e-tests-test-client-1 bash
docker exec -it piku-e2e-tests-piku-server-1 bash
```

## Writing New Tests

### Test File Structure

Create a new file in `tests/` named `test_<category>.sh`:

```bash
#!/bin/bash
source /test-lib/test_helpers.sh

# Test function
test_my_feature() {
    local app_name="test-my-feature"
    
    # Create app
    local app_dir=$(create_app "$app_name")
    
    # Add app files
    echo "flask" > "$app_dir/requirements.txt"
    # ... more files ...
    
    # Deploy
    deploy_app "$app_name"
    wait_for_app "$app_name" 180
    
    # Validate
    test_http "$app_name" "expected content"
    
    # Cleanup
    local result=$?
    destroy_app "$app_name"
    return $result
}

# Run tests
run_test "My Feature" test_my_feature

# Report results
test_summary
```

### Available Helper Functions

| Function | Description |
|----------|-------------|
| `create_app <name>` | Create a new app directory and git repo |
| `deploy_app <name>` | Git push app to piku |
| `wait_for_app <name> [timeout]` | Wait for app to be ready |
| `test_http <name> <expected> [path]` | Test HTTP response |
| `destroy_app <name>` | Remove app from piku |
| `run_piku <command>` | Run a piku command via SSH |
| `ssh_server <command>` | Run a command on the server |
| `run_test <name> <function>` | Execute a test function |
| `test_summary` | Print results and exit |

### App Template Helpers

| Function | Description |
|----------|-------------|
| `create_flask_app <dir> [extra_deps]` | Flask + requirements.txt |
| `create_uv_flask_app <dir> [python_ver]` | Flask + pyproject.toml |
| `create_node_app <dir> [node_ver]` | Express + package.json |

## Debugging

### Container Access

When running with `--keep`, you can access the containers:

```bash
# Access test client
docker exec -it piku-e2e-tests-test-client-1 bash

# Access piku server
docker exec -it piku-e2e-tests-piku-server-1 bash

# View logs
docker compose -p piku-e2e-tests logs -f

# Clean up manually
docker compose -p piku-e2e-tests down -v
```

### Server Inspection

```bash
# On piku-server
systemctl status uwsgi-piku
systemctl status nginx
cat /home/piku/.piku/uwsgi-enabled/*.ini
ls -la /home/piku/.piku/apps/
```

### Common Issues

1. **Timeout waiting for piku-server**: The bootstrap process can take 3-5 minutes. Increase timeout or check server logs.

2. **SSH connection refused**: Ensure the SSH key is correctly shared via the Docker volume.

3. **App not responding**: Check uwsgi logs with `run_piku logs <app>` or inspect the uwsgi config.

## CI Integration

The tests run automatically in GitHub Actions on:
- Push to main
- Pull requests to main
- Manual trigger via workflow_dispatch

See `.github/workflows/e2e-full.yml` for the workflow configuration.

### Manual Trigger

You can trigger tests manually with custom parameters:
1. Go to Actions → E2E Full Test Suite
2. Click "Run workflow"
3. Enter custom piku_repo, piku_branch, or test_filter
