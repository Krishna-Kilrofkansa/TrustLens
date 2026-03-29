/**
 * TrueLens – Express Server
 *
 * REST endpoints:
 *   POST /api/hash    – return SHA-256 of uploaded image
 *   POST /api/embed   – embed manifest into JPEG, return signed JPEG
 *   POST /api/verify  – verify signed JPEG, return result JSON
 */

'use strict';

const express = require('express');
const multer = require('multer');
const path = require('path');

const { createManifest, serializeManifest } = require('./manifest');
const { embedIntoJpeg, isValidJpeg } = require('./jpeg-embed');
const { verifyImage, sha256hex, STATUS } = require('./verifier');

const app = express();
const upload = multer({
    storage: multer.memoryStorage(),
    limits: { fileSize: 25 * 1024 * 1024 }, // 25 MB max
    fileFilter(_req, file, cb) {
        const ok = /image\/jpe?g/i.test(file.mimetype) ||
            /\.(jpg|jpeg)$/i.test(file.originalname);
        cb(ok ? null : new Error('Only JPEG images are supported'), ok);
    },
});

app.use(express.json());
app.use(express.static(path.join(__dirname)));

// ── Error helper ─────────────────────────────────────────────────────────────
function sendError(res, status, message) {
    return res.status(status).json({ ok: false, error: message });
}

// ── POST /api/hash ────────────────────────────────────────────────────────────
// Hashes an uploaded JPEG (use this if Person 2 needs the hash from us).
app.post('/api/hash', upload.single('image'), (req, res) => {
    if (!req.file) return sendError(res, 400, 'No image file uploaded');

    const buf = req.file.buffer;
    if (!isValidJpeg(buf)) return sendError(res, 400, 'File is not a valid JPEG');

    const hash = sha256hex(buf);
    res.json({ ok: true, hash, filename: req.file.originalname });
});

// ── POST /api/embed ───────────────────────────────────────────────────────────
// Accepts multipart/form-data with:
//   image       – JPEG file
//   image_hash  – hex SHA-256 (from Person 2 / /api/hash)
//   signature   – base64 signature (from Person 2)
//   public_key  – PEM public key (from Person 2)
//   timestamp   – ISO timestamp (optional)
//   gps         – "lat,long" string (optional)
//   device      – device name (optional)
//   algorithm   – ES256 | Ed25519 | RS256 (optional, default ES256)
app.post('/api/embed', upload.single('image'), (req, res) => {
    if (!req.file) return sendError(res, 400, 'No image file uploaded');

    const { image_hash, signature, public_key, timestamp, gps, device, algorithm } = req.body;

    if (!image_hash) return sendError(res, 400, 'Missing field: image_hash');
    if (!signature) return sendError(res, 400, 'Missing field: signature');
    if (!public_key) return sendError(res, 400, 'Missing field: public_key');

    const buf = req.file.buffer;
    if (!isValidJpeg(buf)) return sendError(res, 400, 'File is not a valid JPEG');

    let signedJpeg;
    try {
        const manifest = createManifest({ imageHash: image_hash, timestamp, gps, device, signature, publicKey: public_key, algorithm });
        const manifestBuf = serializeManifest(manifest);
        signedJpeg = embedIntoJpeg(buf, manifestBuf);
    } catch (err) {
        return sendError(res, 500, `Embed failed: ${err.message}`);
    }

    const originalName = req.file.originalname.replace(/\.(jpe?g)$/i, '') || 'image';
    res.set('Content-Type', 'image/jpeg');
    res.set('Content-Disposition', `attachment; filename="${originalName}_signed.jpg"`);
    res.set('X-TrueLens-Status', 'SIGNED');
    res.send(signedJpeg);
});

// ── POST /api/verify ──────────────────────────────────────────────────────────
// Accepts multipart/form-data with:
//   image – possibly-signed JPEG
app.post('/api/verify', upload.single('image'), (req, res) => {
    if (!req.file) return sendError(res, 400, 'No image file uploaded');

    const buf = req.file.buffer;
    if (!isValidJpeg(buf)) return sendError(res, 400, 'File is not a valid JPEG');

    const result = verifyImage(buf);

    // Map status to human-readable label and HTTP status
    const statusMap = {
        [STATUS.AUTHENTIC]: { label: '✅ Authentic Image', http: 200 },
        [STATUS.TAMPERED]: { label: '❌ Tampered Image', http: 200 },
        [STATUS.INVALID_SIG]: { label: '❌ Invalid Signature', http: 200 },
        [STATUS.NO_METADATA]: { label: '⚠️ No TrueLens Metadata Found', http: 200 },
        [STATUS.ERROR]: { label: '⚠️ Processing Error', http: 422 },
    };

    const { label, http } = statusMap[result.status] || { label: 'Unknown', http: 500 };

    res.status(http).json({
        ok: true,
        status: result.status,
        label,
        hashMatch: result.hashMatch,
        signatureValid: result.signatureValid,
        computedHash: result.computedHash,
        storedHash: result.storedHash,
        manifest: result.manifest,
        errors: result.errors,
    });
});

// ── Global error handler ──────────────────────────────────────────────────────
app.use((err, _req, res, _next) => {
    console.error('[TrueLens Error]', err.message);
    res.status(err.status || 500).json({ ok: false, error: err.message });
});

// ── Start ─────────────────────────────────────────────────────────────────────
const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
    console.log(`\n🔍 TrueLens Verifier  →  http://localhost:${PORT}\n`);
});

module.exports = app; // for testing