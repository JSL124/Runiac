// Shared sign-in action state. Kept out of the "use server" module because a
// "use server" file may only export async functions — exporting the object
// below from there triggers "A 'use server' file can only export async
// functions, found object."

export type SignInState = {
  error: string | null;
};

export const initialSignInState: SignInState = { error: null };

// Sign-up keeps the created account's email so the success panel can tell the
// runner exactly which account to sign into in the app.
export type SignUpState = {
  error: string | null;
  createdEmail: string | null;
};

export const initialSignUpState: SignUpState = {
  error: null,
  createdEmail: null,
};

// Password reset never distinguishes "sent" from "no such account": `sent`
// only means the request was accepted, so the UI copy stays deliberately
// non-committal about whether the email exists.
export type PasswordResetState = {
  error: string | null;
  sent: boolean;
};

export const initialPasswordResetState: PasswordResetState = {
  error: null,
  sent: false,
};
