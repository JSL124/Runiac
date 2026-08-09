export type PngValidationError =
  | "byte_limit"
  | "signature"
  | "chunk_bounds"
  | "chunk_crc"
  | "chunk_type"
  | "chunk_order"
  | "ihdr"
  | "dimensions"
  | "metadata"
  | "iend"
  | "missing_idat"
  | "empty_idat"
  | "missing_iend";
export type PngValidationResult =
  | { readonly ok: true; readonly width: number; readonly height: number }
  | { readonly ok: false; readonly error: PngValidationError };

const signature = [137, 80, 78, 71, 13, 10, 26, 10] as const;
const canonicalChromaticities = [31_270, 32_900, 64_000, 33_000, 30_000, 60_000, 15_000, 6_000] as const;
const maximumBytes = 1_048_576;

type ValidatePngOptions = {
  readonly maximumBytes: number;
  readonly isAllowedDimension: (width: number, height: number) => boolean;
  readonly allowsBitDepth16: (width: number, height: number) => boolean;
};

export function validateFeedThumbnailPng(bytes: Uint8Array): PngValidationResult {
  return validatePng(bytes, { maximumBytes, isAllowedDimension, allowsBitDepth16: isWideDimension });
}

// Bit depth 16 is allowed for the same reason isWideDimension allows it on
// feed thumbnails: on a wide-gamut (Display P3) device — every recent iPhone —
// Flutter renders Picture.toImage into an F16 surface, so Skia's PNG encoder
// emits depth 16 with sBIT 10,10,10,10 rather than depth 8. Rejecting it made
// avatar upload fail with "Staged avatar image is invalid." for every real
// device while passing on host/simulator Skia, which emits depth 8. This is
// not a blanket relaxation: the depth-16 branch below still requires an sBIT
// chunk declaring exactly 10 significant bits per channel, so only that
// encoder's shape is accepted, and the 1 MiB byte limit and fixed 256x256
// dimension are unchanged.
export function validateAvatarPng(bytes: Uint8Array): PngValidationResult {
  return validatePng(bytes, { maximumBytes, isAllowedDimension: isAllowedAvatarDimension, allowsBitDepth16: () => true });
}

function validatePng(bytes: Uint8Array, options: ValidatePngOptions): PngValidationResult {
  if (bytes.byteLength === 0 || bytes.byteLength > options.maximumBytes) return { ok: false, error: "byte_limit" };
  if (!signature.every((value, index) => bytes[index] === value)) return { ok: false, error: "signature" };
  let offset: number = signature.length;
  let width: number | undefined;
  let height: number | undefined;
  let bitDepth: number | undefined;
  let sawIdat = false;
  let idatByteLength = 0;
  const seenAncillary = new Set<string>();

  while (offset < bytes.length) {
    if (offset + 12 > bytes.length) return { ok: false, error: "chunk_bounds" };
    const length = uint32(bytes, offset);
    const typeStart = offset + 4;
    const dataStart = offset + 8;
    const dataEnd = dataStart + length;
    const crcEnd = dataEnd + 4;
    if (crcEnd > bytes.length) return { ok: false, error: "chunk_bounds" };
    if (crc32(bytes, typeStart, dataEnd) !== uint32(bytes, dataEnd)) return { ok: false, error: "chunk_crc" };
    const chunk = ascii(bytes, typeStart, 4);

    if (chunk === "IHDR") {
      if (offset !== signature.length || width !== undefined || length !== 13) return { ok: false, error: "ihdr" };
      width = uint32(bytes, dataStart);
      height = uint32(bytes, dataStart + 4);
      if (!options.isAllowedDimension(width, height)) return { ok: false, error: "dimensions" };
      bitDepth = bytes[dataStart + 8];
      if (!hasSafeIhdrFields(bytes, dataStart, options.allowsBitDepth16(width, height))) return { ok: false, error: "ihdr" };
    } else if (isAllowedAncillary(chunk)) {
      if (width === undefined || sawIdat) return { ok: false, error: "chunk_order" };
      if (seenAncillary.has(chunk) || !hasSafeAncillaryData(chunk, bytes, dataStart, length, bitDepth)) return { ok: false, error: "metadata" };
      seenAncillary.add(chunk);
    } else if (chunk === "IDAT") {
      if (width === undefined) return { ok: false, error: "chunk_order" };
      if (length === 0) return { ok: false, error: "empty_idat" };
      sawIdat = true;
      idatByteLength += length;
    } else if (chunk === "IEND") {
      if (width === undefined || height === undefined || !sawIdat || length !== 0) return { ok: false, error: "iend" };
      if (bitDepth === 16 && !seenAncillary.has("sBIT")) return { ok: false, error: "metadata" };
      if (idatByteLength === 0) return { ok: false, error: "empty_idat" };
      if (crcEnd !== bytes.length) return { ok: false, error: "chunk_bounds" };
      return { ok: true, width, height };
    } else {
      return { ok: false, error: "chunk_type" };
    }
    offset = crcEnd;
  }

  if (width === undefined || height === undefined) return { ok: false, error: "ihdr" };
  if (!sawIdat) return { ok: false, error: "missing_idat" };
  return { ok: false, error: "missing_iend" };
}

