"use server";

// Server actions for the admin console's "Newsletter" page
// (src/app/admin/newsletter). Every action re-verifies the caller with
// requireAdmin() before touching Firestore — never trust the client, matching
// the pattern in ./admin and ./documents.
//
// Two things this file must never be able to do, by construction rather than
// convention:
//   * Send arbitrary mail to one address — sendTestNewsletterCampaign() below
//     always writes the SIGNED-IN ADMIN's own email as the sole test
//     recipient; the client never gets to choose the address.
//   * Promote a subscriber to "confirmed" — there is deliberately no
//     "set subscriber status" action here, only delete (the privacy/GDPR
//     path). Fabricating double-opt-in evidence would defeat the point of
//     collecting it.
//
// "Send" is likewise irreversible in the other direction: a queued/sent
// campaign cannot be recalled, and src/lib/firebase/firestore.ts enforces
// (in a transaction) that only a "draft" campaign can ever be queued, so a
// double-click or a retried request cannot mail the list twice.

import { requireAdmin } from "@/lib/actions/require-admin";
import { hasFirebaseEnv } from "@/lib/firebase/config";
import {
  createNewsletterCampaign,
  deleteNewsletterSubscriber as deleteNewsletterSubscriberInDb,
  listNewsletterCampaignDeliveries,
  queueNewsletterCampaignSend,
  queueNewsletterCampaignTest,
  updateNewsletterCampaignDraft,
} from "@/lib/firebase/firestore";
import type { NewsletterDelivery } from "@/lib/admin/types";

export type NewsletterActionResult =
  | { ok: true; live: boolean }
  | { ok: false; error: string };

const SUBJECT_MAX_LENGTH = 200;

function errorMessage(error: unknown, fallback: string): string {
  // Thrown Errors from the firestore.ts transactions above carry a clear,
  // admin-facing message (e.g. "Only a draft campaign can be edited.") that
  // is safe to surface directly, unlike a raw Firestore/Auth error.
  return error instanceof Error && error.message ? error.message : fallback;
}

// --- subscribers (newsletterSubscribers/{id}) -------------------------------

// Privacy/GDPR takedown only. There is intentionally no companion "set
// status" action: promoting a subscriber to "confirmed" from the console
// would fabricate the double-opt-in evidence the backend is supposed to be
// the sole source of.
export async function deleteNewsletterSubscriber(
  id: string,
): Promise<NewsletterActionResult> {
  if (!id) {
    return { ok: false, error: "Missing subscriber id." };
  }

  const auth = await requireAdmin();
  if (!auth.ok) {
    return auth;
  }

  if (!hasFirebaseEnv()) {
    return { ok: true, live: false };
  }

  try {
    await deleteNewsletterSubscriberInDb(id, auth.admin.email);
    return { ok: true, live: true };
  } catch (error) {
    console.warn(
      `[admin-action] Newsletter subscriber delete failed for ${id}.`,
      error,
    );
    return {
      ok: false,
      error: "The backend rejected this deletion. Try again.",
    };
  }
}

// --- campaigns (newsletterCampaigns/{id}) -----------------------------------

// Creates a new draft (campaignId omitted/null) or edits an existing one.
// Editing is rejected server-side (by updateNewsletterCampaignDraft() in
// firestore.ts) once the campaign has left "draft", so a stale compose form
// can never silently rewrite content that has already queued or sent.
export async function saveNewsletterCampaignDraft(
  campaignId: string | null,
  subject: string,
  bodyMarkdown: string,
): Promise<NewsletterActionResult & { campaignId?: string }> {
  const trimmedSubject = subject.trim();
  const trimmedBody = bodyMarkdown.trim();

  if (!trimmedSubject || trimmedSubject.length > SUBJECT_MAX_LENGTH) {
    return {
      ok: false,
      error: `Subject must be between 1 and ${SUBJECT_MAX_LENGTH} characters.`,
    };
  }

  if (!trimmedBody) {
    return { ok: false, error: "The campaign body cannot be empty." };
  }

  const auth = await requireAdmin();
  if (!auth.ok) {
    return auth;
  }

  if (!hasFirebaseEnv()) {
    return { ok: true, live: false, campaignId: campaignId ?? undefined };
  }

  try {
    if (campaignId) {
      await updateNewsletterCampaignDraft(
        campaignId,
        trimmedSubject,
        trimmedBody,
        auth.admin.email,
      );
      return { ok: true, live: true, campaignId };
    }

    const newId = await createNewsletterCampaign(
      trimmedSubject,
      trimmedBody,
      auth.admin.email,
    );
    return { ok: true, live: true, campaignId: newId };
  } catch (error) {
    console.warn(
      `[admin-action] Newsletter campaign save failed for ${campaignId ?? "(new)"}.`,
      error,
    );
    return {
      ok: false,
      error: errorMessage(
        error,
        "The backend rejected this campaign save. Try again.",
      ),
    };
  }
}

