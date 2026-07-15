const AppScreenPolicy = require('../models/AppScreenPolicy');
const { validationResult } = require('express-validator');

/**
 * GET /api/v1/screen-policies?packageName=<pkg>
 *
 * Optional `packageName` query param narrows results to a single host app.
 * Returns all screen policies for the authenticated user otherwise.
 */
exports.getScreenPolicies = async (req, res) => {
  try {
    const filter = { userId: req.user.id };
    if (req.query.packageName) {
      filter.packageName = String(req.query.packageName).trim();
    }
    const policies = await AppScreenPolicy.find(filter).sort({
      packageName: 1,
      friendlyName: 1,
    });
    res.status(200).json({
      success: true,
      count: policies.length,
      policies,
    });
  } catch (err) {
    console.error('Get screen-policies error:', err);
    res.status(500).json({ success: false, message: 'Server error' });
  }
};

/**
 * POST /api/v1/screen-policies
 *
 * Upsert keyed by (userId, packageName, screenKey).
 * Body fields required: packageName, screenKey, friendlyName.
 * Body fields optional: timeLimitMinutes (default 0 = full block),
 *                       resetCycle (default 'daily'),
 *                       isActive (default true).
 */
exports.upsertScreenPolicy = async (req, res) => {
  const errors = validationResult(req);
  if (!errors.isEmpty()) {
    return res.status(400).json({ success: false, errors: errors.array() });
  }

  const {
    packageName,
    screenKey,
    friendlyName,
    timeLimitMinutes,
    resetCycle,
    isActive,
  } = req.body;

  try {
    const policy = await AppScreenPolicy.findOneAndUpdate(
      { userId: req.user.id, packageName, screenKey },
      {
        $set: {
          friendlyName,
          timeLimitMinutes: timeLimitMinutes ?? 0,
          resetCycle: resetCycle || 'daily',
          isActive: isActive !== undefined ? isActive : true,
        },
      },
      { new: true, upsert: true, runValidators: true, setDefaultsOnInsert: true }
    );

    res.status(200).json({ success: true, policy });
  } catch (err) {
    console.error('Upsert screen-policy error:', err);
    res.status(500).json({ success: false, message: 'Server error' });
  }
};

/**
 * PATCH /api/v1/screen-policies/:id/toggle
 * Toggle isActive state for a single screen rule.
 */
exports.toggleScreenPolicy = async (req, res) => {
  try {
    const policy = await AppScreenPolicy.findOne({
      _id: req.params.id,
      userId: req.user.id,
    });
    if (!policy) {
      return res.status(404).json({ success: false, message: 'Screen policy not found' });
    }
    policy.isActive = !policy.isActive;
    await policy.save();
    res.status(200).json({
      success: true,
      message: `Screen policy ${policy.isActive ? 'activated' : 'deactivated'}`,
      policy,
    });
  } catch (err) {
    console.error('Toggle screen-policy error:', err);
    res.status(500).json({ success: false, message: 'Server error' });
  }
};

/**
 * DELETE /api/v1/screen-policies/:id
 * Permanently remove a screen rule.
 */
exports.deleteScreenPolicy = async (req, res) => {
  try {
    const policy = await AppScreenPolicy.findOneAndDelete({
      _id: req.params.id,
      userId: req.user.id,
    });
    if (!policy) {
      return res.status(404).json({ success: false, message: 'Screen policy not found' });
    }
    res.status(200).json({ success: true, message: 'Screen policy removed' });
  } catch (err) {
    console.error('Delete screen-policy error:', err);
    res.status(500).json({ success: false, message: 'Server error' });
  }
};

/**
 * POST /api/v1/screen-policies/sync
 *
 * Bulk delta-sync from a single client device. Used by the foreground
 * (cold-launch + on-upsert + on-foreground) and WorkManager (every ~15 min)
 * sync jobs to propagate offline edits to the server.
 *
 * Critical for the "user wiped app data" recovery flow: if a client has
 * been offline for weeks building up local rules, this endpoint gets them
 * onto the server so a fresh install after a wipe can recover via the
 * existing GET /api/v1/screen-policies fetch.
 *
 * Request body:
 * {
 *   policies: [
 *     {
 *       packageName: string,
 *       screenKey: string,
 *       friendlyName: string,
 *       timeLimitMinutes: number,    // 0 = full block
 *       isActive: boolean,
 *       localLastUpdated: ISOString,  // client-side timestamp at edit time
 *       deleted?: boolean             // explicit tombstone
 *     }
 *   ]
 * }
 *
 * Per-row outcome (`results[]`):
 *   - `applied`              → server accepted the candidate
 *   - `skipped_newer`        → server has a newer `updatedAt`; client must
 *                              re-fetch via GET to see authoritative state.
 *                              This is the multi-device conflict signal.
 *   - `deleted`              → row was tombstoned by this request
 *   - `noop`                 → row already matched; no write needed
 *
 * LWW policy: server compares `updatedAt` (Mongoose-managed) against
 * `localLastUpdated` (caller-supplied). Caller wins iff `localLastUpdated >
 * server.updatedAt`. The ≥ comparison: caller-matches-server is treated as
 * `noop` so two devices can race their final edits without trampling each
 * other.
 */
