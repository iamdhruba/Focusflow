const AppPolicy = require('../models/AppPolicy');
const { validationResult } = require('express-validator');

/**
 * GET /api/v1/policies
 * Retrieve all app policies for the authenticated user.
 */
exports.getPolicies = async (req, res) => {
  try {
    const policies = await AppPolicy.find({ userId: req.user.id }).sort({ appName: 1 });
    res.status(200).json({ success: true, count: policies.length, policies });
  } catch (err) {
    console.error('Get policies error:', err);
    res.status(500).json({ success: false, message: 'Server error' });
  }
};

/**
 * POST /api/v1/policies
 * Create or update (upsert) a policy for a specific app.
 * If a policy for the same packageName already exists, it's updated.
 */
exports.upsertPolicy = async (req, res) => {
  const errors = validationResult(req);
  if (!errors.isEmpty()) {
    return res.status(400).json({ success: false, errors: errors.array() });
  }

  const { packageName, appName, timeLimitMinutes, resetCycle, isActive } = req.body;

  try {
    const policy = await AppPolicy.findOneAndUpdate(
      { userId: req.user.id, packageName },
      {
        $set: {
          appName,
          timeLimitMinutes,
          resetCycle: resetCycle || 'daily',
          isActive: isActive !== undefined ? isActive : true,
        },
      },
      { new: true, upsert: true, runValidators: true }
    );

    res.status(200).json({ success: true, policy });
  } catch (err) {
    console.error('Upsert policy error:', err);
    res.status(500).json({ success: false, message: 'Server error' });
  }
};

/**
 * PATCH /api/v1/policies/:id/toggle
 * Toggle the isActive state of a policy.
 */
exports.togglePolicy = async (req, res) => {
  try {
    const policy = await AppPolicy.findOne({ _id: req.params.id, userId: req.user.id });

    if (!policy) {
      return res.status(404).json({ success: false, message: 'Policy not found' });
    }

    policy.isActive = !policy.isActive;
    await policy.save();

    res.status(200).json({
      success: true,
      message: `Policy ${policy.isActive ? 'activated' : 'deactivated'}`,
      policy,
    });
  } catch (err) {
    console.error('Toggle policy error:', err);
    res.status(500).json({ success: false, message: 'Server error' });
  }
};

/**
 * DELETE /api/v1/policies/:id
 * Remove an app policy permanently.
 */
exports.deletePolicy = async (req, res) => {
  try {
    const policy = await AppPolicy.findOneAndDelete({
      _id: req.params.id,
      userId: req.user.id,
    });

    if (!policy) {
      return res.status(404).json({ success: false, message: 'Policy not found' });
    }

    res.status(200).json({ success: true, message: 'Policy removed' });
  } catch (err) {
    console.error('Delete policy error:', err);
    res.status(500).json({ success: false, message: 'Server error' });
  }
};
