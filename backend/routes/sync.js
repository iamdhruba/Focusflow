const express = require('express');
const { sync, getStatus } = require('../controllers/syncController');
const { protect } = require('../middleware/auth');

const router = express.Router();

// All sync routes require authentication
router.use(protect);

router.post('/', sync);
router.get('/status', getStatus);

module.exports = router;
