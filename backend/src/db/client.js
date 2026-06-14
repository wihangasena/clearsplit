import { MongoClient } from 'mongodb';
import { config } from '../config.js';

/**
 * Singleton MongoDB connection. The driver maintains an internal pool, so the
 * whole app shares one MongoClient created at startup.
 */
let client = null;
let db = null;

export async function connect() {
  if (db) return db;
  client = new MongoClient(config.mongoUri, {
    serverSelectionTimeoutMS: 10000,
  });
  await client.connect();
  // Ping to surface auth/network failures immediately rather than on first query.
  await client.db(config.mongoDb).command({ ping: 1 });
  db = client.db(config.mongoDb);
  return db;
}

export function getDb() {
  if (!db) {
    throw new Error('Database not connected. Call connect() during startup.');
  }
  return db;
}

export async function close() {
  if (client) {
    await client.close();
    client = null;
    db = null;
  }
}
