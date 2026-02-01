import { test, expect } from '@playwright/test';
import { BASE_URLS } from '../playwright.config';

/**
 * Smoke tests - verify services are reachable and responding.
 * These don't require authentication.
 */

test.describe('Service Health Checks', () => {
  
  test('vault is reachable', async ({ page }) => {
    const response = await page.goto(BASE_URLS.vault);
    expect(response?.status()).toBeLessThan(500);
    
    // Vault login page should be visible
    await expect(page.getByText('Sign in to Vault')).toBeVisible();
  });

  test('keycloak is reachable', async ({ page }) => {
    const response = await page.goto(BASE_URLS.keycloak);
    expect(response?.status()).toBeLessThan(500);
    
    // Should see Keycloak branding or login
    await expect(page.locator('body')).toContainText(/keycloak|sign in|log in/i);
  });

  test('lldap is reachable', async ({ page }) => {
    const response = await page.goto(BASE_URLS.lldap);
    expect(response?.status()).toBeLessThan(500);
    
    // LLDAP login page
    await expect(page.getByRole('button', { name: /sign in|login/i })).toBeVisible();
  });

  test('grafana is reachable', async ({ page }) => {
    const response = await page.goto(BASE_URLS.grafana);
    expect(response?.status()).toBeLessThan(500);
    
    // Grafana login or dashboard
    await expect(page.locator('body')).toContainText(/grafana|login|welcome/i);
  });

  test('forgejo is reachable', async ({ page }) => {
    const response = await page.goto(BASE_URLS.forgejo);
    expect(response?.status()).toBeLessThan(500);
    
    // Forgejo home page
    await expect(page.locator('body')).toContainText(/forgejo|explore|sign in/i);
  });
});

test.describe('API Health Endpoints', () => {
  
  test('vault health API', async ({ request }) => {
    const response = await request.get(`${BASE_URLS.vault}/v1/sys/health`, {
      ignoreHTTPSErrors: true,
    });
    
    // Vault returns 200 if initialized and unsealed
    // 429 if unsealed but standby
    // 472 if in recovery mode
    // 473 if in performance standby
    // 501 if not initialized
    // 503 if sealed
    expect([200, 429, 472, 473]).toContain(response.status());
    
    const health = await response.json();
    expect(health).toHaveProperty('initialized');
    expect(health).toHaveProperty('sealed');
  });

  test('keycloak health API', async ({ request }) => {
    // Keycloak health endpoint is at /health/ready or /realms/master
    const response = await request.get(`${BASE_URLS.keycloak}/realms/master/.well-known/openid-configuration`, {
      ignoreHTTPSErrors: true,
    });
    
    expect(response.status()).toBe(200);
    const config = await response.json();
    expect(config).toHaveProperty('issuer');
  });

  test('grafana health API', async ({ request }) => {
    const response = await request.get(`${BASE_URLS.grafana}/api/health`, {
      ignoreHTTPSErrors: true,
    });
    
    expect(response.status()).toBe(200);
    const health = await response.json();
    expect(health.database).toBe('ok');
  });
});
