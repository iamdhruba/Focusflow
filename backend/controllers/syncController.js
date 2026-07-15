const AppPolicy = require('../models/AppPolicy');
const User = require('../models/User');
const { validationResult } = require('express-validator');

/**
 * POST /api/v1/sync
 *
 * The core device-to-server sync endpoint.
 */
exports.sync = async (req, res) => {
  const errors = validationResult(req);
  if (!errors.isEmpty()) {
    return res.status(400).json({ success: false, errors: errors.array() });
  }

  const { deviceId, usageReport } = req.body;

  if (!Array.isArray(usageReport)) {
    return res.status(400).json({
      success: false,
      message: 'usageReport must be an array',
    });
  }

  try {
    // ── Step 1: Update user's device + sync timestamp ─────────────────────
    await User.findByIdAndUpdate(req.user.id, {
      deviceId: deviceId || req.user.deviceId,
      lastSyncAt: new Date(),
    });

    // ── Step 2: Batch-update usage stats ─────────────────────────────────
    const bulkOps = usageReport.map((entry) => ({
      updateOne: {
        filter: { userId: req.user.id, packageName: entry.packageName },
        update: {
          $set: {
            todayUsageMs: entry.usedMs,
            lastUsageSyncAt: new Date(),
          },
        },
        // Don't create new policy documents from sync — only update existing ones
        upsert: false,
      },
    }));

    if (bulkOps.length > 0) {
      await AppPolicy.bulkWrite(bulkOps);
    }

    // ── Step 3: Fetch updated policies to return to device ────────────────
    const policies = await AppPolicy.find({ userId: req.user.id, isActive: true });

    // ── Step 4: Fetch user settings ──────────────────────────────────────
    const user = await User.findById(req.user.id).select('strictMode dailyGoalMinutes');
    
    // Calculate total usage for global limit check
    const totalUsageMs = policies.reduce((sum, p) => sum + p.todayUsageMs, 0);
    const globalLimitMs = user.dailyGoalMinutes * 60 * 1000;
    const isGlobalLimitExceeded = totalUsageMs >= globalLimitMs;

    res.status(200).json({
      success: true,
      strictMode: user.strictMode,
      dailyGoalMinutes: user.dailyGoalMinutes,
      masterBlock: isGlobalLimitExceeded, // Global kill-switch
      totalUsageMs,
      policies: policies.map((p) => ({
        id: p._id,
        packageName: p.packageName,
        appName: p.appName,
        timeLimitMinutes: p.timeLimitMinutes,
        resetCycle: p.resetCycle,
        isActive: p.isActive,
        todayUsageMs: p.todayUsageMs,
        isOverLimit: p.isOverLimit || isGlobalLimitExceeded, // Individual app is over limit OR global is over limit
        remainingMs: p.remainingMs,
      })),
      timestamp: new Date().toISOString(),
    });
  } catch (err) {
    console.error('Sync error:', err);
    res.status(500).json({ success: false, message: 'Server error during sync' });
  }
};

/**
 * GET /api/v1/sync/status
 * Returns a lightweight sync status — last sync time and policy count.
 * Useful for the dashboard.
 */
exports.getStatus = async (req, res) => {
  try {
    const user = await User.findById(req.user.id).select('lastSyncAt deviceId strictMode');
    const policyCount = await AppPolicy.countDocuments({ userId: req.user.id, isActive: true });

    res.status(200).json({
      success: true,
      lastSyncAt: user.lastSyncAt,
      deviceId: user.deviceId,
      strictMode: user.strictMode,
      activePolicies: policyCount,
    });
  } catch (err) {
    res.status(500).json({ success: false, message: 'Server error' });
  }
};
