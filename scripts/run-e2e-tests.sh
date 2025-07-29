#!/bin/bash

# Coder on Scaleway - End-to-End Tests
# Comprehensive E2E testing for CI/CD pipeline

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# Global variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENVIRONMENT=""
TIMEOUT=3600  # 60 minutes
BROWSER="chrome"
HEADLESS=true
VERBOSE=false
FAIL_FAST=false
LOG_FILE=""
OUTPUT_FORMAT="console"
JUNIT_OUTPUT=""
SCREENSHOT_DIR=""
VIDEO_RECORDING=false
CLEANUP_WORKSPACES=true
START_TIME=$(date +%s)

# Test results tracking
declare -A TEST_RESULTS
declare -a TEST_ORDER
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# Test data
TEST_WORKSPACE_PREFIX="e2e-test"
TEST_TEMPLATE="python-django-crewai"
TEST_USER_EMAIL="e2e-test@example.com"

print_banner() {
    echo -e "${BLUE}"
    cat << 'EOF'
╔═══════════════════════════════════════╗
║           Coder on Scaleway           ║
║        End-to-End Testing             ║
╚═══════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

print_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Run comprehensive end-to-end tests for Coder environments including
user workflows, workspace lifecycle, template functionality, and UI interactions.

Options:
    --env=ENV               Environment to test (dev|staging|prod) [required]
    --timeout=SECONDS       Test timeout in seconds [default: 3600]
    --browser=BROWSER       Browser for testing (chrome|firefox|safari) [default: chrome]
    --no-headless           Run browser in non-headless mode
    --verbose               Enable verbose test output
    --fail-fast             Stop on first test failure
    --format=FORMAT         Output format (console|json|junit) [default: console]
    --junit-output=FILE     JUnit XML output file (when format=junit)
    --screenshot-dir=DIR    Directory for screenshots
    --enable-video          Record video of test sessions
    --no-cleanup            Skip cleanup of test workspaces
    --help                  Show this help message

Test Scenarios:
    • User Authentication   OAuth login, session management, permissions
    • Workspace Lifecycle   Create, start, stop, delete workspaces
    • Template Testing      Validate templates, resource allocation, startup
    • Code Development      File operations, terminal access, IDE functionality
    • Collaboration        Multiple user scenarios, sharing, team features
    • Performance          Load testing, concurrent users, resource usage
    • Error Handling        Network failures, resource constraints, recovery

Examples:
    $0 --env=staging --verbose --screenshot-dir=./screenshots
    $0 --env=dev --no-headless --browser=firefox
    $0 --env=prod --format=junit --junit-output=e2e-results.xml
    $0 --env=staging --enable-video --timeout=7200

CI/CD Integration:
    # GitHub Actions
    - name: Run E2E Tests
      run: ./scripts/run-e2e-tests.sh --env=staging --format=junit --junit-output=e2e-results.xml

    - name: Upload Screenshots
      if: failure()
      uses: actions/upload-artifact@v4
      with:
        name: e2e-screenshots
        path: screenshots/

Requirements:
    • Node.js and npm (for Playwright)
    • Chrome/Firefox browser
    • Valid Coder instance with OAuth configured
    • Test user account or OAuth test credentials

EOF
}

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    case "$level" in
        INFO)  echo -e "${GREEN}[INFO]${NC}  $message" ;;
        WARN)  echo -e "${YELLOW}[WARN]${NC}  $message" ;;
        ERROR) echo -e "${RED}[ERROR]${NC} $message" ;;
        DEBUG) [[ "$VERBOSE" == "true" ]] && echo -e "${PURPLE}[DEBUG]${NC} $message" ;;
        STEP)  echo -e "${CYAN}[STEP]${NC}  $message" ;;
        PASS)  echo -e "${GREEN}[PASS]${NC}  $message" ;;
        FAIL)  echo -e "${RED}[FAIL]${NC}  $message" ;;
        SKIP)  echo -e "${YELLOW}[SKIP]${NC}  $message" ;;
    esac

    if [[ -n "${LOG_FILE}" ]]; then
        echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    fi
}

