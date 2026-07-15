const jwt = require('jsonwebtoken');
const crypto = require('crypto');
const { validationResult } = require('express-validator');
const User = require('../models/User');
const sendEmail = require('../utils/sendEmail');

// ─── Helpers ─────────────────────────────────────────────────────────────────

/**
 * Generate a signed JWT access token for a user.
 * @param {string} id - MongoDB user ID
 * @returns {string} Signed JWT
 */
const generateAccessToken = (id) =>
  jwt.sign({ id }, process.env.JWT_SECRET, {
    expiresIn: process.env.JWT_EXPIRES_IN || '7d',
  });

/**
 * Generate a signed JWT refresh token.
 * @param {string} id
 * @returns {string}
 */
const generateRefreshToken = (id) =>
  jwt.sign({ id }, process.env.JWT_REFRESH_SECRET || process.env.JWT_SECRET, {
    expiresIn: process.env.JWT_REFRESH_EXPIRES_IN || '30d',
  });

/**
 * Send a token response with the user object.
 * @param {object} user - Mongoose user document
 * @param {number} statusCode - HTTP status code
 * @param {object} res - Express response object
 */
const sendTokenResponse = (user, statusCode, res) => {
  const accessToken = generateAccessToken(user._id.toString());
  const refreshToken = generateRefreshToken(user._id.toString());

  res.status(statusCode).json({
    success: true,
    accessToken,
    refreshToken,
    user: {
      id: user._id,
      name: user.name,
      email: user.email,
      strictMode: user.strictMode,
      dailyGoalMinutes: user.dailyGoalMinutes,
      deviceId: user.deviceId,
      lastSyncAt: user.lastSyncAt,
      createdAt: user.createdAt,
    },
  });
};

// ─── Controllers ─────────────────────────────────────────────────────────────

/**
 * POST /api/v1/auth/register
 * Register a new user account.
 */
exports.register = async (req, res) => {
  console.log('📝 Signup Attempt:', { name: req.body.name, email: req.body.email });
  // Validate incoming fields
  const errors = validationResult(req);
  if (!errors.isEmpty()) {
    return res.status(400).json({ success: false, errors: errors.array() });
  }

  const { name, email, password } = req.body;

  try {
    // Check for duplicate email
    const existing = await User.findOne({ email: email.toLowerCase() });
    if (existing) {
      return res.status(409).json({
        success: false,
        message: 'An account with this email already exists',
      });
    }

    const user = await User.create({ name, email, password });
    console.log(`👤 User registered: ${user.email}`);
    sendTokenResponse(user, 201, res);
  } catch (err) {
    console.error('CRITICAL REGISTRATION ERROR:', err);
    res.status(500).json({ 
      success: false, 
      message: 'Server error during registration',
      debug_message: err.message,
      debug_stack: process.env.NODE_ENV === 'development' ? err.stack : undefined
    });
  }
};

/**
 * POST /api/v1/auth/login
 * Authenticate with email + password. Returns JWT tokens.
 */
exports.login = async (req, res) => {
  const errors = validationResult(req);
  if (!errors.isEmpty()) {
    return res.status(400).json({ success: false, errors: errors.array() });
  }

  const { email, password } = req.body;

  try {
    // Explicitly select password (it's hidden by default via `select: false`)
    const user = await User.findOne({ email: email.toLowerCase() }).select('+password');

    if (!user || !(await user.matchPassword(password))) {
      return res.status(401).json({
        success: false,
        message: 'Invalid email or password',
      });
    }

    if (!user.isActive) {
      return res.status(403).json({ success: false, message: 'Account is deactivated' });
    }

    sendTokenResponse(user, 200, res);
  } catch (err) {
    console.error('Login Error:', err);
    res.status(500).json({ success: false, message: 'Server error during login' });
  }
};

/**
 * POST /api/v1/auth/refresh
 * Refresh access token using a valid refresh token.
 */
exports.refresh = async (req, res) => {
  const { refreshToken } = req.body;

  if (!refreshToken) {
    return res.status(401).json({ success: false, message: 'No refresh token provided' });
  }

  try {
    const secret = process.env.JWT_REFRESH_SECRET;
    if (!secret) {
      console.error('CRITICAL: JWT_REFRESH_SECRET is not defined');
      return res.status(500).json({ success: false, message: 'Server configuration error' });
    }

    const decoded = jwt.verify(refreshToken, secret);
    const user = await User.findById(decoded.id);

    if (!user) {
      return res.status(401).json({ success: false, message: 'User no longer exists' });
    }

    if (!user.isActive) {
      return res.status(403).json({ success: false, message: 'Account is deactivated' });
    }

    const accessToken = generateAccessToken(user._id.toString());
    res.status(200).json({ success: true, accessToken });
  } catch (err) {
    console.error('Refresh Token Error:', err.message);
    return res.status(401).json({ success: false, message: 'Invalid or expired refresh token' });
  }
};

