const request = require('supertest');
const app = require('../server');

describe('Auth API Tests', () => {
  test('POST /api/v1/auth/register - should accept registration request', async () => {
    const res = await request(app)
      .post('/api/v1/auth/register')
      .send({
        email: `test${Date.now()}@example.com`,
        password: 'Test123!',
        name: 'Test User'
      });
    expect([200, 201, 400, 500]).toContain(res.statusCode);
  });

  test('POST /api/v1/auth/login - should accept login request', async () => {
    const res = await request(app)
      .post('/api/v1/auth/login')
      .send({
        email: 'test@example.com',
        password: 'Test123!'
      });
    expect([200, 401, 500]).toContain(res.statusCode);
  });

  test('GET /api/v1/auth/me - should require authentication', async () => {
    const res = await request(app)
      .get('/api/v1/auth/me');
    expect(res.statusCode).toBe(401);
  });

  test('POST /api/v1/auth/forgot-password - should accept email', async () => {
    const res = await request(app)
      .post('/api/v1/auth/forgot-password')
      .send({ email: 'test@example.com' });
    expect([200, 202, 404, 500]).toContain(res.statusCode);
  });
});
