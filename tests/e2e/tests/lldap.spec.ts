import { test, expect } from '@playwright/test';
import { BASE_URLS } from '../playwright.config';

test.describe('LLDAP', () => {

  test.beforeEach(async ({ page }) => {
    await page.goto(BASE_URLS.lldap);
  });

  test('can login to LLDAP admin', async ({ page }) => {
    const username = process.env.LLDAP_ADMIN_USER || 'admin';
    const password = process.env.LLDAP_ADMIN_PASSWORD || process.env.TEST_PASSWORD;
    
    if (!password) {
      test.skip(true, 'LLDAP_ADMIN_PASSWORD not set');
      return;
    }
    
    // Fill login form
    await page.getByLabel('Username').fill(username);
    await page.getByLabel('Password').fill(password);
    
    // Click sign in
    await page.getByRole('button', { name: /sign in|login/i }).click();
    
    // Should see admin dashboard
    await expect(page.getByText('Users')).toBeVisible({ timeout: 10000 });
  });

  test('can view user list', async ({ page }) => {
    const username = process.env.LLDAP_ADMIN_USER || 'admin';
    const password = process.env.LLDAP_ADMIN_PASSWORD || process.env.TEST_PASSWORD;
    
    if (!password) {
      test.skip(true, 'LLDAP_ADMIN_PASSWORD not set');
      return;
    }
    
    // Login
    await page.getByLabel('Username').fill(username);
    await page.getByLabel('Password').fill(password);
    await page.getByRole('button', { name: /sign in|login/i }).click();
    
    // Navigate to users
    await page.getByRole('link', { name: 'Users' }).click();
    
    // Should see user list with at least admin user
    await expect(page.getByText('admin')).toBeVisible();
  });

  test('can view group list', async ({ page }) => {
    const username = process.env.LLDAP_ADMIN_USER || 'admin';
    const password = process.env.LLDAP_ADMIN_PASSWORD || process.env.TEST_PASSWORD;
    
    if (!password) {
      test.skip(true, 'LLDAP_ADMIN_PASSWORD not set');
      return;
    }
    
    // Login
    await page.getByLabel('Username').fill(username);
    await page.getByLabel('Password').fill(password);
    await page.getByRole('button', { name: /sign in|login/i }).click();
    
    // Navigate to groups
    await page.getByRole('link', { name: 'Groups' }).click();
    
    // Should see group list
    await expect(page.getByText('lldap_admin')).toBeVisible();
  });

  test('can create and delete a test user', async ({ page }) => {
    const username = process.env.LLDAP_ADMIN_USER || 'admin';
    const password = process.env.LLDAP_ADMIN_PASSWORD || process.env.TEST_PASSWORD;
    
    if (!password) {
      test.skip(true, 'LLDAP_ADMIN_PASSWORD not set');
      return;
    }
    
    // Login
    await page.getByLabel('Username').fill(username);
    await page.getByLabel('Password').fill(password);
    await page.getByRole('button', { name: /sign in|login/i }).click();
    await expect(page.getByText('Users')).toBeVisible({ timeout: 10000 });
    
    // Create user
    await page.getByRole('link', { name: 'Create a user' }).click();
    
    const testUsername = `e2e-test-${Date.now()}`;
    await page.getByLabel('User ID').fill(testUsername);
    await page.getByLabel('Email').fill(`${testUsername}@test.local`);
    await page.getByLabel('Password', { exact: true }).fill('TestPassword123!');
    await page.getByLabel('Confirm Password').fill('TestPassword123!');
    
    await page.getByRole('button', { name: 'Create' }).click();
    
    // Verify user was created
    await page.getByRole('link', { name: 'Users' }).click();
    await expect(page.getByText(testUsername)).toBeVisible();
    
    // Clean up - delete the user
    await page.getByText(testUsername).click();
    await page.getByRole('button', { name: 'Delete' }).click();
    
    // Confirm deletion
    await page.getByRole('button', { name: 'Delete' }).click();
    
    // Verify deleted
    await page.getByRole('link', { name: 'Users' }).click();
    await expect(page.getByText(testUsername)).not.toBeVisible();
  });
});
