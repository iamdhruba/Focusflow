const express = require('express');
const { sync, getStatus } = require('../controllers/syncController');
const { protect } = require('../middleware/auth');
const { body } = require('express-validator');

const router = express.Router();

// All sync routes require authentication
router.use(protect);

const syncValidation = [
  body('deviceId').trim().notEmpty().withMessage('Device ID is required'),
  body('usageReport').isArray().withMessage('usageReport must be an array'),
  body('usageReport.*.packageName').trim().notEmpty().withMessage('Package name is required'),
  body('usageReport.*.usedMs').isInt({ min: 0 }).withMessage('usedMs must be a non-negative integer'),
];

router.post('/', syncValidation, sync);
router.get('/status', getStatus);

module.exports = router;
