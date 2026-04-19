const express = require('express');
const { body } = require('express-validator');
const {
  getPolicies,
  upsertPolicy,
  togglePolicy,
  deletePolicy,
} = require('../controllers/policyController');
const { protect } = require('../middleware/auth');

const router = express.Router();

// All policy routes require authentication
router.use(protect);

const policyValidation = [
  body('packageName').trim().notEmpty().withMessage('Package name is required'),
  body('appName').trim().notEmpty().withMessage('App name is required'),
  body('timeLimitMinutes')
    .isInt({ min: 0 })
    .withMessage('Time limit must be a non-negative integer'),
];

router.get('/', getPolicies);
router.post('/', policyValidation, upsertPolicy);
router.patch('/:id/toggle', togglePolicy);
router.delete('/:id', deletePolicy);

module.exports = router;
