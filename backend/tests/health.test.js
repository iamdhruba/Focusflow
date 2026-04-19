const request = require('supertest');
const app = require('../server');

describe('Health Check Tests', () => {
  test('GET /health - should return server health', async () => {
    const res = await request(app).get('/health');
    expect(res.statusCode).toBe(200);
    expect(res.body).toHaveProperty('status', 'ok');
    expect(res.body).toHaveProperty('uptime');
    expect(res.body).toHaveProperty('timestamp');
  });

  test('GET /invalid-route - should return 404', async () => {
    const res = await request(app).get('/invalid-route');
    expect(res.statusCode).toBe(404);
  });
});
