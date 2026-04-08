/**
 * TrueLens – JPEG APP11 Segment Handler
 *
 * Embeds and extracts a TrueLens manifest using an APP11 (0xFFEB) JPEG
 * application segment, inserted immediately before the Start-of-Scan (SOS)
 * marker so that the compressed image data is never touched.
 *
 * APP11 wire format:
 *   FF EB           – APP11 marker        (2 bytes)
 *   [length]        – Big-endian uint16   (2 bytes, includes itself)
 *   TRUELENS\0      – Magic identifier    (9 bytes)
 *   [manifest data] – UTF-8 JSON payload  (length - 2 - 9 bytes)
 */

'use strict';

const MAGIC = Buffer.from('TRUELENS\0', 'ascii'); // 9 bytes
const APP11_HI = 0xFF;
const APP11_LO = 0xEB;
const SOI_HI = 0xFF;
const SOI_LO = 0xD8;

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

function isValidJpeg(buf) {
    return buf.length >= 4 && buf[0] === SOI_HI && buf[1] === SOI_LO;
}

/**
 * Walk the JPEG segment chain and return an array of segment descriptors.
 * Each descriptor: { marker, offset, length }
 * We stop at SOS (0xFFDA) because image entropy data follows and is not
 * length-prefixed in the same way.
 */
function walkSegments(buf) {
    const segments = [];
    let i = 2; // skip SOI

    while (i < buf.length - 1) {
        if (buf[i] !== 0xFF) {
            // Padding bytes (0xFF 0xFF) or corruption – try to skip
            i++;
            continue;
        }

        // Skip fill bytes (JPEG spec allows multiple 0xFF before marker byte)
        while (i < buf.length - 1 && buf[i + 1] === 0xFF) i++;

        const marker = buf[i + 1];

        // Standalone markers (no length field)
        if (
            marker === 0xD8 || // SOI
            marker === 0xD9 || // EOI
            (marker >= 0xD0 && marker <= 0xD7) // RST0–RST7
        ) {
            segments.push({ marker, offset: i, length: 0, standalone: true });
            i += 2;
            continue;
        }

        // SOS – stop here; don't parse the compressed data
        if (marker === 0xDA) {
            segments.push({ marker, offset: i, length: null, sos: true });
            break;
        }

        if (i + 3 >= buf.length) break; // truncated
        const segLen = buf.readUInt16BE(i + 2); // includes the 2 length bytes
        segments.push({ marker, offset: i, length: segLen });
        i += 2 + segLen;
    }

    return segments;
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/**
 * Embed a manifest Buffer into a JPEG Buffer as an APP11 segment.
 *
 * @param {Buffer} jpegBuf     – Original JPEG image bytes
 * @param {Buffer} manifestBuf – Serialised manifest (UTF-8 JSON)
 * @returns {Buffer} New JPEG buffer with APP11 segment inserted before SOS
 */
function embedIntoJpeg(jpegBuf, manifestBuf) {
    if (!isValidJpeg(jpegBuf)) throw new Error('Input is not a valid JPEG (bad SOI marker)');

    const segments = walkSegments(jpegBuf);
    const sos = segments.find(s => s.sos);
    if (!sos) throw new Error('JPEG has no SOS marker – cannot embed manifest');

    // Remove any pre-existing TrueLens APP11 segment so re-embedding is safe
    const stripped = stripApp11(jpegBuf);
    const strippedSegs = walkSegments(stripped);
    const newSos = strippedSegs.find(s => s.sos);
    const insertAt = newSos ? newSos.offset : sos.offset;

    // Build APP11 segment
    // payload = MAGIC + manifestBuf
    const payload = Buffer.concat([MAGIC, manifestBuf]);
    const segLength = 2 + payload.length; // length field includes itself
    if (segLength > 0xFFFF) throw new Error('Manifest too large for a single APP11 segment (max ~65 KB)');

    const app11 = Buffer.alloc(2 + 2 + payload.length);
    app11[0] = APP11_HI;
    app11[1] = APP11_LO;
    app11.writeUInt16BE(segLength, 2);
    payload.copy(app11, 4);

    return Buffer.concat([
        stripped.slice(0, insertAt),
        app11,
        stripped.slice(insertAt),
    ]);
}

/**
 * Extract the TrueLens manifest from a JPEG Buffer.
 *
 * @param {Buffer} jpegBuf
 * @returns {{ manifest: Buffer|null, cleanBuffer: Buffer }}
 *   manifest   – raw manifest bytes (UTF-8 JSON), or null if not found
 *   cleanBuffer – JPEG with the APP11 segment removed (for re-hashing)
 */
function extractFromJpeg(jpegBuf) {
    if (!isValidJpeg(jpegBuf)) throw new Error('Input is not a valid JPEG');

    const segments = walkSegments(jpegBuf);
    const app11Seg = segments.find(
        s => s.marker === APP11_LO && !s.standalone && !s.sos
    );

    if (!app11Seg) {
        return { manifest: null, cleanBuffer: jpegBuf };
    }

    const segStart = app11Seg.offset;
    const segEnd = segStart + 2 + app11Seg.length; // marker(2) + length
    const segPayload = jpegBuf.slice(segStart + 4, segEnd); // skip marker + length bytes

    // Validate magic
    if (!segPayload.slice(0, MAGIC.length).equals(MAGIC)) {
        // APP11 exists but not ours – skip it
        return { manifest: null, cleanBuffer: jpegBuf };
    }

    const manifest = segPayload.slice(MAGIC.length);
    const cleanBuffer = Buffer.concat([
        jpegBuf.slice(0, segStart),
        jpegBuf.slice(segEnd),
    ]);

    return { manifest, cleanBuffer };
}

/**
 * Remove any TrueLens APP11 segment from a JPEG (non-destructive to image data).
 * @param {Buffer} jpegBuf
 * @returns {Buffer}
 */
function stripApp11(jpegBuf) {
    const { cleanBuffer } = extractFromJpeg(jpegBuf);
    return cleanBuffer;
}

module.exports = { embedIntoJpeg, extractFromJpeg, stripApp11, isValidJpeg };