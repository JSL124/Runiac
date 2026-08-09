import { cookies } from "next/headers";
import { hasFirebaseEnv } from "@/lib/firebase/config";
import {
  SESSION_COOKIE_NAME,
  getFirebaseAdminUser,
} from "@/lib/firebase/session";

// Minimal identity shape shared by every consumer (admin layout, documents
// pages and API routes).
export type CurrentUser = {
  uid: string | null;
  email: string | null;
};

export type CurrentUserResult = {
  configured: boolean;
  user: CurrentUser | null;
  isAdmin: boolean;
};

// Resolves the caller's identity from the Firebase admin-session cookie.
export async function getCurrentUser(): Promise<CurrentUserResult> {
  if (hasFirebaseEnv()) {
    const cookieStore = await cookies();
    const sessionCookie = cookieStore.get(SESSION_COOKIE_NAME)?.value;
    const firebaseUser = await getFirebaseAdminUser(sessionCookie);

    if (firebaseUser) {
      return {
        configured: true,
        user: { uid: firebaseUser.uid, email: firebaseUser.email },
        isAdmin: firebaseUser.isAdmin,
      };
    }
  }

  return { configured: hasFirebaseEnv(), user: null, isAdmin: false };
}
