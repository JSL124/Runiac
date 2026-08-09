import { describe, expect, it } from "vitest";

import {
  DEFAULT_SITE_DOWNLOAD,
  mergeSiteDownload,
  validateSiteDownload,
} from "../site-download";

describe("mergeSiteDownload", () => {
  it("defaults the Android button to the same-origin download route", () => {
    expect(DEFAULT_SITE_DOWNLOAD.android.apkUrl).toBe("/api/download/android");
    expect(mergeSiteDownload(undefined).android.apkUrl).toBe(
      "/api/download/android",
    );
  });

  it("still lets a stored URL override the default", () => {
    const merged = mergeSiteDownload({
      android: { apkUrl: "https://example.test/runiac.apk" },
    });

    expect(merged.android.apkUrl).toBe("https://example.test/runiac.apk");
  });

  it("trims a stored URL pasted with surrounding whitespace", () => {
    // A leading space rendered href=" https://…", which the browser resolved
    // as a relative path instead of downloading.
    const merged = mergeSiteDownload({
      android: { apkUrl: "  https://example.test/runiac.apk\n" },
    });

    expect(merged.android.apkUrl).toBe("https://example.test/runiac.apk");
  });

  it("falls back when the stored URL is blank or not a string", () => {
    expect(mergeSiteDownload({ android: { apkUrl: "   " } }).android.apkUrl).toBe(
      DEFAULT_SITE_DOWNLOAD.android.apkUrl,
    );
    expect(mergeSiteDownload({ android: { apkUrl: 42 } }).android.apkUrl).toBe(
      DEFAULT_SITE_DOWNLOAD.android.apkUrl,
    );
  });

  it("refuses a stored URL whose scheme is not https or site-relative", () => {
    // The value becomes the public download button's href, so a
    // "javascript:" URL saved through the admin console would have been
    // rendered as a link handed to every visitor.
    for (const apkUrl of [
      "javascript:alert(1)",
      "  JavaScript:alert(1)",
      "data:text/html,<script>alert(1)</script>",
      "http://example.test/runiac.apk",
      "//evil.test/runiac.apk",
      "/\\evil.test/runiac.apk",
      // Control characters are stripped by URL parsing, so this normalises to
      // the protocol-relative "//evil.test/..." the prefix checks reject.
      "/\t/evil.test/runiac.apk",
      "/\n/evil.test/runiac.apk",
    ]) {
      expect(mergeSiteDownload({ android: { apkUrl } }).android.apkUrl).toBe(
        DEFAULT_SITE_DOWNLOAD.android.apkUrl,
      );
    }
  });
});

describe("validateSiteDownload", () => {
  it("accepts an https URL and a site-relative path", () => {
    for (const apkUrl of [
      "https://example.test/runiac.apk",
      "/api/download/android",
    ]) {
      expect(validateSiteDownload({ android: { apkUrl } }).errors).toEqual([]);
    }
  });

  it("reports an unsupported scheme instead of silently defaulting it", () => {
    const { errors } = validateSiteDownload({
      android: { apkUrl: "javascript:alert(1)" },
    });

    expect(errors).toHaveLength(1);
    expect(errors[0]).toContain("https://");
  });
});
