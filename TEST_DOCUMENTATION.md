# FocusFlow Test Suite

Comprehensive tests for all features of the FocusFlow project.

## Test Coverage

### Backend API Tests (Node.js + Jest + Supertest)

#### 1. Authentication Tests (`tests/auth.test.js`)
- ✅ User registration
- ✅ User login
- ✅ Get current user profile
- ✅ Forgot password flow

#### 2. Policy Tests (`tests/policy.test.js`)
- ✅ Create app policy
- ✅ Get all policies
- ✅ Update policy
- ✅ Delete policy

#### 3. Sync Tests (`tests/sync.test.js`)
- ✅ Sync usage data
- ✅ Get sync status

#### 4. Health Check Tests (`tests/health.test.js`)
- ✅ Server health endpoint
- ✅ 404 error handling

### Flutter Tests (Dart + flutter_test)

#### 1. Auth Tests (`test/auth_test.dart`)
- ✅ Login functionality
- ✅ Registration functionality
- ✅ Auth provider state management

#### 2. Policy Tests (`test/policy_test.dart`)
- ✅ Policy sync with usage data
- ✅ Empty usage report handling

#### 3. Storage Tests (`test/storage_test.dart`)
- ✅ Save/retrieve JWT token
- ✅ Save/retrieve user ID
- ✅ Onboarding flag management
- ✅ Clear all data

#### 4. Native Channel Tests (`test/native_channel_test.dart`)
- ✅ Get installed apps
- ✅ Get usage statistics
- ✅ Update blocking rules
- ✅ Check accessibility service
- ✅ Open accessibility settings

#### 5. Widget Tests (`test/widget_test.dart`)
- ✅ WelcomeScreen rendering
- ✅ GradientButton component
- ✅ GlassCard component

## Running Tests

### Run All Tests
```bash
# Windows
run_tests.bat

# Linux/Mac
./run_tests.sh
```

### Run Backend Tests Only
```bash
cd backend
npm test
```

### Run Flutter Tests Only
```bash
cd focusflow
flutter test
```

### Run Specific Test File
```bash
# Backend
cd backend
npm test -- tests/auth.test.js

# Flutter
cd focusflow
flutter test test/auth_test.dart
```

## Setup Requirements

### Backend
1. Install dependencies:
   ```bash
   cd backend
   npm install
   ```

2. Configure environment:
   - Copy `.env.example` to `.env`
   - Set MongoDB connection string
   - Set JWT secret

### Flutter
1. Install dependencies:
   ```bash
   cd focusflow
   flutter pub get
   ```

2. Configure environment:
   - Copy `.env.example` to `.env`
   - Set API base URL

## Features Tested

### Core Features
- ✅ User authentication (register, login, logout)
- ✅ Password reset flow
- ✅ JWT token management
- ✅ Secure storage
- ✅ App policy CRUD operations
- ✅ Usage data synchronization
- ✅ Background sync (WorkManager)
- ✅ Native Android integration
- ✅ Accessibility service
- ✅ App blocking functionality
- ✅ UI components and widgets
- ✅ Navigation and routing
- ✅ State management (Riverpod)

### API Endpoints Tested
- `POST /api/v1/auth/register`
- `POST /api/v1/auth/login`
- `GET /api/v1/auth/me`
- `POST /api/v1/auth/forgot-password`
- `POST /api/v1/policies`
- `GET /api/v1/policies`
- `PUT /api/v1/policies/:id`
- `DELETE /api/v1/policies/:id`
- `POST /api/v1/sync`
- `GET /api/v1/sync/status`
- `GET /health`

## Test Results

Run the tests to see detailed results. All tests are designed to validate:
- Correct HTTP status codes
- Expected response structure
- Error handling
- Authentication/authorization
- Data persistence
- Platform integration
