const request = require('supertest');

/**
 * End-to-end integration tests against a running FocusFlow backend.
 *
 * These tests assume the backend is already running (e.g. on localhost:5000
 * or on Render). They exercise the full auth → policies → screen-policies
 * → sync flow and clean up created resources where possible.
 */

const API_BASE = process.env.API_BASE_URL || 'http://localhost:5000';
const api = request(API_BASE);

// Unique test user so repeated runs don't collide.
const testEmail = `integration-${Date.now()}@focusflow.test`;
const testPassword = 'TestPass123!';
const testName = 'Integration Test';

let accessToken;
let refreshToken;
let userId;
let policyId;
let screenPolicyId;

describe('FocusFlow E2E Integration', () => {
  // Increase timeout for network calls
  jest.setTimeout(30000);

  afterAll(async () => {
    // Best-effort cleanup of resources created by this suite. The test user
    // itself cannot be deleted because there is no DELETE /auth/me endpoint.
    if (!accessToken) return;
    try {
      if (screenPolicyId) {
        await api
          .delete(`/api/v1/screen-policies/${screenPolicyId}`)
          .set('Authorization', `Bearer ${accessToken}`);
      }
      if (policyId) {
        await api
          .delete(`/api/v1/policies/${policyId}`)
          .set('Authorization', `Bearer ${accessToken}`);
      }
    } catch (e) {
      // ignore cleanup errors
    }
  });

  test('GET /health returns ok', async () => {
    const res = await api.get('/health').expect(200);
    expect(res.body.status).toBe('ok');
    expect(res.body).toHaveProperty('uptime');
    expect(res.body).toHaveProperty('environment');
  });

  test('POST /api/v1/auth/register creates a new user', async () => {
    const res = await api
      .post('/api/v1/auth/register')
      .send({ name: testName, email: testEmail, password: testPassword })
      .expect(201);

    expect(res.body.success).toBe(true);
    expect(res.body.accessToken).toBeDefined();
    expect(res.body.refreshToken).toBeDefined();
    expect(res.body.user.email).toBe(testEmail.toLowerCase());

    accessToken = res.body.accessToken;
    refreshToken = res.body.refreshToken;
    userId = res.body.user.id;
  });

  test('POST /api/v1/auth/register rejects duplicate email', async () => {
    const res = await api
      .post('/api/v1/auth/register')
      .send({ name: testName, email: testEmail, password: testPassword })
      .expect(409);

    expect(res.body.success).toBe(false);
  });

  test('POST /api/v1/auth/login rejects invalid password', async () => {
    const res = await api
      .post('/api/v1/auth/login')
      .send({ email: testEmail, password: 'wrongpassword' })
      .expect(401);

    expect(res.body.success).toBe(false);
  });

  test('POST /api/v1/auth/login returns tokens', async () => {
    const res = await api
      .post('/api/v1/auth/login')
      .send({ email: testEmail, password: testPassword })
      .expect(200);

    expect(res.body.success).toBe(true);
    expect(res.body.accessToken).toBeDefined();
    expect(res.body.refreshToken).toBeDefined();

    accessToken = res.body.accessToken;
    refreshToken = res.body.refreshToken;
  });

  test('POST /api/v1/auth/refresh returns a new access token', async () => {
    const res = await api
      .post('/api/v1/auth/refresh')
      .send({ refreshToken })
      .expect(200);

    expect(res.body.success).toBe(true);
    expect(res.body.accessToken).toBeDefined();

    accessToken = res.body.accessToken;
  });

  test('GET /api/v1/auth/me requires authentication', async () => {
    const res = await api.get('/api/v1/auth/me').expect(401);
    expect(res.body.success).toBe(false);
  });

  test('GET /api/v1/auth/me returns current user', async () => {
    const res = await api
      .get('/api/v1/auth/me')
      .set('Authorization', `Bearer ${accessToken}`)
      .expect(200);

    expect(res.body.success).toBe(true);
    expect(res.body.user.email).toBe(testEmail.toLowerCase());
    expect(res.body.user.id).toBeDefined();
  });

  test('PATCH /api/v1/auth/strict-mode enables strict mode', async () => {
    const res = await api
      .patch('/api/v1/auth/strict-mode')
      .set('Authorization', `Bearer ${accessToken}`)
      .send({ strictMode: true, pin: '1234', dailyGoalMinutes: 90 })
      .expect(200);

    expect(res.body.success).toBe(true);
    expect(res.body.strictMode).toBe(true);
    expect(res.body.dailyGoalMinutes).toBe(90);
  });

  test('POST /api/v1/policies creates an app policy', async () => {
    const res = await api
      .post('/api/v1/policies')
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        packageName: 'com.instagram.android',
        appName: 'Instagram',
        timeLimitMinutes: 30,
      })
      .expect(200);

    expect(res.body.success).toBe(true);
    expect(res.body.policy.packageName).toBe('com.instagram.android');

    policyId = res.body.policy._id;
  });

  test('GET /api/v1/policies returns the created policy', async () => {
    const res = await api
      .get('/api/v1/policies')
      .set('Authorization', `Bearer ${accessToken}`)
      .expect(200);

    expect(res.body.success).toBe(true);
    expect(res.body.count).toBeGreaterThanOrEqual(1);
    expect(res.body.policies.some((p) => p.packageName === 'com.instagram.android')).toBe(true);
  });

  test('PATCH /api/v1/policies/:id/toggle deactivates the policy', async () => {
    const res = await api
      .patch(`/api/v1/policies/${policyId}/toggle`)
      .set('Authorization', `Bearer ${accessToken}`)
      .expect(200);

    expect(res.body.success).toBe(true);
    expect(res.body.policy.isActive).toBe(false);
  });

  test('POST /api/v1/screen-policies creates a screen policy', async () => {
    const res = await api
      .post('/api/v1/screen-policies')
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        packageName: 'com.instagram.android',
        screenKey: 'reels',
        friendlyName: 'Reels',
        timeLimitMinutes: 15,
      })
      .expect(200);

    expect(res.body.success).toBe(true);
    expect(res.body.policy.screenKey).toBe('reels');

    screenPolicyId = res.body.policy._id;
  });

  test('GET /api/v1/screen-policies returns the created screen policy', async () => {
    const res = await api
      .get('/api/v1/screen-policies?packageName=com.instagram.android')
      .set('Authorization', `Bearer ${accessToken}`)
      .expect(200);

    expect(res.body.success).toBe(true);
    expect(res.body.policies.some((p) => p.screenKey === 'reels')).toBe(true);
  });

  test('POST /api/v1/screen-policies/sync applies a batch update', async () => {
    const res = await api
      .post('/api/v1/screen-policies/sync')
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        policies: [
          {
            packageName: 'com.instagram.android',
            screenKey: 'reels',
            friendlyName: 'Reels',
            timeLimitMinutes: 20,
            isActive: true,
            // Use a future timestamp so the server always accepts our update.
            localLastUpdated: new Date(Date.now() + 5 * 60 * 1000).toISOString(),
          },
        ],
      })
      .expect(200);

    expect(res.body.success).toBe(true);
    expect(res.body.applied + res.body.skipped).toBeGreaterThanOrEqual(1);
  });

  test('POST /api/v1/sync reports usage and returns active policies', async () => {
    const res = await api
      .post('/api/v1/sync')
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        deviceId: 'integration-device-123',
        usageReport: [
          { packageName: 'com.instagram.android', usedMs: 600000 },
        ],
      })
      .expect(200);

    expect(res.body.success).toBe(true);
    expect(res.body).toHaveProperty('strictMode');
    expect(res.body).toHaveProperty('policies');
    expect(res.body).toHaveProperty('timestamp');
  });

  test('GET /api/v1/sync/status returns sync status', async () => {
    const res = await api
      .get('/api/v1/sync/status')
      .set('Authorization', `Bearer ${accessToken}`)
      .expect(200);

    expect(res.body.success).toBe(true);
    expect(res.body).toHaveProperty('activePolicies');
    expect(res.body).toHaveProperty('lastSyncAt');
  });

  test('DELETE /api/v1/screen-policies/:id removes the screen policy', async () => {
    const res = await api
      .delete(`/api/v1/screen-policies/${screenPolicyId}`)
      .set('Authorization', `Bearer ${accessToken}`)
      .expect(200);

    expect(res.body.success).toBe(true);
  });

  test('DELETE /api/v1/policies/:id removes the app policy', async () => {
    const res = await api
      .delete(`/api/v1/policies/${policyId}`)
      .set('Authorization', `Bearer ${accessToken}`)
      .expect(200);

    expect(res.body.success).toBe(true);
  });
});