/**
 * GET /api/v1/auth/me
 * Returns the currently authenticated user's profile.
 * Protected route — requires valid JWT.
 */
exports.getMe = async (req, res) => {
  try {
    const user = await User.findById(req.user.id);
    res.status(200).json({
      success: true,
      user: {
        id: user._id,
        name: user.name,
        email: user.email,
        strictMode: user.strictMode,
        dailyGoalMinutes: user.dailyGoalMinutes,
        deviceId: user.deviceId,
        lastSyncAt: user.lastSyncAt,
        createdAt: user.createdAt,
      },
    });
  } catch (err) {
    res.status(500).json({ success: false, message: 'Server error' });
  }
};

/**
 * PATCH /api/v1/auth/strict-mode
 * Toggle strict mode on/off. Requires PIN to disable when already active.
 * Protected route.
 */
exports.updateStrictMode = async (req, res) => {
  const { strictMode, pin, dailyGoalMinutes } = req.body;

  try {
    const user = await User.findById(req.user.id).select('+strictModePIN');

    // If turning OFF strict mode, verify PIN and check cooldown
    if (strictMode === false && user.strictMode) {
      if (!pin) {
        return res.status(400).json({ success: false, message: 'PIN required to process request' });
      }
      const pinValid = await user.matchPIN(pin);
      if (!pinValid) {
        return res.status(403).json({ success: false, message: 'Incorrect PIN' });
      }

      // Check if a cooldown is already in progress
      if (!user.strictModeDisableRequestAt) {
        // Start cooldown
        user.strictModeDisableRequestAt = new Date();
        await user.save();
        return res.status(202).json({
          success: true,
          message: 'Cooldown started. You can disable Strict Mode in 24 hours.',
          cooldownActive: true,
          availableAt: new Date(Date.now() + 24 * 60 * 60 * 1000),
        });
      }

      // Check if 24h has passed
      const cooldownMs = 24 * 60 * 60 * 1000;
      const timePassed = Date.now() - user.strictModeDisableRequestAt.getTime();
      
      if (timePassed < cooldownMs) {
        const remainingHours = Math.ceil((cooldownMs - timePassed) / (60 * 60 * 1000));
        return res.status(403).json({
          success: false,
          message: `Strict Mode is locked. Please wait ${remainingHours} more hours.`,
          cooldownActive: true,
        });
      }

      // Cooldown passed, we can proceed to disable
      user.strictModeDisableRequestAt = null;
    }

    // If enabling strict mode with a new PIN or updating it
    if (strictMode === true && pin) {
      user.strictModePIN = pin;
    }

    // Update daily focus goal if provided
    if (dailyGoalMinutes !== undefined) {
      user.dailyGoalMinutes = dailyGoalMinutes;
    }

    user.strictMode = strictMode ?? user.strictMode;
    await user.save();

    res.status(200).json({
      success: true,
      message: 'Settings updated successfully',
      strictMode: user.strictMode,
      dailyGoalMinutes: user.dailyGoalMinutes,
    });
  } catch (err) {
    console.error('Strict mode error:', err);
    res.status(500).json({ success: false, message: 'Server error' });
  }
};

/**
 * POST /api/v1/auth/forgot-password
 */
