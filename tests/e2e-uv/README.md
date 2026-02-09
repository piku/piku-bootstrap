# E2E Tests for UV-based Python Deployments

This directory contains end-to-end tests that validate piku-bootstrap correctly installs piku with UV support, and that UV-based Python app deployments work correctly.

## Prerequisites

- Docker with systemd support
- A machine capable of running Docker containers

## Running the Tests

```bash
./run_tests.sh
```

This will:
1. Build a Docker image based on Ubuntu 22.04 with systemd
2. Start the container with systemd running
3. Run `piku-bootstrap install` to set up piku
4. Install UV for the piku user
5. Execute 6 comprehensive E2E tests

## Test Cases

### Test 1: Basic UV Deployment
Validates that an app with `pyproject.toml` is detected as a UV-based Python app and deploys correctly.

### Test 2: Python Version via ENV
Validates that setting `PYTHON_VERSION` in the app's `ENV` file is respected during deployment.

### Test 3: Python Version via .python-version
Validates that a `.python-version` file in the app root is read and used to select the Python version.

### Test 4: Multiple Dependencies
Validates that multiple dependencies (flask, requests, click) are correctly installed via UV.

### Test 5: Dependency Update on Redeploy
Validates that adding new dependencies to `pyproject.toml` and redeploying correctly installs the new dependencies.

### Test 6: ENV Priority Over .python-version
Validates that `PYTHON_VERSION` in `ENV` takes priority over `.python-version` file when both are present.

## Testing with Custom Piku Fork/Branch

The tests support configuration via environment variables:

```bash
# Default: uses clusterfudge/piku with UV fixes
./run_tests.sh

# Use a custom fork/branch:
PIKU_REPO=your-username/piku PIKU_BRANCH=your-branch ./run_tests.sh

# Once UV fixes are merged upstream:
PIKU_REPO=piku/piku PIKU_BRANCH=master ./run_tests.sh
```

## CI Integration

The E2E tests run automatically on GitHub Actions via `.github/workflows/e2e-uv.yml`. The workflow:
- Triggers on push/PR to main branch
- Uses Docker-in-Docker to run systemd containers
- Currently uses `clusterfudge/piku` with UV fixes until merged upstream

## Debugging Test Failures

If tests fail, you can:

1. **Keep the container running** by commenting out the cleanup at the end of `run_tests.sh`
2. **SSH into the container**:
   ```bash
   docker exec -it piku-e2e-test bash
   ```
3. **Check piku logs**:
   ```bash
   cat /home/piku/.piku/logs/<app_name>/*.log
   ```
4. **Manually run the test script**:
   ```bash
   docker exec piku-e2e-test /root/test_uv_e2e.sh
   ```

## Test Infrastructure

- **Dockerfile**: Ubuntu 22.04 with systemd support (jrei/systemd-ubuntu)
- **run_tests.sh**: Master orchestrator that builds, starts, and runs tests
- **test_uv_e2e.sh**: The actual test script that runs inside the container

## Known Issues

- GitHub's raw.githubusercontent.com has a 5-minute CDN cache, which can cause stale piku.py to be downloaded during development. The playbook now uses `force: yes` to mitigate this.
- The test container requires systemd for proper piku operation (uwsgi, nginx, etc.)
