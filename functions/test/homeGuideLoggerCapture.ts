import assert from "node:assert/strict";

type CapturedHomeGuideLog = {
  readonly stream: "stdout" | "stderr";
  readonly severity: "INFO" | "WARNING";
  readonly fields: {
    readonly event: "home_guide_agent_result";
    readonly delivery: "generated" | "cache" | "fallback";
    readonly source: "agent" | "unavailable";
    readonly fallbackCategory: string;
  };
};

export async function captureStructuredLogger<T>(
  action: () => Promise<T>,
): Promise<{ readonly value: T; readonly entries: readonly CapturedHomeGuideLog[] }> {
  const originalStdoutWrite = process.stdout.write;
  const originalStderrWrite = process.stderr.write;
  const entries: CapturedHomeGuideLog[] = [];
  const capture = (stream: "stdout" | "stderr") => (chunk: string | Uint8Array): boolean => {
    const text = typeof chunk === "string" ? chunk : Buffer.from(chunk).toString("utf8");
    recordHomeGuideLogLines(stream, text, entries);
    return true;
  };
  Object.defineProperty(process.stdout, "write", { value: capture("stdout"), configurable: true, writable: true });
  Object.defineProperty(process.stderr, "write", { value: capture("stderr"), configurable: true, writable: true });
  try {
    const value = await action();
    return { value, entries };
  } finally {
    Object.defineProperty(process.stdout, "write", { value: originalStdoutWrite, configurable: true, writable: true });
    Object.defineProperty(process.stderr, "write", { value: originalStderrWrite, configurable: true, writable: true });
  }
}

function recordHomeGuideLogLines(
  stream: "stdout" | "stderr",
  text: string,
  entries: CapturedHomeGuideLog[],
): void {
  for (const line of text.split("\n")) {
    const trimmed = line.trim();
    if (trimmed.length === 0) continue;
    const parsed = parseJsonLine(trimmed);
    if (isRecord(parsed) && parsed["event"] === "home_guide_agent_result") {
      entries.push(readCapturedHomeGuideLog(stream, parsed));
    }
  }
}

function parseJsonLine(line: string): unknown {
  try {
    return JSON.parse(line);
  } catch (error) {
    if (error instanceof SyntaxError) return null;
    throw error;
  }
}

function readCapturedHomeGuideLog(
  stream: "stdout" | "stderr",
  entry: Readonly<Record<string, unknown>>,
): CapturedHomeGuideLog {
  assert.deepEqual(Object.keys(entry).sort(), ["delivery", "event", "fallbackCategory", "severity", "source"]);
  assert.equal(entry["event"], "home_guide_agent_result");
  assert.ok(entry["delivery"] === "generated" || entry["delivery"] === "cache" || entry["delivery"] === "fallback");
  assert.ok(entry["source"] === "agent" || entry["source"] === "unavailable");
  assert.ok(entry["severity"] === "INFO" || entry["severity"] === "WARNING");
  const fallbackCategory = entry["fallbackCategory"];
  if (typeof fallbackCategory !== "string") {
    assert.fail("Expected fallbackCategory to be a string.");
  }
  return {
    stream,
    severity: entry["severity"],
    fields: {
      event: entry["event"],
      delivery: entry["delivery"],
      source: entry["source"],
      fallbackCategory,
    },
  };
}

function isRecord(value: unknown): value is Readonly<Record<string, unknown>> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