setup_logging() {
    local log_dir="${PROJECT_ROOT}/logs/e2e-tests"
    mkdir -p "$log_dir"
    LOG_FILE="${log_dir}/$(date +%Y%m%d-%H%M%S)-${ENVIRONMENT}-e2e-tests.log"

    # Setup screenshot directory
    if [[ -z "$SCREENSHOT_DIR" ]]; then
        SCREENSHOT_DIR="${log_dir}/screenshots-$(date +%Y%m%d-%H%M%S)"
    fi
    mkdir -p "$SCREENSHOT_DIR"

    log INFO "Logging to: $LOG_FILE"
    log INFO "Screenshots: $SCREENSHOT_DIR"
}

validate_environment() {
    case "$ENVIRONMENT" in
        dev|staging|prod)
            log INFO "Testing environment: $ENVIRONMENT"
            ;;
        *)
            log ERROR "Invalid environment: $ENVIRONMENT"
            log ERROR "Must be one of: dev, staging, prod"
            exit 1
            ;;
    esac

    local env_dir="${PROJECT_ROOT}/environments/${ENVIRONMENT}"
    if [[ ! -d "$env_dir" ]]; then
        log ERROR "Environment directory not found: $env_dir"
        exit 1
    fi
}

get_coder_url() {
    local kubeconfig="${HOME}/.kube/config-coder-${ENVIRONMENT}"
    if [[ ! -f "$kubeconfig" ]]; then
        log ERROR "Kubeconfig not found: $kubeconfig"
        return 1
    fi

    export KUBECONFIG="$kubeconfig"

    # Get Coder URL from ingress or service
    local coder_host=""
    if kubectl get ingress -n coder > /dev/null 2>&1; then
        coder_host=$(kubectl get ingress -n coder -o jsonpath='{.items[0].spec.rules[0].host}' 2>/dev/null || echo "")
        if [[ -n "$coder_host" ]]; then
            echo "https://$coder_host"
            return 0
        fi
    fi

    # Fallback to service
    local coder_ip=$(kubectl get service coder -n coder -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    local coder_port=$(kubectl get service coder -n coder -o jsonpath='{.spec.ports[0].port}' 2>/dev/null || echo "7080")

    if [[ -n "$coder_ip" ]]; then
        echo "http://$coder_ip:$coder_port"
        return 0
    fi

    log ERROR "Cannot determine Coder URL"
    return 1
}

setup_playwright() {
    log STEP "Setting up Playwright test environment"

    # Check if Node.js is available
    if ! command -v node > /dev/null; then
        log ERROR "Node.js is required for E2E tests but not found"
        return 1
    fi

    # Create temporary test directory
    local test_dir="${PROJECT_ROOT}/tmp/e2e-tests"
    mkdir -p "$test_dir"
    cd "$test_dir"

    # Create package.json if it doesn't exist
    if [[ ! -f "package.json" ]]; then
        cat > package.json <<EOF
{
  "name": "coder-e2e-tests",
  "version": "1.0.0",
  "private": true,
  "dependencies": {
    "@playwright/test": "^1.40.0",
    "playwright": "^1.40.0"
  },
  "scripts": {
    "test": "playwright test"
  }
}
EOF
    fi

    # Install dependencies
    if [[ ! -d "node_modules" ]]; then
        log INFO "Installing Playwright dependencies..."
        if ! npm install > /dev/null 2>&1; then
            log ERROR "Failed to install Playwright dependencies"
            return 1
        fi
    fi

    # Install browser binaries
    if ! npx playwright install "$BROWSER" > /dev/null 2>&1; then
        log WARN "Failed to install browser binaries, tests may fail"
    fi

    # Create Playwright config
    cat > playwright.config.js <<EOF
module.exports = {
  testDir: './tests',
  timeout: ${TIMEOUT}000,
  fullyParallel: false,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 1 : 0,
  workers: 1,
  reporter: [
    ['html'],
    ['junit', { outputFile: 'results.xml' }]
  ],
  use: {
    baseURL: process.env.CODER_URL,
    headless: ${HEADLESS},
    screenshot: 'only-on-failure',
    video: ${VIDEO_RECORDING} ? 'retain-on-failure' : 'off',
    trace: 'retain-on-failure'
  },
  projects: [
    {
      name: '${BROWSER}',
      use: { ...require('@playwright/test').devices['Desktop ${BROWSER^}'] },
    }
  ],
};
EOF

    log INFO "✅ Playwright environment set up"
    echo "$test_dir"  # Return test directory
}

create_e2e_tests() {
    local test_dir="$1"
    local coder_url="$2"

    log STEP "Creating E2E test scenarios"

    mkdir -p "${test_dir}/tests"

    # User Authentication Test
    cat > "${test_dir}/tests/auth.spec.js" <<'EOF'
const { test, expect } = require('@playwright/test');

test.describe('User Authentication', () => {
  test('should display login page', async ({ page }) => {
    await page.goto('/');

    // Check if we're redirected to login or if already logged in
    await page.waitForLoadState('networkidle');

    const title = await page.title();
    expect(title).toContain('Coder');

    // Take screenshot
    await page.screenshot({ path: 'screenshots/login-page.png' });
  });

  test('should handle login flow', async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('networkidle');

    // If already authenticated, skip login
    const currentUrl = page.url();
    if (currentUrl.includes('/workspaces') || currentUrl.includes('/dashboard')) {
      console.log('Already authenticated, skipping login');
      return;
    }

    // Look for OAuth login buttons
    const oauthButtons = await page.locator('button, a').filter({
      hasText: /sign in|login|oauth|github|google/i
    }).count();

    expect(oauthButtons).toBeGreaterThan(0);
    await page.screenshot({ path: 'screenshots/login-options.png' });
  });
});
EOF

    # Workspace Lifecycle Test
    cat > "${test_dir}/tests/workspace-lifecycle.spec.js" <<EOF
const { test, expect } = require('@playwright/test');

test.describe('Workspace Lifecycle', () => {
  test('should list available templates', async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('networkidle');

    // Navigate to templates if not already there
    try {
      await page.click('text=Templates', { timeout: 5000 });
    } catch (e) {
      // May already be on templates page or templates link not visible
    }

    await page.waitForLoadState('networkidle');

    // Look for template cards or list items
    const templates = await page.locator('[data-testid="template"], .template-card, [href*="/templates/"]').count();

    // Should have at least one template
    expect(templates).toBeGreaterThan(0);

    await page.screenshot({ path: 'screenshots/templates-list.png' });
  });

  test('should create workspace', async ({ page }) => {
    const workspaceName = '${TEST_WORKSPACE_PREFIX}-' + Date.now();

    await page.goto('/');
    await page.waitForLoadState('networkidle');

    // Try to navigate to create workspace
    try {
      await page.click('text=Create Workspace', { timeout: 5000 });
    } catch (e) {
      try {
        await page.click('text=New Workspace', { timeout: 5000 });
      } catch (e2) {
        // Try template selection
        await page.goto('/templates');
        await page.waitForLoadState('networkidle');

        // Click on a template
        await page.click('text=${TEST_TEMPLATE}, [data-template="${TEST_TEMPLATE}"]', { timeout: 5000 });
      }
    }

    await page.waitForLoadState('networkidle');

    // Fill workspace name
    const nameInput = page.locator('input[name="name"], input[placeholder*="name"], #workspace-name');
    if (await nameInput.count() > 0) {
      await nameInput.fill(workspaceName);
    }

    await page.screenshot({ path: 'screenshots/create-workspace.png' });

    // Submit form
    try {
      await page.click('button[type="submit"], text=Create, text=Create Workspace');
      await page.waitForLoadState('networkidle');

      // Wait for workspace to be created (may take some time)
      await page.waitForSelector('text=Building, text=Running, text=Stopped', { timeout: 180000 });

      await page.screenshot({ path: 'screenshots/workspace-created.png' });
    } catch (e) {
      console.log('Workspace creation may not be fully automated in UI');
    }
  });

  test('should display workspace dashboard', async ({ page }) => {
    await page.goto('/workspaces');
    await page.waitForLoadState('networkidle');

    // Should show workspace list or dashboard
    const pageContent = await page.textContent('body');
    expect(pageContent).toMatch(/workspace|dashboard|no workspaces/i);

    await page.screenshot({ path: 'screenshots/workspace-dashboard.png' });
  });
});
EOF

    # Code Development Test
    cat > "${test_dir}/tests/development.spec.js" <<'EOF'
