const mongoose = require('mongoose');
const bcrypt = require('bcryptjs');
const crypto = require('crypto');

/**
 * User Schema
 * Stores authentication credentials and global strict-mode preference.
 */
const UserSchema = new mongoose.Schema(
  {
    name: {
      type: String,
      required: [true, 'Name is required'],
      trim: true,
      maxlength: [60, 'Name cannot exceed 60 characters'],
    },
    email: {
      type: String,
      required: [true, 'Email is required'],
      unique: true,
      lowercase: true,
      trim: true,
      match: [
        /^\w+([.-]?\w+)*@\w+([.-]?\w+)*(\.\w{2,})+$/,
        'Please provide a valid email address',
      ],
    },
    password: {
      type: String,
      required: [true, 'Password is required'],
      minlength: [8, 'Password must be at least 8 characters'],
      select: false, // Never return password in queries by default
    },

    // ─── Strict Mode ────────────────────────────────────────────────────────
    strictMode: {
      type: Boolean,
      default: false,
    },
    strictModePIN: {
      type: String,
      default: null,
      select: false, // Hidden from default queries
    },
    dailyGoalMinutes: {
      type: Number,
      default: 120, // 2 hours default
    },
    strictModeDisableRequestAt: {
      type: Date,
      default: null,
    },

    // ─── Device Tracking ────────────────────────────────────────────────────
    deviceId: {
      type: String,
      default: null,
    },
    lastSyncAt: {
      type: Date,
      default: null,
    },

    // ─── Recovery ────────────────────────────────────────────────────────────
    resetPasswordToken: String,
    resetPasswordExpire: Date,
    resetPINToken: String,
    resetPINExpire: Date,

    // ─── Soft Delete ────────────────────────────────────────────────────────
    isActive: {
      type: Boolean,
      default: true,
    },
  },
  {
    timestamps: true, // createdAt, updatedAt
  }
);

// ─── Hooks ──────────────────────────────────────────────────────────────────

UserSchema.pre('save', async function () {
  // Hash password if modified
  if (this.isModified('password')) {
    const salt = await bcrypt.genSalt(12);
    this.password = await bcrypt.hash(this.password, salt);
  }

  // Hash strictModePIN if modified
  if (this.isModified('strictModePIN') && this.strictModePIN) {
    const salt = await bcrypt.genSalt(10);
    this.strictModePIN = await bcrypt.hash(this.strictModePIN, salt);
  }
});

// ─── Instance Methods ────────────────────────────────────────────────────────

/**
 * Compare a plain-text password against the stored hash.
 * @param {string} candidatePassword
 * @returns {Promise<boolean>}
 */
UserSchema.methods.matchPassword = async function (candidatePassword) {
  return bcrypt.compare(candidatePassword, this.password);
};

/**
 * Compare a plain-text PIN against the stored strictModePIN hash.
 * @param {string} candidatePIN
 * @returns {Promise<boolean>}
 */
UserSchema.methods.matchPIN = async function (candidatePIN) {
  if (!this.strictModePIN) return false;
  return bcrypt.compare(candidatePIN, this.strictModePIN);
};

/**
 * Generate and hash password reset token.
 */
UserSchema.methods.getResetPasswordToken = function () {
  const resetToken = crypto.randomBytes(20).toString('hex');
  this.resetPasswordToken = crypto
    .createHash('sha256')
    .update(resetToken)
    .digest('hex');
  this.resetPasswordExpire = Date.now() + 10 * 60 * 1000; // 10 minutes
  return resetToken;
};

/**
 * Generate and hash PIN reset token.
 */
UserSchema.methods.getResetPINToken = function () {
  const resetToken = Math.floor(100000 + Math.random() * 900000).toString(); // 6 digit code
  this.resetPINToken = crypto
    .createHash('sha256')
    .update(resetToken)
    .digest('hex');
  this.resetPINExpire = Date.now() + 10 * 60 * 1000; // 10 minutes
  return resetToken;
};

module.exports = mongoose.model('User', UserSchema);
