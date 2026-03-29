/**
 * TrueLens – Manifest Builder
 * Structures cryptographic proof data into a verifiable JSON manifest.
 */

'use strict';

/**
 * Creates a signed manifest object from provided cryptographic data.
 *
 * @param {object} params
 * @param {string} params.imageHash     - SHA-256 hex hash of the original image
 * @param {string} [params.timestamp]   - ISO 8601 timestamp (defaults to now)
 * @param {string} [params.gps]         - "lat,long" coordinate string
 * @param {string} [params.device]      - Device identifier string
 * @param {string} params.signature     - Base64-encoded digital signature
 * @param {string} params.publicKey     - PEM-encoded public key
 * @param {string} [params.algorithm]   - Signing algorithm used (ES256 / Ed25519)
 * @returns {object} Manifest object
 */
function createManifest({ imageHash, timestamp, gps, device, signature, publicKey, algorithm }) {
    if (!imageHash) throw new Error('Manifest: imageHash is required');
    if (!signature) throw new Error('Manifest: signature is required');
    if (!publicKey) throw new Error('Manifest: publicKey is required');

    return {
        truelens_version: '1.0',
        image_hash: imageHash,
        timestamp: timestamp || new Date().toISOString(),
        gps: gps || null,
        device: device || 'TrueLens Camera',
        algorithm: algorithm || 'ES256',
        signature: signature,
        public_key: publicKey,
    };
}

/**
 * Serialises a manifest to a UTF-8 Buffer suitable for JPEG embedding.
 * @param {object} manifest
 * @returns {Buffer}
 */
function serializeManifest(manifest) {
    return Buffer.from(JSON.stringify(manifest, null, 0), 'utf8');
}

/**
 * Deserialises a UTF-8 Buffer back into a manifest object.
 * @param {Buffer} buffer
 * @returns {object}
 */
function deserializeManifest(buffer) {
    return JSON.parse(buffer.toString('utf8'));
}

module.exports = { createManifest, serializeManifest, deserializeManifest };