// "Send test to yourself": the recipient is always the caller's own verified
// admin email (from requireAdmin(), never a client-supplied value), so this
// can never be used to mail an arbitrary address. Only a draft campaign can
// be test-queued; the backend send trigger reverts status back to "draft"
// once the test completes.
export async function sendTestNewsletterCampaign(
  campaignId: string,
): Promise<NewsletterActionResult> {
  if (!campaignId) {
    return { ok: false, error: "Missing campaign id." };
  }

  const auth = await requireAdmin();
  if (!auth.ok) {
    return auth;
  }

  if (!hasFirebaseEnv()) {
    return { ok: true, live: false };
  }

  try {
    await queueNewsletterCampaignTest(campaignId, auth.admin.email);
    return { ok: true, live: true };
  } catch (error) {
    console.warn(
      `[admin-action] Newsletter test send failed for ${campaignId}.`,
      error,
    );
    return {
      ok: false,
      error: errorMessage(
        error,
        "The backend rejected this test send. Try again.",
      ),
    };
  }
}

// The real send, to every confirmed subscriber. The client is expected to
// have already shown its own explicit confirm step before calling this — see
// NewsletterCampaigns.tsx — but the irreversibility is enforced here too:
// firestore.ts only allows a "draft" campaign to be queued, so this can never
// mail the same campaign twice even on a retried request.
export async function sendNewsletterCampaign(
  campaignId: string,
): Promise<NewsletterActionResult> {
  if (!campaignId) {
    return { ok: false, error: "Missing campaign id." };
  }

  const auth = await requireAdmin();
  if (!auth.ok) {
    return auth;
  }

  if (!hasFirebaseEnv()) {
    return { ok: true, live: false };
  }

  try {
    await queueNewsletterCampaignSend(campaignId, auth.admin.email);
    return { ok: true, live: true };
  } catch (error) {
    console.warn(
      `[admin-action] Newsletter send failed for ${campaignId}.`,
      error,
    );
    return {
      ok: false,
      error: errorMessage(error, "The backend rejected this send. Try again."),
    };
  }
}

// --- per-campaign delivery history (newsletterCampaigns/{id}/deliveries) ---

export type NewsletterDeliveriesResult =
  | { ok: true; deliveries: NewsletterDelivery[] }
  | { ok: false; error: string };

// Read-only, but still re-verified via requireAdmin() like every other action
// here — delivery rows are per-recipient send outcomes and are not exposed to
// anything but the admin console.
export async function getNewsletterCampaignDeliveries(
  campaignId: string,
): Promise<NewsletterDeliveriesResult> {
  if (!campaignId) {
    return { ok: false, error: "Missing campaign id." };
  }

  const auth = await requireAdmin();
  if (!auth.ok) {
    return auth;
  }

  if (!hasFirebaseEnv()) {
    return { ok: true, deliveries: [] };
  }

  try {
    const rows = await listNewsletterCampaignDeliveries(campaignId);
    return {
      ok: true,
      deliveries: rows.map((row) => ({
        id: row.id,
        status: row.status ?? "unknown",
        error: row.error,
      })),
    };
  } catch (error) {
    console.warn(
      `[admin-action] Newsletter delivery history read failed for ${campaignId}.`,
      error,
    );
    return {
      ok: false,
      error: "Could not load the delivery history. Try again.",
    };
  }
}