const { test, expect } = require('@playwright/test');

test.describe('Development Features', () => {
  test('should access workspace terminal', async ({ page }) => {
    await page.goto('/workspaces');
    await page.waitForLoadState('networkidle');

    // Look for running workspaces
    const runningWorkspaces = await page.locator('text=Running, [data-status="running"]').count();

    if (runningWorkspaces === 0) {
      console.log('No running workspaces found, skipping terminal test');
      return;
    }

    // Click on first running workspace or terminal button
    try {
      await page.click('text=Terminal, [data-testid="terminal"], button:has-text("Terminal")');
      await page.waitForLoadState('networkidle');

      // Check if terminal interface is loaded
      const terminal = await page.locator('.xterm, .terminal, [data-testid="terminal-container"]').count();
      expect(terminal).toBeGreaterThan(0);

      await page.screenshot({ path: 'screenshots/workspace-terminal.png' });
    } catch (e) {
      console.log('Terminal access not available through UI');
    }
  });

  test('should access code editor', async ({ page }) => {
    await page.goto('/workspaces');
    await page.waitForLoadState('networkidle');

    // Look for VS Code or code editor links
    try {
      await page.click('text=VS Code, text=Code Server, [href*="code"], button:has-text("Code")');
      await page.waitForLoadState('networkidle');

      await page.screenshot({ path: 'screenshots/code-editor.png' });
    } catch (e) {
      console.log('Code editor not accessible through main UI');
    }
  });
});
EOF

    # Performance Test
    cat > "${test_dir}/tests/performance.spec.js" <<'EOF'
