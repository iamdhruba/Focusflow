const request = require('supertest');
const app = require('./server');

async function testRegistration() {
  console.log('Testing user registration...\n');
  
  const testUser = {
    name: 'Test User',
    email: `test${Date.now()}@example.com`,
    password: 'Test123!'
  };

  console.log('Sending registration request:', testUser);
  
  const res = await request(app)
    .post('/api/v1/auth/register')
    .send(testUser);

  console.log('\nResponse Status:', res.statusCode);
  console.log('Response Body:', JSON.stringify(res.body, null, 2));

  if (res.statusCode === 201) {
    console.log('\n✅ Registration successful!');
    console.log('Access Token:', res.body.accessToken ? 'Present' : 'Missing');
    console.log('User ID:', res.body.user?.id);
  } else {
    console.log('\n❌ Registration failed!');
    console.log('Error:', res.body.message);
    if (res.body.debug_message) {
      console.log('Debug:', res.body.debug_message);
    }
  }

  process.exit(0);
}

testRegistration().catch(err => {
  console.error('Test error:', err);
  process.exit(1);
});
