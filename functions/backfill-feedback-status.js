const admin = require('firebase-admin');

async function ensureFeedbackMetadata(collectionName, db) {
  const snapshot = await db.collection(collectionName).get();
  if (snapshot.empty) {
    return 0;
  }

  const now = admin.firestore.Timestamp.now();
  let updated = 0;

  for (const doc of snapshot.docs) {
    const data = doc.data() || {};
    const updates = {};
    if (!Object.prototype.hasOwnProperty.call(data, 'status')) {
      updates.status = 'open';
    }
    if (!Object.prototype.hasOwnProperty.call(data, 'updatedAt')) {
      updates.updatedAt = now;
    }
    if (!Object.prototype.hasOwnProperty.call(data, 'resolvedAt')) {
      updates.resolvedAt = null;
    }
    if (!Object.prototype.hasOwnProperty.call(data, 'resolutionNotes')) {
      updates.resolutionNotes = null;
    }

    if (Object.keys(updates).length > 0) {
      await doc.ref.update(updates);
      updated += 1;
    }
  }

  return updated;
}

async function main() {
  admin.initializeApp();
  const db = admin.firestore();
  const collections = ['bugReports', 'featureRequests'];
  let totalUpdated = 0;

  for (const collectionName of collections) {
    const count = await ensureFeedbackMetadata(collectionName, db);
    console.log(`Updated ${count} documents in ${collectionName}.`);
    totalUpdated += count;
  }

  console.log(`Backfill complete. Updated ${totalUpdated} documents.`);
}

if (require.main === module) {
  main().catch(error => {
    console.error(error);
    process.exit(1);
  });
}

module.exports = { ensureFeedbackMetadata, main };
