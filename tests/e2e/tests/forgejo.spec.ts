import { test, expect } from '@playwright/test';
import { BASE_URLS } from '../playwright.config';

test.describe('Forgejo', () => {

  test('homepage loads', async ({ page }) => {
    await page.goto(BASE_URLS.forgejo);
    
    // Should see Forgejo home page
    await expect(page.getByText('Explore').or(page.getByText('Forgejo'))).toBeVisible();
  });

  test('can login with credentials', async ({ page }) => {
    const username = process.env.FORGEJO_USERNAME || 'jimi';
    const password = process.env.FORGEJO_PASSWORD;
    
    if (!password) {
      test.skip(true, 'FORGEJO_PASSWORD not set');
      return;
    }
    
    await page.goto(`${BASE_URLS.forgejo}/user/login`);
    
    // Fill login form
    await page.getByLabel('Username or email').fill(username);
    await page.getByLabel('Password').fill(password);
    
    // Click sign in
    await page.getByRole('button', { name: 'Sign In' }).click();
    
    // Should see dashboard
    await expect(page.getByText('Dashboard').or(page.getByText('Repositories'))).toBeVisible({ timeout: 10000 });
  });

  test('can view repositories', async ({ page }) => {
    const username = process.env.FORGEJO_USERNAME || 'jimi';
    const password = process.env.FORGEJO_PASSWORD;
    
    if (!password) {
      test.skip(true, 'FORGEJO_PASSWORD not set');
      return;
    }
    
    await page.goto(`${BASE_URLS.forgejo}/user/login`);
    await page.getByLabel('Username or email').fill(username);
    await page.getByLabel('Password').fill(password);
    await page.getByRole('button', { name: 'Sign In' }).click();
    
    // Navigate to explore repos
    await page.goto(`${BASE_URLS.forgejo}/explore/repos`);
    
    // Should see repo list
    await expect(page.getByText('Explore')).toBeVisible();
  });

  test('can create and delete a test repository', async ({ page }) => {
    const username = process.env.FORGEJO_USERNAME || 'jimi';
    const password = process.env.FORGEJO_PASSWORD;
    
    if (!password) {
      test.skip(true, 'FORGEJO_PASSWORD not set');
      return;
    }
    
    // Login
    await page.goto(`${BASE_URLS.forgejo}/user/login`);
    await page.getByLabel('Username or email').fill(username);
    await page.getByLabel('Password').fill(password);
    await page.getByRole('button', { name: 'Sign In' }).click();
    await expect(page.getByText('Dashboard').or(page.getByText('Repositories'))).toBeVisible({ timeout: 10000 });
    
    // Create new repo
    await page.goto(`${BASE_URLS.forgejo}/repo/create`);
    
    const repoName = `e2e-test-${Date.now()}`;
    await page.getByLabel('Repository name').fill(repoName);
    await page.getByLabel('Description').fill('E2E test repository - safe to delete');
    
    // Initialize with README
    await page.getByLabel('Initialize repository').check();
    
    // Create
    await page.getByRole('button', { name: 'Create Repository' }).click();
    
    // Verify repo was created
    await expect(page.getByText(repoName)).toBeVisible({ timeout: 10000 });
    await expect(page.getByText('README.md')).toBeVisible();
    
    // Clean up - delete repo
    await page.goto(`${BASE_URLS.forgejo}/${username}/${repoName}/settings`);
    
    // Scroll to danger zone
    await page.getByText('Delete This Repository').scrollIntoViewIfNeeded();
    await page.getByRole('button', { name: 'Delete This Repository' }).click();
    
    // Confirm deletion - type repo name
    await page.getByPlaceholder(repoName).fill(repoName);
    await page.getByRole('button', { name: 'Delete Repository' }).click();
    
    // Verify deleted - should redirect to dashboard
    await expect(page.getByText('Dashboard').or(page.getByText('Repositories'))).toBeVisible({ timeout: 10000 });
  });

  test('can view user profile', async ({ page }) => {
    const username = process.env.FORGEJO_USERNAME || 'jimi';
    const password = process.env.FORGEJO_PASSWORD;
    
    if (!password) {
      test.skip(true, 'FORGEJO_PASSWORD not set');
      return;
    }
    
    await page.goto(`${BASE_URLS.forgejo}/user/login`);
    await page.getByLabel('Username or email').fill(username);
    await page.getByLabel('Password').fill(password);
    await page.getByRole('button', { name: 'Sign In' }).click();
    
    // Navigate to profile
    await page.goto(`${BASE_URLS.forgejo}/${username}`);
    
    // Should see profile page
    await expect(page.getByText(username)).toBeVisible();
  });
});