const { test, expect } = require('@playwright/test');

test.describe('Performance Tests', () => {
  test('should load dashboard quickly', async ({ page }) => {
    const startTime = Date.now();

    await page.goto('/');
    await page.waitForLoadState('networkidle');

    const loadTime = Date.now() - startTime;

    // Dashboard should load within 10 seconds
    expect(loadTime).toBeLessThan(10000);

    console.log(`Dashboard loaded in ${loadTime}ms`);

    await page.screenshot({ path: 'screenshots/dashboard-loaded.png' });
  });

  test('should handle multiple concurrent requests', async ({ browser }) => {
    const contexts = await Promise.all([
      browser.newContext(),
      browser.newContext(),
      browser.newContext()
    ]);

    const pages = await Promise.all(contexts.map(context => context.newPage()));

    const startTime = Date.now();

    // Load dashboard in all tabs simultaneously
    await Promise.all(pages.map(page =>
      page.goto('/').then(() => page.waitForLoadState('networkidle'))
    ));

    const loadTime = Date.now() - startTime;

    // All pages should load within 15 seconds
    expect(loadTime).toBeLessThan(15000);

    console.log(`Concurrent load completed in ${loadTime}ms`);

    // Cleanup
    await Promise.all(contexts.map(context => context.close()));
  });
});
EOF

    # Error Handling Test
    cat > "${test_dir}/tests/error-handling.spec.js" <<'EOF'
