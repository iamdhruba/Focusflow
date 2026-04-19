@echo off
echo ================================
echo Running FocusFlow Test Suite
echo ================================

REM Backend Tests
echo.
echo Backend API Tests
echo -------------------
cd backend
call npm test

REM Flutter Tests
echo.
echo Flutter Tests
echo ----------------
cd ..\focusflow
call flutter test

echo.
echo All tests completed!
pause
