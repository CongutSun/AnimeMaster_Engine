import { closeSync, mkdirSync, openSync, readFileSync, unlinkSync } from 'node:fs';
import path from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { MobileAuthStore, sessionTtl } from '../bangumi_auth_worker/mobile_auth.mjs';

export function openMobileAuthStore(directory) {
  mkdirSync(directory, { recursive: true, mode: 0o700 });
  const file = path.join(directory, 'sessions.sqlite');
  closeSync(openSync(file, 'a', 0o600));
  const db = new DatabaseSync(file);
  try {
    db.exec('PRAGMA busy_timeout=5000');
    const store = new MobileAuthStore((sql, ...params) => db.prepare(sql).all(...params));
    const legacy = path.join(directory, 'store.json');
    db.exec('BEGIN IMMEDIATE');
    let imported = false;
    try {
      if (!db.prepare('PRAGMA user_version').get().user_version) {
        let raw;
        try {
          raw = readFileSync(legacy, 'utf8');
        } catch (error) {
          if (error.code !== 'ENOENT') throw error;
        }
        if (raw !== undefined) {
          const data = JSON.parse(raw);
          if (!data.sessions || typeof data.sessions !== 'object' || Array.isArray(data.sessions)) {
            throw new Error('Invalid legacy session store.');
          }
          for (const [id, session] of Object.entries(data.sessions)) {
            const deadline = Date.parse(session.updatedAt || session.createdAt) + sessionTtl;
            if (deadline > Date.now()) {
              store.query("INSERT INTO mobile_auth VALUES (?, 'session', NULL, ?, ?)",
                id, JSON.stringify(session), deadline);
            }
          }
          imported = true;
        }
        db.exec('PRAGMA user_version=1');
      }
      db.exec('COMMIT');
    } catch (error) {
      db.exec('ROLLBACK');
      throw error;
    }
    if (imported) unlinkSync(legacy);
    store.purgeExpired();
    return { store, close: () => db.close() };
  } catch (error) {
    db.close();
    throw error;
  }
}
