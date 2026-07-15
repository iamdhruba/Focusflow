const mongoose = require('mongoose');

/**
 * AppScreenPolicy Schema
 *
 * One rule per in-app screen for a given user.
 * Examples:
 *   { userId: <u>, packageName: "com.instagram.android", screenKey: "reels", friendlyName: "Reels", isActive: true }
 *   { userId: <u>, packageName: "com.zhiliaoapp.musically", screenKey: "fyp",   friendlyName: "For You", isActive: true }
 *
 * Compound unique index on (userId, packageName, screenKey) keeps a user from
 * creating multiple policies for the same screen.
 */
const AppScreenPolicySchema = new mongoose.Schema(
  {
    userId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true,
      index: true,
    },

    // ─── Identifying tuple ──────────────────────────────────────────────────
    packageName: {
      type: String,
      required: [true, 'Package name is required'],
      trim: true,
    },
    screenKey: {
      type: String,
      required: [true, 'Screen key is required'],
      trim: true,
      // e.g. "reels", "stories", "fyp", "explore", "search", "live"
    },
    friendlyName: {
      type: String,
      required: true,
      trim: true,
      // e.g. "Reels", "Stories", "For You", "Explore"
    },

    // ─── Time Policy ────────────────────────────────────────────────────────
    /**
     * Daily time limit in minutes for this screen.
     * 0 = fully blocked (no usage allowed)
     * null = no limit (screen-tracking only)
     */
    timeLimitMinutes: {
      type: Number,
      required: true,
      min: [0, 'Time limit cannot be negative'],
      default: 0,
    },
    resetCycle: {
      type: String,
      enum: ['daily'],
      default: 'daily',
    },

    // ─── Status ────────────────────────────────────────────────────────────
    isActive: {
      type: Boolean,
      default: true,
    },

    // ─── Usage Cache (synced from device) ──────────────────────────────────
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

// One screen policy per (user, app, screen)
AppScreenPolicySchema.index(
  { userId: 1, packageName: 1, screenKey: 1 },
  { unique: true }
);

// Common lookup: "give me all my screen rules for Instagram"
AppScreenPolicySchema.index({ userId: 1, packageName: 1 });

module.exports = mongoose.model('AppScreenPolicy', AppScreenPolicySchema);
