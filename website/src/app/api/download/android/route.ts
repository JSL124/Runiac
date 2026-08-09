// Same-origin download endpoint for the public Android APK.
//
// The Download button used to link straight at
// github.com/JSL124/Runiac_App/releases/latest/download/runiac.apk, so the
// visitor left the site to fetch the installer. This route keeps the link on
// the Runiac domain and streams the release asset through, rather than
// redirecting — a 302 would put the GitHub host back in front of the visitor,
// which is the thing the same-origin link exists to avoid.
//
// APK_UPSTREAM_URL keeps the Releases "latest" alias, so publishing a new
// android-vX.Y.Z release still re-points this endpoint with no code change.

const APK_UPSTREAM_URL =
  "https://github.com/JSL124/Runiac_App/releases/latest/download/runiac.apk";

const APK_FILE_NAME = "runiac.apk";
const APK_CONTENT_TYPE = "application/vnd.android.package-archive";

// The asset is ~150 MB, so the response body is piped from upstream and never
// buffered in the function. Node runtime (not edge) because the stream is long
// lived; maxDuration is the ceiling a slow client is allowed to take.
export const runtime = "nodejs";
export const maxDuration = 60;
export const dynamic = "force-dynamic";

function attachmentHeaders(upstream: Response): Headers {
  const headers = new Headers({
    "Content-Type": APK_CONTENT_TYPE,
    "Content-Disposition": `attachment; filename="${APK_FILE_NAME}"`,
    // The upstream alias moves on every release, so a cached copy would go
    // stale silently. Correctness beats a cache hit for a once-per-install
    // download.
    "Cache-Control": "no-store",
  });

  // Passed through when upstream provides it, so the browser can show a real
  // progress bar instead of an unknown-size download.
  const contentLength = upstream.headers.get("content-length");
  if (contentLength) {
    headers.set("Content-Length", contentLength);
  }

  return headers;
}

async function fetchUpstream(method: "GET" | "HEAD"): Promise<Response | null> {
  try {
    // GitHub answers the alias with a redirect to a signed release-assets URL;
    // following it here is what keeps the visitor on this origin.
    const upstream = await fetch(APK_UPSTREAM_URL, {
      method,
      redirect: "follow",
      cache: "no-store",
    });

    return upstream.ok ? upstream : null;
  } catch {
    return null;
  }
}

export async function GET() {
  const upstream = await fetchUpstream("GET");

  if (!upstream || !upstream.body) {
    return Response.json(
      { error: "The Android APK is temporarily unavailable." },
      { status: 502 },
    );
  }

  return new Response(upstream.body, { headers: attachmentHeaders(upstream) });
}

// Some download managers probe with HEAD before starting; answering it with
// the same headers and no body avoids a needless 405 and a wasted retry.
export async function HEAD() {
  const upstream = await fetchUpstream("HEAD");

  if (!upstream) {
    return new Response(null, { status: 502 });
  }

  return new Response(null, { headers: attachmentHeaders(upstream) });
}
