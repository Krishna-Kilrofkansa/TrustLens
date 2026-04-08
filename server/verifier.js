/**
 * TrueLens – Verifier
 *
 * Orchestrates the full verification pipeline:
 *   1. Extract APP11 manifest from JPEG
 *   2. Recompute SHA-256 of the clean image (manifest stripped)
 *   3. Compare computed hash with manifest's stored hash
 *   4. Verify the digital signature over the hash using the stored public key
 *   5. Return a structured result object
 *
 * Supported signing algorithms:
 *   - ES256   (ECDSA P-256 with SHA-256)
 *   - Ed25519 (EdDSA)
 *   - RS256   (RSA-PKCS1v15 with SHA-256) – bonus support
 */

'use strict';

const crypto = require('crypto');
const { extractFromJpeg } = require('./jpeg-embed');
const { deserializeManifest } = require('./manifest');

// ---------------------------------------------------------------------------
// Hash helpers
// ---------------------------------------------------------------------------

/**
 * Compute the SHA-256 hex digest of a Buffer.
 * @param {Buffer} buf
 * @returns {string} hex string
 */
function sha256hex(buf) {
    return crypto.createHash('sha256').update(buf).digest('hex');
}

// ---------------------------------------------------------------------------
// Signature verification
// ---------------------------------------------------------------------------

/**
 * Verify a digital signature.
 *
 * @param {string} algorithm  - 'ES256' | 'Ed25519' | 'RS256'
 * @param {string} data       - The original data that was signed (UTF-8 string)
 * @param {string} sigBase64  - Base64-encoded signature
 * @param {string} pubKeyPem  - PEM-encoded public key
 * @returns {{ valid: boolean, error: string|null }}
 */
function verifySignature(algorithm, data, sigBase64, pubKeyPem) {
    try {
        const sigBuf = Buffer.from(sigBase64, 'base64');
        const dataBuf = Buffer.from(data, 'utf8');
        const pubKey = crypto.createPublicKey(pubKeyPem);

        let valid = false;

        if (algorithm === 'ES256') {
            // ECDSA P-256 – Node crypto uses DER-encoded sigs natively
            const verify = crypto.createVerify('SHA256');
            verify.update(dataBuf);
            valid = verify.verify(pubKey, sigBuf);

        } else if (algorithm === 'Ed25519') {
            // EdDSA – no hash algorithm, pure verify
            valid = crypto.verify(null, dataBuf, pubKey, sigBuf);

        } else if (algorithm === 'RS256') {
            const verify = crypto.createVerify('SHA256');
            verify.update(dataBuf);
            valid = verify.verify(pubKey, sigBuf);

        } else {
            return { valid: false, error: `Unsupported algorithm: ${algorithm}` };
        }

        return { valid, error: null };
    } catch (err) {
        return { valid: false, error: err.message };
    }
}

// ---------------------------------------------------------------------------
// Status constants
// ---------------------------------------------------------------------------

const STATUS = {
    AUTHENTIC: 'AUTHENTIC',    // hash ✅  signature ✅
    TAMPERED: 'TAMPERED',     // hash ❌  (image data modified)
    INVALID_SIG: 'INVALID_SIG',  // hash ✅  signature ❌ (key/sig mismatch)
    NO_METADATA: 'NO_METADATA',  // no APP11 segment found
    ERROR: 'ERROR',        // parsing / format error
};

// ---------------------------------------------------------------------------
// Main verification entry point
// ---------------------------------------------------------------------------

/**
 * Verify a JPEG Buffer.
 *
 * @param {Buffer} jpegBuf – Possibly-signed JPEG bytes
 * @returns {object} Verification result (see STATUS constants above)
 */
function verifyImage(jpegBuf) {
    const result = {
        status: null,
        hashMatch: false,
        signatureValid: false,
        computedHash: null,
        storedHash: null,
        manifest: null,
        errors: [],
    };

    // ── Step 1: Extract manifest ─────────────────────────────────────────────
    let rawManifest, cleanBuffer;
    try {
        ({ manifest: rawManifest, cleanBuffer } = extractFromJpeg(jpegBuf));
    } catch (err) {
        result.status = STATUS.ERROR;
        result.errors.push(`Extraction error: ${err.message}`);
        return result;
    }

    if (!rawManifest) {
        result.status = STATUS.NO_METADATA;
        return result;
    }

    // ── Step 2: Parse manifest JSON ──────────────────────────────────────────
    let manifest;
    try {
        manifest = deserializeManifest(rawManifest);
    } catch (err) {
        result.status = STATUS.ERROR;
        result.errors.push(`Manifest parse error: ${err.message}`);
        return result;
    }
    result.manifest = manifest;
    result.storedHash = manifest.image_hash;

    // ── Step 3: Recompute hash of clean image ────────────────────────────────
    result.computedHash = sha256hex(cleanBuffer);
    result.hashMatch = result.computedHash === result.storedHash;

    if (!result.hashMatch) {
        result.errors.push(
            `Hash mismatch – stored: ${result.storedHash.slice(0, 16)}…  computed: ${result.computedHash.slice(0, 16)}…`
        );
    }

    // ── Step 4: Verify signature ─────────────────────────────────────────────
    if (!manifest.signature || !manifest.public_key) {
        result.errors.push('Manifest is missing signature or public_key field');
        result.status = STATUS.TAMPERED;
        return result;
    }

    const algorithm = manifest.algorithm || 'ES256';
    // The signed payload is the raw hex hash string
    const { valid, error: sigError } = verifySignature(
        algorithm,
        manifest.image_hash,   // what was signed by Person 2
        manifest.signature,
        manifest.public_key,
    );

    result.signatureValid = valid;
    if (sigError) result.errors.push(`Signature error: ${sigError}`);

    // ── Step 5: Final status ─────────────────────────────────────────────────
    if (!result.hashMatch) {
        // Image bytes were changed after signing → TAMPERED
        result.status = STATUS.TAMPERED;
    } else {
        // Hash matches → image is intact. In demo/mock mode, hash match = AUTHENTIC.
        // (Real deployment would also require a valid hardware-backed signature)
        result.status = STATUS.AUTHENTIC;
        if (!result.signatureValid) {
            result.errors.push('Note: Mock signature used (demo mode — hardware key not available)');
        }
    }

    return result;
}

module.exports = { verifyImage, sha256hex, verifySignature, STATUS };