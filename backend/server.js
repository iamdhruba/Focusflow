/**
 * FocusFlow Backend — Entry Point
 * Node.js + Express + MongoDB REST API
 */

require('dotenv').config();
const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const morgan = require('morgan');
const rateLimit = require('express-rate-limit');
const connectDB = require('./config/db');

// ─── Connect to Database ──────────────────────────────────────────────────────
connectDB();

// ─── Initialize Express ──────────────────────────────────────────────────────
const app = express();

// ─── Security & Middleware ───────────────────────────────────────────────────

// Security headers (XSS, Clickjacking, etc)
app.use(helmet());

// Rate Limiting: Prevent brute-force on API
const limiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 mins
  max: 100, // 100 requests per IP
  standardHeaders: true,
  legacyHeaders: false,
  message: 'Too many requests, please try again later.',
});
app.use('/api', limiter);

// Strict rate limit for Auth (Login/Register)
const authLimiter = rateLimit({
  windowMs: 60 * 60 * 1000, // 1 hour
  max: 10, // 10 attempts
  message: 'Too many attempts, please try again in an hour.',
});
app.use('/api/v1/auth/login', authLimiter);
app.use('/api/v1/auth/register', authLimiter);

// CORS — allow configured origins
const allowedOrigins = (process.env.ALLOWED_ORIGINS || '')
  .split(',')
  .map((o) => o.trim())
  .filter(Boolean);

app.use(
  cors({
    origin: (origin, callback) => {
      // Allow all in development, otherwise check allowedOrigins
      if (process.env.NODE_ENV === 'development' || !origin) {
        return callback(null, true);
      }
      if (allowedOrigins.length === 0 || allowedOrigins.includes(origin)) {
        return callback(null, true);
      }
      callback(new Error(`CORS policy: origin ${origin} is not allowed`));
    },
    credentials: true,
  })
);

// ─── Body Parsing ─────────────────────────────────────────────────────────────
app.use(express.json({ limit: '1mb' }));
app.use(express.urlencoded({ extended: true }));

// ─── Logging ──────────────────────────────────────────────────────────────────
if (process.env.NODE_ENV !== 'test') {
  app.use(morgan(process.env.NODE_ENV === 'production' ? 'combined' : 'dev'));
}

// ─── Health Check ─────────────────────────────────────────────────────────────
app.get('/health', (req, res) => {
  res.status(200).json({
    status: 'ok',
    uptime: process.uptime(),
    timestamp: new Date().toISOString(),
    environment: process.env.NODE_ENV,
  });
});

// ─── API Routes ───────────────────────────────────────────────────────────────
app.use('/api/v1/auth', require('./routes/auth'));
app.use('/api/v1/policies', require('./routes/policy'));
app.use('/api/v1/sync', require('./routes/sync'));

// ─── 404 Handler ──────────────────────────────────────────────────────────────
app.use((req, res) => {
  res.status(404).json({ success: false, message: `Route ${req.originalUrl} not found` });
});

// ─── Global Error Handler ─────────────────────────────────────────────────────
// eslint-disable-next-line no-unused-vars
app.use((err, req, res, next) => {
  console.error('Unhandled error:', err);
  res.status(500).json({
    success: false,
    message: process.env.NODE_ENV === 'production' ? 'Internal server error' : err.message,
  });
});

// ─── Start Server ─────────────────────────────────────────────────────────────
const PORT = process.env.PORT || 5000;
app.listen(PORT, () => {
  console.log(`🚀  FocusFlow API running on port ${PORT} [${process.env.NODE_ENV}]`);
  console.log(`    Health: http://localhost:${PORT}/health`);
  console.log(`    Auth:   http://localhost:${PORT}/api/v1/auth`);
  console.log(`    Sync:   http://localhost:${PORT}/api/v1/sync`);
});

module.exports = app;