function isAllowedDimension(width: number, height: number): boolean {
  if (width === height && (width === 88 || width === 176 || width === 264)) return true;
  return (width === 344 && height === 184) || (width === 688 && height === 368) || (width === 1032 && height === 552);
}

function isAllowedAvatarDimension(width: number, height: number): boolean {
  return width === 256 && height === 256;
}

function hasSafeIhdrFields(bytes: Uint8Array, dataStart: number, allowsBitDepth16: boolean): boolean {
  const bitDepth = bytes[dataStart + 8];
  const hasSafeBitDepth = bitDepth === 8 || (bitDepth === 16 && allowsBitDepth16);
  return hasSafeBitDepth && bytes[dataStart + 9] === 6 && bytes[dataStart + 10] === 0 && bytes[dataStart + 11] === 0 && bytes[dataStart + 12] === 0;
}

function isAllowedAncillary(chunk: string): boolean {
  return chunk === "cHRM" || chunk === "gAMA" || chunk === "sBIT" || chunk === "sRGB";
}

function hasSafeAncillaryData(chunk: string, bytes: Uint8Array, dataStart: number, length: number, bitDepth: number | undefined): boolean {
  if (chunk === "cHRM") return length === 32 && canonicalChromaticities.every((value, index) => uint32(bytes, dataStart + (index * 4)) === value);
  if (chunk === "gAMA") return length === 4 && uint32(bytes, dataStart) === 45_455;
  if (chunk === "sBIT") {
    const significantBits = bitDepth === 16 ? 10 : 8;
    return length === 4 && bytes[dataStart] === significantBits && bytes[dataStart + 1] === significantBits && bytes[dataStart + 2] === significantBits && bytes[dataStart + 3] === significantBits;
  }
  return length === 1 && bytes[dataStart] === 0;
}

function isWideDimension(width: number, height: number): boolean {
  return (width === 344 && height === 184) || (width === 688 && height === 368) || (width === 1032 && height === 552);
}

function uint32(bytes: Uint8Array, offset: number): number {
  return ((bytes[offset] ?? 0) * 16_777_216) + ((bytes[offset + 1] ?? 0) * 65_536) + ((bytes[offset + 2] ?? 0) * 256) + (bytes[offset + 3] ?? 0);
}

function ascii(bytes: Uint8Array, offset: number, length: number): string {
  return String.fromCharCode(...bytes.slice(offset, offset + length));
}

function crc32(bytes: Uint8Array, start: number, end: number): number {
  let crc = 0xffff_ffff;
  for (let index = start; index < end; index += 1) {
    crc ^= bytes[index] ?? 0;
    for (let bit = 0; bit < 8; bit += 1) crc = (crc & 1) === 1 ? (crc >>> 1) ^ 0xedb8_8320 : crc >>> 1;
  }
  return (crc ^ 0xffff_ffff) >>> 0;
}