exports.syncScreenPolicies = async (req, res) => {
  const errors = validationResult(req);
  if (!errors.isEmpty()) {
    return res.status(400).json({ success: false, errors: errors.array() });
  }

  const incoming = Array.isArray(req.body?.policies) ? req.body.policies : [];
  if (incoming.length === 0) {
    return res.status(200).json({
      success: true,
      serverTime: new Date().toISOString(),
      applied: 0,
      skipped: 0,
      deleted: 0,
      results: [],
    });
  }

  // Defensive: cap so a malicious client can't blow the request budget.
  const MAX_BATCH = 200;
  if (incoming.length > MAX_BATCH) {
    return res.status(413).json({
      success: false,
      message: `Batch too large (max ${MAX_BATCH} policies per call)`,
    });
  }

  try {
    const results = [];
    for (const row of incoming) {
      const { packageName, screenKey, deleted, localLastUpdated } = row;
      if (!packageName || !screenKey) {
        results.push({
          packageName: packageName || null,
          screenKey: screenKey || null,
          status: 'invalid',
          reason: 'missing packageName or screenKey',
        });
        continue;
      }

      const existing = await AppScreenPolicy.findOne({
        userId: req.user.id,
        packageName,
        screenKey,
      });

      // ── Tombstone path ─────────────────────────────────────────────────
      if (deleted === true) {
        if (!existing) {
          results.push({
            packageName,
            screenKey,
            status: 'noop',
            reason: 'already absent',
          });
          continue;
        }
        await AppScreenPolicy.findOneAndDelete({
          _id: existing._id,
        });
        results.push({
          packageName,
          screenKey,
          status: 'deleted',
          serverPolicy: null,
        });
        continue;
      }

      // ── Upsert path with LWW sanity ────────────────────────────────────
      const serverUpdatedAt = existing ? existing.updatedAt : null;
      const candidateAt = localLastUpdated ? new Date(localLastUpdated) : null;

      if (
        existing &&
        candidateAt &&
        serverUpdatedAt &&
        serverUpdatedAt.getTime() >= candidateAt.getTime()
      ) {
        results.push({
          packageName,
          screenKey,
          status: 'skipped_newer',
          serverPolicy: existing,
          serverUpdatedAt,
        });
        continue;
      }

      const saved = await AppScreenPolicy.findOneAndUpdate(
        { userId: req.user.id, packageName, screenKey },
        {
          $set: {
            friendlyName: row.friendlyName ?? existing?.friendlyName ?? screenKey,
            timeLimitMinutes:
              row.timeLimitMinutes ?? existing?.timeLimitMinutes ?? 0,
            isActive:
              row.isActive !== undefined
                ? row.isActive
                : existing
                  ? existing.isActive
                  : true,
          },
        },
        {
          new: true,
          upsert: true,
          runValidators: true,
          setDefaultsOnInsert: true,
        }
      );

      results.push({
        packageName,
        screenKey,
        status: existing ? 'applied' : 'applied',
        serverPolicy: saved,
      });
    }

    const counts = results.reduce(
      (acc, r) => {
        if (r.status === 'applied' || r.status === 'noop') acc.applied += 1;
        else if (r.status === 'deleted') acc.deleted += 1;
        else if (
          r.status === 'skipped_newer' ||
          r.status === 'invalid'
        )
          acc.skipped += 1;
        return acc;
      },
      { applied: 0, deleted: 0, skipped: 0 }
    );

    res.status(200).json({
      success: true,
      serverTime: new Date().toISOString(),
      ...counts,
      results,
    });
  } catch (err) {
    console.error('Sync screen-policies error:', err);
    res.status(500).json({ success: false, message: 'Server error' });
  }
};
