# Homelab E2E Tests

End-to-end browser tests for homelab services using [Playwright](https://playwright.dev/).

## Services Tested

| Service | Tests |
|---------|-------|
| Vault | OIDC login, secrets CRUD, policies |
| Keycloak | Admin console, users, LDAP federation |
| LLDAP | Login, user/group management |
| Grafana | OAuth login, dashboards, data sources |
| Forgejo | Login, repository CRUD |

## Quick Start

```bash
# Install dependencies
npm install

# Install browsers
npx playwright install chromium

# Run smoke tests (no auth needed)
npm run test -- --project=smoke

# Run all tests (needs credentials)
cp .env.example .env
# Edit .env with your credentials
npm test
```

## Test Types

### Smoke Tests (`*.smoke.ts`)
Basic connectivity tests - verify services are reachable and responding.
No authentication required.

```bash
npm run test -- --project=smoke
```

### Full Tests (`*.spec.ts`)
Complete feature tests with authentication.
Requires `TEST_PASSWORD` environment variable.

```bash
npm test
```

## Configuration

### Environment Variables

| Variable | Description | Required |
|----------|-------------|----------|
| `TEST_USERNAME` | Keycloak admin username | No (default: admin) |
| `TEST_PASSWORD` | Keycloak admin password | Yes |
| `LLDAP_ADMIN_PASSWORD` | LLDAP admin password | For LLDAP tests |
| `FORGEJO_PASSWORD` | Forgejo user password | For Forgejo tests |
| `VAULT_URL` | Vault URL | No (default: https://vault.fords.cloud) |
| `KEYCLOAK_URL` | Keycloak URL | No (default: https://sso.fords.cloud) |
| `LLDAP_URL` | LLDAP URL | No (default: https://ldap.fords.cloud) |
| `GRAFANA_URL` | Grafana URL | No (default: https://grafana.fords.cloud) |
| `FORGEJO_URL` | Forgejo URL | No (default: https://forgejo.fords.cloud) |

### Testing Different Environments

```bash
# Test staging environment
VAULT_URL=https://vault-staging.fords.cloud \
KEYCLOAK_URL=https://sso-staging.fords.cloud \
npm test

# Test local k3s port-forwards
VAULT_URL=http://localhost:8200 \
KEYCLOAK_URL=http://localhost:8080 \
npm test
```

## Development

### Generate tests with codegen

```bash
# Open browser and record actions
npm run test:codegen https://vault.fords.cloud

# Generates code as you interact with the page
```

### Debug failing tests

```bash
# Run with headed browser and debug tools
npm run test:debug

# Run with UI mode (interactive)
npm run test:ui

# View HTML report from last run
npm run report
```

### Run specific tests

```bash
# Single test file
npm test -- tests/vault.spec.ts

# Tests matching pattern
npm test -- -g "can login"

# Headed mode (see browser)
npm run test:headed
```

## CI/CD

Tests run automatically via GitHub Actions:

- **Smoke tests**: On every push, verify services are up
- **Full E2E**: Nightly, or on-demand via workflow dispatch

### Required Secrets

Add these to your GitHub repository secrets:

- `TEST_USERNAME`
- `TEST_PASSWORD`
- `LLDAP_ADMIN_PASSWORD`
- `FORGEJO_PASSWORD`

### Test Reports

Reports are deployed to GitHub Pages at:
`https://<username>.github.io/homelab-k8s/e2e-report/`

## Project Structure

```
tests/e2e/
├── fixtures/
│   └── .auth/           # Saved authentication state
├── tests/
│   ├── auth.setup.ts    # Authentication setup (runs first)
│   ├── smoke.smoke.ts   # Smoke tests (no auth)
│   ├── vault.spec.ts    # Vault tests
│   ├── keycloak.spec.ts # Keycloak tests
│   ├── lldap.spec.ts    # LLDAP tests
│   ├── grafana.spec.ts  # Grafana tests
│   └── forgejo.spec.ts  # Forgejo tests
├── playwright.config.ts # Playwright configuration
├── package.json
└── README.md
```

## Writing New Tests

1. Create `tests/<service>.spec.ts`
2. Import config: `import { BASE_URLS } from '../playwright.config';`
3. Use `test.describe` and `test` from `@playwright/test`
4. For authenticated tests, the session is pre-loaded from setup

Example:
```typescript
import { test, expect } from '@playwright/test';
import { BASE_URLS } from '../playwright.config';

test.describe('My Service', () => {
  test('does something', async ({ page }) => {
    await page.goto(BASE_URLS.myService);
    await expect(page.getByText('Welcome')).toBeVisible();
  });
});
```

## Troubleshooting

### Tests failing with timeout
- Increase timeout in `playwright.config.ts`
- Check if services are actually reachable
- Run smoke tests first to verify connectivity

### Authentication issues
- Delete `fixtures/.auth/user.json` and re-run
- Verify `TEST_PASSWORD` is correct
- Check Keycloak is accessible

### Flaky tests
- Add `test.slow()` for slow operations
- Use proper `expect` assertions with `toBeVisible({ timeout: X })`
- Avoid `page.waitForTimeout()` - use assertions instead
