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
    .withMessage('Password must be at least 8 characters'),
];

const loginValidation = [
  body('email').isEmail().withMessage('Valid email is required').normalizeEmail(),
  body('password').notEmpty().withMessage('Password is required'),
];

// ─── Routes ──────────────────────────────────────────────────────────────────

router.post('/register', registerValidation, register);
router.post('/login', loginValidation, login);
router.post('/refresh', refresh);
router.get('/me', protect, getMe);
router.patch('/strict-mode', protect, updateStrictMode);

// ─── Recovery ────────────────────────────────────────────────────────────────
router.post('/forgot-password', forgotPassword);
router.put('/reset-password/:resetToken', resetPassword);
router.post('/forgot-pin', protect, forgotPIN);
router.put('/reset-pin', protect, resetPIN);

module.exports = router;
