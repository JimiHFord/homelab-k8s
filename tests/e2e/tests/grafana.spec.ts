import { test, expect } from '@playwright/test';
import { BASE_URLS } from '../playwright.config';

test.describe('Grafana', () => {

  test('can login via OAuth', async ({ page }) => {
    await page.goto(BASE_URLS.grafana);
    
    // Click OAuth login button (Keycloak)
    const oauthButton = page.getByRole('link', { name: /sign in with|keycloak|oauth/i });
    
    if (await oauthButton.isVisible()) {
      await oauthButton.click();
      
      // Should redirect to Keycloak - already authenticated from setup
      // Should come back to Grafana logged in
      await expect(page.getByText('Home')).toBeVisible({ timeout: 15000 });
    } else {
      // Fallback to basic auth if OAuth not configured
      test.skip(true, 'OAuth not configured');
    }
  });

  test('can access home dashboard', async ({ page }) => {
    await page.goto(BASE_URLS.grafana);
    
    // Login via OAuth
    const oauthButton = page.getByRole('link', { name: /sign in with|keycloak|oauth/i });
    if (await oauthButton.isVisible()) {
      await oauthButton.click();
    }
    
    // Should see home dashboard
    await expect(page.getByText('Home').or(page.getByText('Welcome'))).toBeVisible({ timeout: 15000 });
  });

  test('can access data sources', async ({ page }) => {
    await page.goto(BASE_URLS.grafana);
    
    // Login via OAuth
    const oauthButton = page.getByRole('link', { name: /sign in with|keycloak|oauth/i });
    if (await oauthButton.isVisible()) {
      await oauthButton.click();
    }
    
    await expect(page.getByText('Home').or(page.getByText('Welcome'))).toBeVisible({ timeout: 15000 });
    
    // Navigate to data sources via menu
    await page.goto(`${BASE_URLS.grafana}/datasources`);
    
    // Should see data sources page
    await expect(page.getByText('Data sources')).toBeVisible();
  });

  test('can access alerting', async ({ page }) => {
    await page.goto(BASE_URLS.grafana);
    
    // Login via OAuth
    const oauthButton = page.getByRole('link', { name: /sign in with|keycloak|oauth/i });
    if (await oauthButton.isVisible()) {
      await oauthButton.click();
    }
    
    await expect(page.getByText('Home').or(page.getByText('Welcome'))).toBeVisible({ timeout: 15000 });
    
    // Navigate to alerting
    await page.goto(`${BASE_URLS.grafana}/alerting/list`);
    
    // Should see alerting page
    await expect(page.getByText('Alert rules').or(page.getByText('Alerting'))).toBeVisible();
  });

  test('can access explore', async ({ page }) => {
    await page.goto(BASE_URLS.grafana);
    
    // Login via OAuth
    const oauthButton = page.getByRole('link', { name: /sign in with|keycloak|oauth/i });
    if (await oauthButton.isVisible()) {
      await oauthButton.click();
    }
    
    await expect(page.getByText('Home').or(page.getByText('Welcome'))).toBeVisible({ timeout: 15000 });
    
    // Navigate to explore
    await page.goto(`${BASE_URLS.grafana}/explore`);
    
    // Should see explore page
    await expect(page.getByText('Explore')).toBeVisible();
  });
});
