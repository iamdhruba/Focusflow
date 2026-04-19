const request = require('supertest');
const app = require('../server');

describe('Policy API Tests', () => {
  test('POST /api/v1/policies - should require authentication', async () => {
    const res = await request(app)
      .post('/api/v1/policies')
      .send({
        packageName: 'com.example.app',
        appName: 'Test App',
        dailyLimitMinutes: 60,
        isBlocked: false
      });
    expect(res.statusCode).toBe(401);
  });

  test('GET /api/v1/policies - should require authentication', async () => {
    const res = await request(app)
      .get('/api/v1/policies');
    expect(res.statusCode).toBe(401);
  });

  test('PUT /api/v1/policies/:id - should require authentication', async () => {
    const res = await request(app)
      .put('/api/v1/policies/123')
      .send({ dailyLimitMinutes: 30 });
    expect(res.statusCode).toBe(401);
  });

  test('DELETE /api/v1/policies/:id - should require authentication', async () => {
    const res = await request(app)
      .delete('/api/v1/policies/123');
    expect(res.statusCode).toBe(401);
  });
});
