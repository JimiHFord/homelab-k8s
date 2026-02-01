import { test as setup, expect } from '@playwright/test';
import { BASE_URLS } from '../playwright.config';
import path from 'path';

const authFile = path.join(__dirname, '../fixtures/.auth/user.json');

/**
 * Authentication setup - logs into Keycloak and saves session state.
 * This runs before all tests that depend on authenticated state.
 */
setup('authenticate via keycloak', async ({ page }) => {
  const username = process.env.TEST_USERNAME || 'admin';
  const password = process.env.TEST_PASSWORD;
  
  if (!password) {
    throw new Error('TEST_PASSWORD environment variable is required');
  }

  // Go to Keycloak login page directly
  await page.goto(`${BASE_URLS.keycloak}/realms/master/account`);
  
  // Wait for login form
  await expect(page.getByLabel('Username or email')).toBeVisible();
  
  // Fill in credentials
  await page.getByLabel('Username or email').fill(username);
  await page.getByLabel('Password', { exact: true }).fill(password);
  
  // Click sign in
  await page.getByRole('button', { name: 'Sign In' }).click();
  
  // Wait for successful login - should see account page
  await expect(page.getByText('Personal info')).toBeVisible({ timeout: 15000 });
  
  // Save authentication state
  await page.context().storageState({ path: authFile });
});

setup('verify keycloak session saved', async ({ page }) => {
  // Quick verification that our saved state works
  await page.goto(`${BASE_URLS.keycloak}/realms/master/account`);
  
  // Should already be logged in
  await expect(page.getByText('Personal info')).toBeVisible({ timeout: 5000 });
});
