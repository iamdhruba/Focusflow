const mongoose = require('mongoose');

/**
 * AppPolicy Schema
 * Defines blocking rules for individual apps on a per-user basis.
 * Each document represents one app's policy for one user.
 */
const AppPolicySchema = new mongoose.Schema(
  {
    // ─── Ownership ───────────────────────────────────────────────────────────
    userId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true,
      index: true,
    },

    // ─── App Identity ────────────────────────────────────────────────────────
    packageName: {
      type: String,
      required: [true, 'Package name is required'],
      trim: true,
      // e.g. "com.instagram.android"
    },
    appName: {
      type: String,
      required: [true, 'App display name is required'],
      trim: true,
    },
    appIcon: {
      type: String, // Base64 or URL (optional, sent from device)
      default: null,
    },

    // ─── Time Policy ─────────────────────────────────────────────────────────
    /**
     * Daily time limit in minutes.
     * 0 = fully blocked (no usage allowed)
     * null = no limit (app is whitelisted / tracking only)
     */
    timeLimitMinutes: {
      type: Number,
      required: true,
      min: [0, 'Time limit cannot be negative'],
      default: 60,
    },

    /**
     * When the daily counter resets.
     * 'daily' = midnight local time on device
     */
    resetCycle: {
      type: String,
      enum: ['daily'],
      default: 'daily',
    },

    // ─── Status ──────────────────────────────────────────────────────────────
    isActive: {
      type: Boolean,
      default: true,
    },

    // ─── Usage Cache (updated on sync) ───────────────────────────────────────
    todayUsageMs: {
      type: Number,
      default: 0,
    },
    lastUsageSyncAt: {
      type: Date,
      default: null,
    },
  },
  {
    timestamps: true,
  }
);

// ─── Compound Index ───────────────────────────────────────────────────────────
// One policy per user per package
AppPolicySchema.index({ userId: 1, packageName: 1 }, { unique: true });

// ─── Virtual: isOverLimit ─────────────────────────────────────────────────────
AppPolicySchema.virtual('isOverLimit').get(function () {
  if (this.timeLimitMinutes === 0) return true;
  const limitMs = this.timeLimitMinutes * 60 * 1000;
  return this.todayUsageMs >= limitMs;
});

// ─── Virtual: remainingMs ─────────────────────────────────────────────────────
AppPolicySchema.virtual('remainingMs').get(function () {
  if (this.timeLimitMinutes === 0) return 0;
  const limitMs = this.timeLimitMinutes * 60 * 1000;
  return Math.max(0, limitMs - this.todayUsageMs);
});

// Ensure virtuals are included in JSON output
AppPolicySchema.set('toJSON', { virtuals: true });
AppPolicySchema.set('toObject', { virtuals: true });

module.exports = mongoose.model('AppPolicy', AppPolicySchema);
