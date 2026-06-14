import { config } from './config.js';
import { connect, close } from './db/client.js';
import { ensureMemberIndexes } from './db/memberStore.js';
import { createApp } from './app.js';

/**
 * Startup sequence: connect to MongoDB first (fail fast if unreachable), then
 * start the HTTP server. Shuts down gracefully on SIGINT/SIGTERM.
 */
async function main() {
  try {
    await connect();
    await ensureMemberIndexes();
    console.log(`✓ Connected to MongoDB (db: ${config.mongoDb})`);
  } catch (err) {
    console.error('✗ Failed to connect to MongoDB:', err.message);
    process.exit(1);
  }

  const app = createApp();
  const server = app.listen(config.port, config.host, () => {
    console.log(`✓ ClearSplit API listening on http://${config.host}:${config.port}`);
  });

  const shutdown = async (signal) => {
    console.log(`\n${signal} received, shutting down...`);
    server.close(async () => {
      await close();
      console.log('✓ Closed HTTP server and MongoDB connection');
      process.exit(0);
    });
    // Force-exit if graceful shutdown stalls.
    setTimeout(() => process.exit(1), 10000).unref();
  };

  process.on('SIGINT', () => shutdown('SIGINT'));
  process.on('SIGTERM', () => shutdown('SIGTERM'));
}

main();
