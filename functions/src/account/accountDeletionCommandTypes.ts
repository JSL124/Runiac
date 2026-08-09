// Shared shape of the account-deletion command document.
//
// Split out of both the callable that writes it and the trigger that consumes
// it so the two cannot drift on the collection name or the status vocabulary,
// and so a test can assert against the same constants the production code uses.

export const ACCOUNT_DELETION_COMMANDS = "accountDeletionCommands";

export type AccountDeletionCommandStatus =
  // Written by requestAccountDeletion. The account is already locked out.
  | "pending"
  // The fan-out is running. Distinguishable from `pending` so an operator can
  // tell "never started" from "started and did not finish".
  | "erasing"
  | "completed"
  | "failed";

export const TERMINAL_COMMAND_STATUSES: readonly AccountDeletionCommandStatus[] = [
  "completed",
  "failed",
];
