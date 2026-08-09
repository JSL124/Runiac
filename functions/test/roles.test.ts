import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { isPlatformAdminRole } from "../src/security/roles.js";

describe("isPlatformAdminRole", () => {
  it("accepts the canonical console-written role string", () => {
    assert.equal(isPlatformAdminRole({ userRole: "platformAdmin" }), true);
  });

  it("keeps accepting the legacy display-style role string for backward compatibility", () => {
    assert.equal(isPlatformAdminRole({ userRole: "Platform Administrator" }), true);
  });

  it("rejects any other role or an absent/undefined document", () => {
    assert.equal(isPlatformAdminRole({ userRole: "user" }), false);
    assert.equal(isPlatformAdminRole({}), false);
    assert.equal(isPlatformAdminRole(undefined), false);
  });
});
