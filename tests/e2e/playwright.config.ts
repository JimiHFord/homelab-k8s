import { defineConfig, devices } from '@playwright/test';
import dotenv from 'dotenv';

// Load environment variables from .env file
dotenv.config();

// Base URLs for services - override with environment variables
// In CI, these are set to ephemeral E2E URLs (e.g., vault-e2e-12345.fords.cloud)
const BASE_URLS = {
  vault: process.env.VAULT_URL || 'https://vault.fords.cloud',
  keycloak: process.env.KEYCLOAK_URL || 'https://sso.fords.cloud',
  lldap: process.env.LLDAP_URL || 'https://ldap.fords.cloud',
  grafana: process.env.GRAFANA_URL || 'https://grafana.fords.cloud',
  forgejo: process.env.FORGEJO_URL || 'https://forgejo.fords.cloud',
};

// For E2E tests, Vault uses dev mode with a known root token
const VAULT_DEV_TOKEN = process.env.VAULT_DEV_TOKEN || 'e2e-root-token';

export { BASE_URLS };

export default defineConfig({
  testDir: './tests',
  
  // Run tests in parallel
  fullyParallel: true,
  
  // Fail the build on CI if you accidentally left test.only in the source code
  forbidOnly: !!process.env.CI,
  
  // Retry on CI only
  retries: process.env.CI ? 2 : 0,
  
  // Limit parallel workers on CI
  workers: process.env.CI ? 1 : undefined,
  
  // Reporter configuration
  reporter: [
    ['html', { open: 'never' }],
    ['list'],
    ...(process.env.CI ? [['github'] as const] : []),
  ],
  
  // Shared settings for all projects
  use: {
    // Collect trace on first retry
    trace: 'on-first-retry',
    
    // Capture screenshot on failure
    screenshot: 'only-on-failure',
    
    // Record video on first retry
    video: 'on-first-retry',
    
    // Timeout for each action
    actionTimeout: 15000,
    
    // Base URL (can be overridden per-test)
    baseURL: BASE_URLS.vault,
    
    // Ignore HTTPS errors (for self-signed certs in test environments)
    ignoreHTTPSErrors: true,
  },

  // Global timeout for each test
  timeout: 60000,

  // Expect timeout
  expect: {
    timeout: 10000,
  },

  // Configure projects for different browsers
  projects: [
    // Setup project - runs first to authenticate
    {
      name: 'setup',
      testMatch: /.*\.setup\.ts/,
      use: { ...devices['Desktop Chrome'] },
    },
    
    // Main test project
    {
      name: 'chromium',
      use: { 
        ...devices['Desktop Chrome'],
        // Use authenticated state from setup
        storageState: './fixtures/.auth/user.json',
      },
      dependencies: ['setup'],
    },

    // Smoke tests - quick sanity checks, no auth needed
    {
      name: 'smoke',
      testMatch: /.*\.smoke\.ts/,
      use: { ...devices['Desktop Chrome'] },
    },
  ],

  // Local dev server (optional - for testing local deployments)
  // webServer: {
  //   command: 'kubectl port-forward svc/vault 8200:8200 -n vault',
  //   url: 'http://localhost:8200',
  //   reuseExistingServer: !process.env.CI,
  // },
});