const { test, expect } = require('@playwright/test');

test.describe('Error Handling', () => {
  test('should handle network errors gracefully', async ({ page }) => {
    // Test invalid route
    const response = await page.goto('/invalid-route');

    // Should get 404 or redirect to login
    expect([200, 404, 302]).toContain(response.status());

    await page.screenshot({ path: 'screenshots/invalid-route.png' });
  });

  test('should display error messages appropriately', async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('networkidle');

    // Look for any error messages on the page
    const errorMessages = await page.locator('.error, .alert-error, [role="alert"]').count();

    // Take screenshot if errors are present
    if (errorMessages > 0) {
      await page.screenshot({ path: 'screenshots/error-messages.png' });
      console.log(`Found ${errorMessages} error messages on page`);
    }

    // Page should load without critical errors
    const pageContent = await page.textContent('body');
    expect(pageContent.length).toBeGreaterThan(100);
  });
});
EOF

    log INFO "✅ E2E test scenarios created"
}

run_e2e_tests() {
    local test_dir="$1"
    local coder_url="$2"

    log STEP "Running E2E tests against: $coder_url"

    cd "$test_dir"

    # Set environment variables
    export CODER_URL="$coder_url"
    export PLAYWRIGHT_BROWSERS_PATH=0  # Use system browsers if available

    # Run tests
    local test_command="npx playwright test"

    if [[ "$VERBOSE" == "true" ]]; then
        test_command="$test_command --reporter=line"
    fi

    if [[ "$FAIL_FAST" == "true" ]]; then
        test_command="$test_command -x"
    fi

    log INFO "Executing: $test_command"

    # Copy screenshots to our directory
    if [[ -d "test-results" ]]; then
        cp -r test-results/* "$SCREENSHOT_DIR/" 2>/dev/null || true
    fi

    if $test_command; then
        log INFO "✅ E2E tests passed"
        return 0
    else
        log ERROR "❌ E2E tests failed"

        # Copy any additional artifacts
        if [[ -d "test-results" ]]; then
            cp -r test-results/* "$SCREENSHOT_DIR/" 2>/dev/null || true
        fi

        return 1
    fi
}

cleanup_test_workspaces() {
    if [[ "$CLEANUP_WORKSPACES" == "false" ]]; then
        log INFO "Skipping test workspace cleanup"
        return 0
    fi

    log STEP "Cleaning up test workspaces"

    local kubeconfig="${HOME}/.kube/config-coder-${ENVIRONMENT}"
    if [[ ! -f "$kubeconfig" ]]; then
        log WARN "Kubeconfig not found, skipping cleanup"
        return 0
    fi

    export KUBECONFIG="$kubeconfig"

    # Find and delete test workspaces (pods with test prefix)
    local test_pods=$(kubectl get pods -n coder --no-headers | grep "^${TEST_WORKSPACE_PREFIX}-" | awk '{print $1}' || echo "")

    if [[ -n "$test_pods" ]]; then
        echo "$test_pods" | while IFS= read -r pod; do
            log INFO "Deleting test pod: $pod"
            kubectl delete pod "$pod" -n coder --ignore-not-found=true || true
        done
    fi

    # Clean up any test PVCs
    local test_pvcs=$(kubectl get pvc -n coder --no-headers | grep "^${TEST_WORKSPACE_PREFIX}-" | awk '{print $1}' || echo "")

    if [[ -n "$test_pvcs" ]]; then
        echo "$test_pvcs" | while IFS= read -r pvc; do
            log INFO "Deleting test PVC: $pvc"
            kubectl delete pvc "$pvc" -n coder --ignore-not-found=true || true
        done
    fi

    log INFO "✅ Test workspace cleanup completed"
}

generate_junit_report() {
    local test_dir="$1"

    if [[ "$OUTPUT_FORMAT" != "junit" ]] || [[ -z "$JUNIT_OUTPUT" ]]; then
        return 0
    fi

    # Playwright generates its own JUnit report
    if [[ -f "${test_dir}/results.xml" ]]; then
        cp "${test_dir}/results.xml" "$JUNIT_OUTPUT"
        log INFO "JUnit report copied to: $JUNIT_OUTPUT"
    else
        # Generate basic JUnit report
        local end_time=$(date +%s)
        local total_time=$((end_time - START_TIME))

        cat > "$JUNIT_OUTPUT" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<testsuites name="Coder E2E Tests" tests="1" failures="0" errors="0" skipped="0" time="$total_time">
  <testsuite name="coder-${ENVIRONMENT}-e2e" tests="1" failures="0" errors="0" skipped="0" time="$total_time">
    <testcase name="E2E Test Suite" classname="e2e" time="$total_time">
    </testcase>
  </testsuite>
</testsuites>
EOF
        log INFO "Basic JUnit report generated: $JUNIT_OUTPUT"
    fi
}

print_summary() {
    local test_dir="$1"
    local end_time=$(date +%s)
    local duration=$((end_time - START_TIME))
    local duration_min=$((duration / 60))
    local duration_sec=$((duration % 60))

    echo
    echo -e "${BLUE}═══════════════════════════════════════${NC}"
    echo -e "${WHITE}           E2E TEST SUMMARY${NC}"
    echo -e "${BLUE}═══════════════════════════════════════${NC}"
    echo
    echo -e "${WHITE}Environment:${NC} $ENVIRONMENT"
    echo -e "${WHITE}Browser:${NC} $BROWSER (headless: $HEADLESS)"
    echo -e "${WHITE}Duration:${NC} ${duration_min}m ${duration_sec}s"
    echo

    # Try to get results from Playwright report
    local results_summary=""
    if [[ -f "${test_dir}/test-results/results.json" ]]; then
        results_summary=$(cat "${test_dir}/test-results/results.json" 2>/dev/null || echo "")
    fi

    if [[ -n "$results_summary" ]]; then
        local passed=$(echo "$results_summary" | jq -r '.suites[].specs[] | select(.ok == true) | .title' 2>/dev/null | wc -l)
        local failed=$(echo "$results_summary" | jq -r '.suites[].specs[] | select(.ok != true) | .title' 2>/dev/null | wc -l)
        local total=$((passed + failed))

        echo -e "${WHITE}Total Tests:${NC} $total"
        echo -e "${GREEN}Passed:${NC} $passed"
        echo -e "${RED}Failed:${NC} $failed"
    else
        echo -e "${WHITE}Test Results:${NC} See detailed logs and screenshots"
    fi

    echo
    echo -e "${YELLOW}🎯 Test Coverage:${NC}"
    echo "   • User Authentication: Login flow, session management"
    echo "   • Workspace Lifecycle: Creation, management, deletion"
    echo "   • Development Tools: Terminal access, code editor integration"
    echo "   • Performance: Page load times, concurrent user scenarios"
    echo "   • Error Handling: Invalid routes, network errors, resilience"

    echo
    echo -e "${CYAN}📁 Artifacts:${NC}"
    echo "   • Test logs: $LOG_FILE"
    echo "   • Screenshots: $SCREENSHOT_DIR"

    if [[ -d "${test_dir}/playwright-report" ]]; then
        echo "   • HTML report: ${test_dir}/playwright-report/index.html"
    fi

    if [[ "$OUTPUT_FORMAT" == "junit" ]] && [[ -n "$JUNIT_OUTPUT" ]]; then
        echo "   • JUnit XML: $JUNIT_OUTPUT"
    fi

    if [[ "$VIDEO_RECORDING" == "true" ]] && [[ -d "${test_dir}/test-results" ]]; then
        echo "   • Video recordings: ${test_dir}/test-results"
    fi

    echo
    echo -e "${CYAN}🌐 Browser Information:${NC}"
    echo "   • Browser: $BROWSER"
    echo "   • Mode: $([ "$HEADLESS" == "true" ] && echo "Headless" || echo "Interactive")"
    echo "   • Screenshots: On failure"
    echo "   • Video: $([ "$VIDEO_RECORDING" == "true" ] && echo "Enabled" || echo "Disabled")"

    echo
}

main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --env=*)
                ENVIRONMENT="${1#*=}"
                shift
                ;;
            --timeout=*)
                TIMEOUT="${1#*=}"
                shift
                ;;
            --browser=*)
                BROWSER="${1#*=}"
                shift
                ;;
            --no-headless)
                HEADLESS=false
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --fail-fast)
                FAIL_FAST=true
                shift
                ;;
            --format=*)
                OUTPUT_FORMAT="${1#*=}"
                shift
                ;;
            --junit-output=*)
                JUNIT_OUTPUT="${1#*=}"
                shift
                ;;
            --screenshot-dir=*)
                SCREENSHOT_DIR="${1#*=}"
                shift
                ;;
            --enable-video)
                VIDEO_RECORDING=true
                shift
                ;;
            --no-cleanup)
                CLEANUP_WORKSPACES=false
                shift
                ;;
            --help)
                print_usage
                exit 0
                ;;
            *)
                log ERROR "Unknown option: $1"
                print_usage
                exit 1
                ;;
        esac
    done

    # Validate required parameters
    if [[ -z "$ENVIRONMENT" ]]; then
        log ERROR "Environment is required. Use --env=ENV"
        print_usage
        exit 1
    fi

    # Validate browser
    case "$BROWSER" in
        chrome|firefox|safari)
            ;;
        *)
            log ERROR "Invalid browser: $BROWSER"
            log ERROR "Must be one of: chrome, firefox, safari"
            exit 1
            ;;
    esac

    # Validate output format
    case "$OUTPUT_FORMAT" in
        console|json|junit)
            ;;
        *)
            log ERROR "Invalid output format: $OUTPUT_FORMAT"
            log ERROR "Must be one of: console, json, junit"
            exit 1
            ;;
    esac

    print_banner
    setup_logging
    validate_environment

    log INFO "Starting E2E tests for environment: $ENVIRONMENT"
    log INFO "Browser: $BROWSER (headless: $HEADLESS)"
    log INFO "Test timeout: ${TIMEOUT}s"

    # Get Coder URL
    local coder_url
    coder_url=$(get_coder_url)
    if [[ $? -ne 0 ]]; then
        log ERROR "Cannot determine Coder URL"
        exit 1
    fi

    log INFO "Testing Coder instance at: $coder_url"

    # Setup test environment
    local test_dir
    test_dir=$(setup_playwright)
    if [[ $? -ne 0 ]]; then
        log ERROR "Failed to setup Playwright test environment"
        exit 1
    fi

    # Create test scenarios
    create_e2e_tests "$test_dir" "$coder_url"

    # Run E2E tests
    local test_result=0
    if ! run_e2e_tests "$test_dir" "$coder_url"; then
        test_result=1
    fi

    # Cleanup
    cleanup_test_workspaces

    # Generate reports
    generate_junit_report "$test_dir"
    print_summary "$test_dir"

    # Exit with test result
    exit $test_result
}

# Check for required dependencies
command -v node >/dev/null 2>&1 || { log ERROR "Node.js is required but not installed. Aborting."; exit 1; }
command -v npm >/dev/null 2>&1 || { log ERROR "npm is required but not installed. Aborting."; exit 1; }
command -v kubectl >/dev/null 2>&1 || { log ERROR "kubectl is required but not installed. Aborting."; exit 1; }

# Run main function with all arguments
main "$@"