exports.forgotPassword = async (req, res) => {
  const errors = validationResult(req);
  if (!errors.isEmpty()) {
    return res.status(400).json({ success: false, errors: errors.array() });
  }
  const { email } = req.body;
  try {
    const user = await User.findOne({ email: email.toLowerCase() });
    if (!user) {
      return res.status(404).json({ success: false, message: 'User not found' });
    }

    const resetToken = user.getResetPasswordToken();
    await user.save();

    const resetUrl = `${req.protocol}://${req.get('host')}/api/v1/auth/reset-password/${resetToken}`;

    const html = `
      <div style="font-family: sans-serif; padding: 20px; border: 1px solid #eee; border-radius: 10px;">
        <h2 style="color: #6200EE;">FocusFlow Password Recovery</h2>
        <p>You requested a password reset. Please use the token below to reset your password:</p>
        <div style="background: #f4f4f4; padding: 15px; border-radius: 5px; font-size: 24px; font-weight: bold; text-align: center; letter-spacing: 2px;">
          ${resetToken}
        </div>
        <p>This token is valid for 10 minutes.</p>
        <p>If you didn't request this, please ignore this email.</p>
        <hr style="border: none; border-top: 1px solid #eee; margin: 20px 0;">
        <small style="color: #888;">Protecting your focus, one app at a time.</small>
      </div>
    `;

    try {
      await sendEmail({
        email: user.email,
        subject: 'FocusFlow Password Reset Token',
        message: `Your password reset token is: ${resetToken}`,
        html,
      });

      res.status(200).json({
        success: true,
        message: 'Recovery email sent successfully.',
      });
    } catch (err) {
      console.error('Email send error:', err);
      user.resetPasswordToken = undefined;
      user.resetPasswordExpire = undefined;
      await user.save();
      return res.status(500).json({ success: false, message: 'Email could not be sent' });
    }
  } catch (err) {
    res.status(500).json({ success: false, message: 'Server error' });
  }
};

/**
 * PUT /api/v1/auth/reset-password/:resetToken
 */
exports.resetPassword = async (req, res) => {
  const errors = validationResult(req);
  if (!errors.isEmpty()) {
    return res.status(400).json({ success: false, errors: errors.array() });
  }
  const resetPasswordToken = crypto
    .createHash('sha256')
    .update(req.params.resetToken)
    .digest('hex');

  try {
    const user = await User.findOne({
      resetPasswordToken,
      resetPasswordExpire: { $gt: Date.now() },
    });

    if (!user) {
      return res.status(400).json({ success: false, message: 'Invalid or expired token' });
    }

    user.password = req.body.password;
    user.resetPasswordToken = undefined;
    user.resetPasswordExpire = undefined;
    await user.save();

    sendTokenResponse(user, 200, res);
  } catch (err) {
    res.status(500).json({ success: false, message: 'Server error' });
  }
};

/**
 * POST /api/v1/auth/forgot-pin
 */
exports.forgotPIN = async (req, res) => {
  try {
    const user = await User.findById(req.user.id);
    const resetToken = user.getResetPINToken();
    await user.save();

    const html = `
      <div style="font-family: sans-serif; padding: 20px; border: 1px solid #eee; border-radius: 10px;">
        <h2 style="color: #6200EE;">FocusFlow PIN Reset</h2>
        <p>Your PIN reset code for Strict Mode is:</p>
        <div style="background: #f4f4f4; padding: 15px; border-radius: 5px; font-size: 32px; font-weight: bold; text-align: center; color: #000; letter-spacing: 5px;">
          ${resetToken}
        </div>
        <p>Enter this code in the app to set a new PIN.</p>
        <p>This code is valid for 10 minutes.</p>
        <hr style="border: none; border-top: 1px solid #eee; margin: 20px 0;">
        <small style="color: #888;">FocusFlow Security Team</small>
      </div>
    `;

    try {
      await sendEmail({
        email: user.email,
        subject: 'FocusFlow PIN Reset Code',
        message: `Your PIN reset code is: ${resetToken}`,
        html,
      });

      res.status(200).json({
        success: true,
        message: 'PIN reset code sent to your email.',
      });
    } catch (err) {
      console.error('Email send error:', err);
      user.resetPINToken = undefined;
      user.resetPINExpire = undefined;
      await user.save();
      return res.status(500).json({ success: false, message: 'Email could not be sent' });
    }
  } catch (err) {
    res.status(500).json({ success: false, message: 'Server error' });
  }
};

/**
 * PUT /api/v1/auth/reset-pin
 */
exports.resetPIN = async (req, res) => {
  const errors = validationResult(req);
  if (!errors.isEmpty()) {
    return res.status(400).json({ success: false, errors: errors.array() });
  }
  const { code, newPin } = req.body;
  const resetPINToken = crypto
    .createHash('sha256')
    .update(code)
    .digest('hex');

  try {
    const user = await User.findById(req.user.id);

    if (user.resetPINToken !== resetPINToken || user.resetPINExpire < Date.now()) {
      return res.status(400).json({ success: false, message: 'Invalid or expired code' });
    }

    user.strictModePIN = newPin;
    user.resetPINToken = undefined;
    user.resetPINExpire = undefined;
    await user.save();

    res.status(200).json({ success: true, message: 'PIN reset successfully' });
  } catch (err) {
    res.status(500).json({ success: false, message: 'Server error' });
  }
};
