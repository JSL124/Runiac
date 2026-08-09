// Firestore-emulator integration tests for the "Project Documents" PDF
// library's read/write path (src/lib/firebase/firestore.ts:
// listProjectDocuments / getProjectDocumentById / createProjectDocument).
// Modeled on overview.int.test.ts: writes real documents into the emulator
// and reads them back through the exact functions the admin console uses,
// proving the Timestamp -> ISO createdAt normalization and audit-log side
// effect actually happen, not just that they look plausible when mocked.
//
// Skips itself entirely when no Firestore emulator is configured (see
// emulatorAvailable() in ./helpers/emulator) so `npm run test:integration`
// never accidentally talks to a live project.

import type { Firestore } from "firebase-admin/firestore";
import { beforeEach, describe, expect, it } from "vitest";

import {
  createProjectDocument,
  getProjectDocumentById,
  listProjectDocuments,
  newProjectDocumentId,
} from "@/lib/firebase/firestore";

import {
  emulatorAvailable,
  getTestDb,
  resetFirestore,
  seedProjectDocument,
} from "./helpers/emulator";

describe.skipIf(!emulatorAvailable())(
  "project documents — Firestore emulator integration",
  () => {
    let db: Firestore;

    beforeEach(async () => {
      db = getTestDb();
      await resetFirestore();
    });

    describe("listProjectDocuments", () => {
      it("orders records by documentDate descending", async () => {
        await seedProjectDocument(db, { documentDate: "2026-01-10", title: "Oldest" });
        await seedProjectDocument(db, { documentDate: "2026-03-01", title: "Newest" });
        await seedProjectDocument(db, { documentDate: "2026-02-15", title: "Middle" });

        const records = await listProjectDocuments();

        expect(records.map((record) => record.title)).toEqual([
          "Newest",
          "Middle",
          "Oldest",
        ]);
      });

      it("normalizes createdAt to an ISO string, not a Timestamp object", async () => {
        // seedProjectDocument() defaults createdAt to a real Firestore
        // Timestamp (matching what FieldValue.serverTimestamp() produces on
        // read-back), so this exercises toIso()'s Timestamp branch.
        await seedProjectDocument(db, { documentDate: "2026-01-01" });

        const [record] = await listProjectDocuments();

        expect(typeof record.createdAt).toBe("string");
        expect(Number.isNaN(Date.parse(record.createdAt))).toBe(false);
      });
    });

    describe("getProjectDocumentById", () => {
      it("returns null for an unknown id", async () => {
        expect(await getProjectDocumentById("does-not-exist")).toBeNull();
      });
    });

    describe("createProjectDocument", () => {
      it("round-trips every field through getProjectDocumentById and writes an adminAuditLogs entry", async () => {
        const id = newProjectDocumentId();
        const storagePath = `project-documents/${id}/architecture.pdf`;

        await createProjectDocument(
          id,
          storagePath,
          {
            title: "Architecture Review",
            category: "architecture",
            documentDate: "2026-05-20",
            fileName: "architecture.pdf",
            fileSize: 2048,
          },
          "admin@example.com",
        );

        const record = await getProjectDocumentById(id);

        expect(record).not.toBeNull();
        expect(record).toMatchObject({
          id,
          title: "Architecture Review",
          category: "architecture",
          documentDate: "2026-05-20",
          fileName: "architecture.pdf",
          fileSize: 2048,
          storagePath,
          createdBy: "admin@example.com",
        });
        expect(typeof record?.createdAt).toBe("string");
        expect(Number.isNaN(Date.parse(record?.createdAt ?? ""))).toBe(false);

        const auditSnapshot = await db
          .collection("adminAuditLogs")
          .where("targetId", "==", id)
          .get();

        expect(auditSnapshot.empty).toBe(false);
        const auditEntry = auditSnapshot.docs[0].data();
        expect(auditEntry.action).toBe("documents.upload");
        expect(auditEntry.targetType).toBe("projectDocument");
      });
    });
  },
);
