import { afterEach, describe, expect, it, vi } from "vitest";

import { GET, HEAD } from "../route";

const UPSTREAM_URL =
  "https://github.com/JSL124/Runiac_App/releases/latest/download/runiac.apk";

function stubFetch(response: Response | Error) {
  const fetchMock = vi.fn(async () => {
    if (response instanceof Error) {
      throw response;
    }
    return response;
  });

  vi.stubGlobal("fetch", fetchMock);
  return fetchMock;
}

afterEach(() => {
  vi.unstubAllGlobals();
});

describe("GET /api/download/android", () => {
  it("streams the release asset back as a runiac.apk attachment", async () => {
    const fetchMock = stubFetch(
      new Response("apk-bytes", {
        headers: { "Content-Length": "9", "Content-Type": "text/plain" },
      }),
    );

    const response = await GET();

    expect(fetchMock).toHaveBeenCalledWith(
      UPSTREAM_URL,
      expect.objectContaining({ method: "GET", redirect: "follow" }),
    );
    expect(response.status).toBe(200);
    expect(response.headers.get("Content-Type")).toBe(
      "application/vnd.android.package-archive",
    );
    expect(response.headers.get("Content-Disposition")).toBe(
      'attachment; filename="runiac.apk"',
    );
    // Passed through so the browser can draw a real progress bar.
    expect(response.headers.get("Content-Length")).toBe("9");
    await expect(response.text()).resolves.toBe("apk-bytes");
  });

  it("answers 502 when the release asset cannot be fetched", async () => {
    stubFetch(new Response("not found", { status: 404 }));

    const response = await GET();

    expect(response.status).toBe(502);
    await expect(response.json()).resolves.toEqual({
      error: "The Android APK is temporarily unavailable.",
    });
  });

  it("answers 502 when the upstream request throws", async () => {
    stubFetch(new Error("network down"));

    const response = await GET();

    expect(response.status).toBe(502);
  });
});

describe("HEAD /api/download/android", () => {
  it("returns the download headers with no body", async () => {
    const fetchMock = stubFetch(
      new Response(null, { headers: { "Content-Length": "150346968" } }),
    );

    const response = await HEAD();

    expect(fetchMock).toHaveBeenCalledWith(
      UPSTREAM_URL,
      expect.objectContaining({ method: "HEAD" }),
    );
    expect(response.status).toBe(200);
    expect(response.headers.get("Content-Length")).toBe("150346968");
    expect(response.body).toBeNull();
  });

  it("answers 502 when the release asset cannot be reached", async () => {
    stubFetch(new Response(null, { status: 500 }));

    const response = await HEAD();

    expect(response.status).toBe(502);
  });
});
