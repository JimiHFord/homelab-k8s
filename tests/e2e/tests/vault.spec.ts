import { test, expect } from '@playwright/test';
import { BASE_URLS } from '../playwright.config';

test.describe('Vault', () => {
  
  test.beforeEach(async ({ page }) => {
    await page.goto(BASE_URLS.vault);
  });

  test('can login via OIDC', async ({ page }) => {
    // Select OIDC method
    await page.getByRole('tab', { name: 'OIDC' }).click();
    
    // Enter role name (optional, depends on config)
    const roleInput = page.getByLabel('Role');
    if (await roleInput.isVisible()) {
      await roleInput.fill('admin');
    }
    
    // Click sign in
    await page.getByRole('button', { name: 'Sign in with OIDC Provider' }).click();
    
    // Should redirect to Keycloak - but we're already authenticated from setup
    // So we should be redirected back to Vault
    
    // Wait for Vault dashboard
    await expect(page.getByText('Secrets Engines')).toBeVisible({ timeout: 15000 });
  });

  test('can view secrets engines', async ({ page }) => {
    // Login first
    await page.getByRole('tab', { name: 'OIDC' }).click();
    await page.getByRole('button', { name: 'Sign in with OIDC Provider' }).click();
    
    await expect(page.getByText('Secrets Engines')).toBeVisible({ timeout: 15000 });
    
    // Should see the default KV engine
    await expect(page.getByText('secret/')).toBeVisible();
  });

  test('can navigate to KV secrets', async ({ page }) => {
    // Login
    await page.getByRole('tab', { name: 'OIDC' }).click();
    await page.getByRole('button', { name: 'Sign in with OIDC Provider' }).click();
    await expect(page.getByText('Secrets Engines')).toBeVisible({ timeout: 15000 });
    
    // Click on secret engine
    await page.getByRole('link', { name: 'secret' }).click();
    
    // Should see KV interface
    await expect(page.getByText('Create secret')).toBeVisible();
  });

  test('can create and read a secret', async ({ page }) => {
    // Login
    await page.getByRole('tab', { name: 'OIDC' }).click();
    await page.getByRole('button', { name: 'Sign in with OIDC Provider' }).click();
    await expect(page.getByText('Secrets Engines')).toBeVisible({ timeout: 15000 });
    
    // Navigate to secrets
    await page.getByRole('link', { name: 'secret' }).click();
    await page.getByRole('link', { name: 'Create secret' }).click();
    
    // Create a test secret
    const testPath = `e2e-test-${Date.now()}`;
    await page.getByLabel('Path for this secret').fill(testPath);
    
    // Add secret data
    await page.getByPlaceholder('key').first().fill('test-key');
    await page.getByPlaceholder('value').first().fill('test-value');
    
    // Save
    await page.getByRole('button', { name: 'Save' }).click();
    
    // Verify it was created
    await expect(page.getByText(testPath)).toBeVisible();
    await expect(page.getByText('test-key')).toBeVisible();
    
    // Clean up - delete the secret
    await page.getByRole('button', { name: 'Delete' }).click();
    await page.getByRole('button', { name: 'Delete' }).click(); // Confirm
  });

  test('can view policies', async ({ page }) => {
    // Login
    await page.getByRole('tab', { name: 'OIDC' }).click();
    await page.getByRole('button', { name: 'Sign in with OIDC Provider' }).click();
    await expect(page.getByText('Secrets Engines')).toBeVisible({ timeout: 15000 });
    
    // Navigate to policies
    await page.getByRole('link', { name: 'Policies' }).click();
    
    // Should see ACL policies
    await expect(page.getByText('ACL Policies')).toBeVisible();
    await expect(page.getByText('default')).toBeVisible();
  });
});
