const request = require('supertest');
const app = require('../server');

describe('Sync API Tests', () => {
  test('POST /api/v1/sync - should require authentication', async () => {
    const res = await request(app)
      .post('/api/v1/sync')
      .send({
        deviceId: 'test-device-123',
        usageReport: [
          { packageName: 'com.example.app', usedMs: 3600000 }
        ]
      });
    expect(res.statusCode).toBe(401);
  });

  test('GET /api/v1/sync/status - should require authentication', async () => {
    const res = await request(app)
      .get('/api/v1/sync/status');
    expect(res.statusCode).toBe(401);
  });
});
