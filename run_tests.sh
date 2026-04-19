#!/bin/bash

echo "================================"
echo "Running FocusFlow Test Suite"
echo "================================"

# Backend Tests
echo ""
echo "📦 Backend API Tests"
echo "-------------------"
cd backend
npm test

# Flutter Tests
echo ""
echo "📱 Flutter Tests"
echo "----------------"
cd ../focusflow
flutter test

echo ""
echo "✅ All tests completed!"
