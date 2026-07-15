const express = require('express');
const { body } = require('express-validator');
const {
  getScreenPolicies,
  upsertScreenPolicy,
  toggleScreenPolicy,
  deleteScreenPolicy,
  syncScreenPolicies,
} = require('../controllers/screenPolicyController');
const { protect } = require('../middleware/auth');

const router = express.Router();

// All screen-policy routes require authentication
router.use(protect);

const screenPolicyValidation = [
  body('packageName').trim().notEmpty().withMessage('Package name is required'),
  body('screenKey').trim().notEmpty().withMessage('Screen key is required'),
  body('friendlyName').trim().notEmpty().withMessage('Friendly name is required'),
  body('timeLimitMinutes')
    .optional({ nullable: true })
    .isInt({ min: 0 })
    .withMessage('Time limit must be a non-negative integer'),
];

// Bulk delta-sync. The body's `policies` array is itself an array, so
// express-validator needs an extra `.isArray()` rule on the parent rather
// than `.trim()` on the leaves. Looser per-row shape: deleted=true rows
// skip the friendlyName requirement.
const syncPayloadValidation = [
  body('policies').isArray({ min: 0, max: 200 }).withMessage('policies must be an array of 0-200 rows'),
];

router.get('/', getScreenPolicies);
router.post('/', screenPolicyValidation, upsertScreenPolicy);
router.post('/sync', syncPayloadValidation, syncScreenPolicies);
router.patch('/:id/toggle', toggleScreenPolicy);
router.delete('/:id', deleteScreenPolicy);

module.exports = router;
