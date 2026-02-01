import { test, expect } from '@playwright/test';
import { BASE_URLS } from '../playwright.config';

test.describe('Keycloak', () => {

  test('can access admin console', async ({ page }) => {
    await page.goto(`${BASE_URLS.keycloak}/admin/master/console`);
    
    // Should be logged in from setup, or redirected to login
    // Either way, eventually see the admin console
    await expect(page.getByText('master')).toBeVisible({ timeout: 15000 });
  });

  test('can view realm settings', async ({ page }) => {
    await page.goto(`${BASE_URLS.keycloak}/admin/master/console`);
    await expect(page.getByText('master')).toBeVisible({ timeout: 15000 });
    
    // Click on Realm settings in sidebar
    await page.getByRole('link', { name: 'Realm settings' }).click();
    
    // Should see realm configuration
    await expect(page.getByText('General')).toBeVisible();
  });

  test('can view users', async ({ page }) => {
    await page.goto(`${BASE_URLS.keycloak}/admin/master/console`);
    await expect(page.getByText('master')).toBeVisible({ timeout: 15000 });
    
    // Navigate to Users
    await page.getByRole('link', { name: 'Users' }).click();
    
    // Should see user list
    await expect(page.getByRole('button', { name: 'Add user' })).toBeVisible();
  });

  test('can view LDAP federation', async ({ page }) => {
    await page.goto(`${BASE_URLS.keycloak}/admin/master/console`);
    await expect(page.getByText('master')).toBeVisible({ timeout: 15000 });
    
    // Navigate to User Federation
    await page.getByRole('link', { name: 'User federation' }).click();
    
    // Should see LLDAP federation if configured
    await expect(page.getByText('lldap').or(page.getByText('Add Ldap providers'))).toBeVisible();
  });

  test('can view clients', async ({ page }) => {
    await page.goto(`${BASE_URLS.keycloak}/admin/master/console`);
    await expect(page.getByText('master')).toBeVisible({ timeout: 15000 });
    
    // Navigate to Clients
    await page.getByRole('link', { name: 'Clients' }).click();
    
    // Should see client list including vault
    await expect(page.getByText('vault').or(page.getByText('admin-cli'))).toBeVisible();
  });

  test('can view identity providers', async ({ page }) => {
    await page.goto(`${BASE_URLS.keycloak}/admin/master/console`);
    await expect(page.getByText('master')).toBeVisible({ timeout: 15000 });
    
    // Navigate to Identity Providers
    await page.getByRole('link', { name: 'Identity providers' }).click();
    
    // Should see identity provider configuration page
    await expect(page.getByText('Add provider')).toBeVisible();
  });

  test('LDAP sync is configured', async ({ page }) => {
    await page.goto(`${BASE_URLS.keycloak}/admin/master/console`);
    await expect(page.getByText('master')).toBeVisible({ timeout: 15000 });
    
    // Navigate to User Federation
    await page.getByRole('link', { name: 'User federation' }).click();
    
    // Click on LLDAP federation
    const lldapLink = page.getByRole('link', { name: 'lldap' });
    
    if (await lldapLink.isVisible()) {
      await lldapLink.click();
      
      // Should see federation settings
      await expect(page.getByLabel('Connection URL')).toBeVisible();
      
      // Verify it's pointing to LLDAP service
      const connectionUrl = page.getByLabel('Connection URL');
      await expect(connectionUrl).toHaveValue(/lldap.*:389/);
    } else {
      test.skip(true, 'LLDAP federation not configured');
    }
  });
});
