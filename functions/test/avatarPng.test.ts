import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { validateAvatarPng } from "../src/feed/png.js";

describe("Avatar PNG validation", () => {
  it("accepts a well-formed 256x256, bit depth 8, colour type 6, non-interlaced PNG", () => {
    const result = validateAvatarPng(png(256, 256));
    assert.equal(result.ok, true);
    assert.equal(result.ok && result.width, 256);
    assert.equal(result.ok && result.height, 256);
  });

  it("rejects dimensions other than exactly 256x256", () => {
    rejects(png(255, 255), "dimensions");
    rejects(png(512, 512), "dimensions");
  });

  // What a wide-gamut (Display P3) device actually uploads: Flutter renders
  // Picture.toImage into an F16 surface there, so Skia emits depth 16 plus an
  // sBIT declaring 10 significant bits. Host/simulator Skia emits depth 8, so
  // only a real device ever produced this shape — and rejecting it failed
  // every real avatar upload with "Staged avatar image is invalid."
  it("accepts bit depth 16 at 256x256 when sBIT declares 10 significant bits", () => {
    const result = validateAvatarPng(png(256, 256, { bitDepth: 16, sBit: [10, 10, 10, 10] }));
    assert.equal(result.ok, true);
    assert.equal(result.ok && result.width, 256);
  });

  it("rejects bit depth 16 at 256x256 without an sBIT chunk", () => {
    rejects(png(256, 256, { bitDepth: 16 }), "metadata");
  });

  it("rejects bit depth 16 at 256x256 with any sBIT other than 10 significant bits", () => {
    rejects(png(256, 256, { bitDepth: 16, sBit: [8, 8, 8, 8] }), "metadata");
    rejects(png(256, 256, { bitDepth: 16, sBit: [10, 10, 10, 16] }), "metadata");
  });

  it("rejects an sBIT declaring 10 significant bits at bit depth 8", () => {
    rejects(png(256, 256, { sBit: [10, 10, 10, 10] }), "metadata");
  });

  it("rejects colour type 2 at 256x256", () => {
    rejects(png(256, 256, { colourType: 2 }), "ihdr");
  });

  it("rejects a tEXt chunk", () => {
    rejects(pngWithTextChunk(), "chunk_type");
  });

  it("rejects a corrupted chunk CRC", () => {
    rejects(corruptPng(png(256, 256)), "chunk_crc");
  });

  it("rejects bytes appended after IEND", () => {
    rejects(Uint8Array.from([...png(256, 256), 0]), "chunk_bounds");
  });

  it("rejects zero-length input", () => {
    rejects(new Uint8Array(0), "byte_limit");
  });
});

function rejects(bytes: Uint8Array, error: string): void {
  const result = validateAvatarPng(bytes);
  assert.equal(result.ok, false);
  assert.equal(!result.ok && result.error, error);
}

function png(width: number, height: number, options: { bitDepth?: number; colourType?: number; sBit?: readonly number[] } = {}): Uint8Array {
  const bitDepth = options.bitDepth ?? 8;
  const colourType = options.colourType ?? 6;
  const sBit = options.sBit === undefined ? [] : chunk("sBIT", options.sBit);
  return Uint8Array.from([137, 80, 78, 71, 13, 10, 26, 10, ...chunk("IHDR", [...u32(width), ...u32(height), bitDepth, colourType, 0, 0, 0]), ...sBit, ...chunk("IDAT", [0]), ...chunk("IEND", [])]);
}

function pngWithTextChunk(): Uint8Array {
  return Uint8Array.from([137, 80, 78, 71, 13, 10, 26, 10, ...chunk("IHDR", [...u32(256), ...u32(256), 8, 6, 0, 0, 0]), ...chunk("tEXt", [116, 101, 115, 116, 0, 118, 97, 108]), ...chunk("IDAT", [0]), ...chunk("IEND", [])]);
}

function corruptPng(bytes: Uint8Array): Uint8Array { const corrupted = Uint8Array.from(bytes); corrupted[corrupted.length - 1] = (corrupted[corrupted.length - 1] ?? 0) ^ 1; return corrupted; }
function u32(value: number): number[] { return [(value >>> 24) & 255, (value >>> 16) & 255, (value >>> 8) & 255, value & 255]; }
function chunk(type: string, data: readonly number[]): number[] { const typeBytes = [...type].map((character) => character.charCodeAt(0)); return [...u32(data.length), ...typeBytes, ...data, ...u32(crc32([...typeBytes, ...data]))]; }
function crc32(bytes: readonly number[]): number { let crc = 0xffff_ffff; for (const value of bytes) { crc ^= value; for (let bit = 0; bit < 8; bit += 1) crc = (crc & 1) === 1 ? (crc >>> 1) ^ 0xedb8_8320 : crc >>> 1; } return (crc ^ 0xffff_ffff) >>> 0; }
