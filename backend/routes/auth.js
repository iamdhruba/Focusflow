const express = require('express');
const { body } = require('express-validator');
const {
  register,
  login,
  getMe,
  refresh,
  updateStrictMode,
  forgotPassword,
  resetPassword,
  forgotPIN,
  resetPIN,
} = require('../controllers/authController');
const { protect } = require('../middleware/auth');

const router = express.Router();

// ─── Validation Rules ─────────────────────────────────────────────────────────

const registerValidation = [
  body('name').trim().notEmpty().withMessage('Name is required'),
  body('email').isEmail().withMessage('Valid email is required').normalizeEmail(),
  body('password')
    .isLength({ min: 8 })
    .withMessage('Password must be at least 8 characters')
    .matches(/^(?=.*[A-Za-z])(?=.*\d)/)
    .withMessage('Password must contain at least one letter and one number'),
];

const loginValidation = [
  body('email').isEmail().withMessage('Valid email is required').normalizeEmail(),
  body('password').notEmpty().withMessage('Password is required'),
];

const recoveryValidation = [
  body('email').isEmail().withMessage('Valid email is required').normalizeEmail(),
];

const resetPasswordValidation = [
  body('password')
    .isLength({ min: 8 })
    .withMessage('Password must be at least 8 characters')
    .matches(/^(?=.*[A-Za-z])(?=.*\d)/)
    .withMessage('Password must contain at least one letter and one number'),
];

const resetPinValidation = [
  body('code').notEmpty().withMessage('Reset code is required'),
  body('newPin')
    .isLength({ min: 4, max: 8 })
    .withMessage('PIN must be between 4 and 8 digits'),
];

// ─── Routes ──────────────────────────────────────────────────────────────────

router.post('/register', registerValidation, register);
router.post('/login', loginValidation, login);
router.post('/refresh', refresh);
router.get('/me', protect, getMe);
router.patch('/strict-mode', protect, updateStrictMode);

// ─── Recovery ────────────────────────────────────────────────────────────────
router.post('/forgot-password', recoveryValidation, forgotPassword);
router.put('/reset-password/:resetToken', resetPasswordValidation, resetPassword);
router.post('/forgot-pin', protect, forgotPIN);
router.put('/reset-pin', [protect, resetPinValidation], resetPIN);

module.exports = router;
