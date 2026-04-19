const mongoose = require('mongoose');

/**
 * Connects to MongoDB using the URI from environment variables.
 * Implements exponential back-off retry on failure.
 */
const connectDB = async () => {
  const MONGO_URI = process.env.MONGO_URI;

  if (!MONGO_URI) {
    console.error('❌  MONGO_URI is not defined in .env');
    process.exit(1);
  }

  try {
    const conn = await mongoose.connect(MONGO_URI, {
      // Mongoose 7+ drops deprecated options — these are safe defaults
      serverSelectionTimeoutMS: 5000,
      socketTimeoutMS: 45000,
    });

    console.log(`✅  MongoDB connected: ${conn.connection.host}`);
  } catch (err) {
    console.error(`❌  MongoDB connection error: ${err.message}`);
    // Retry after 5 seconds
    setTimeout(connectDB, 5000);
  }
};

// Graceful shutdown
process.on('SIGINT', async () => {
  await mongoose.connection.close();
  console.log('MongoDB connection closed (SIGINT)');
  process.exit(0);
});

module.exports = connectDB;
