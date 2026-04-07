package com.example.camera_app.crypto

import android.util.Log
import java.security.KeyStore
import java.security.MessageDigest
import java.security.PrivateKey
import java.security.Signature

/**
 * TrueLensSigner
 * ==============
 * Performs cryptographic hashing and ECDSA signing using hardware-backed keys
 * stored in the Android Keystore.
 *
 * This class is the "sign oracle" — given arbitrary data (typically a C2PA claim
 * hash or raw image digest), it produces a DER-encoded ECDSA signature whose
 * private key never leaves the TEE/StrongBox boundary.
 *
 * Thread Safety:
 * - Each call to [signPayload] creates its own [Signature] instance, so
 *   concurrent calls from different threads (e.g., Rust JNI callbacks)
 *   are safe.
 *
 * Algorithms:
 * - Hashing:  SHA-256 (256-bit digest)
 * - Signing:  SHA256withECDSA (ECDSA over NIST P-256 / secp256r1)
 * - Output:   DER-encoded ECDSA signature (ASN.1: SEQUENCE { r INTEGER, s INTEGER })
 */
class TrueLensSigner {

    companion object {
        private const val TAG = "TrueLensSigner"

        /** Android Keystore provider name. */
        private const val KEYSTORE_PROVIDER = "AndroidKeyStore"

        /**
         * The JCA signature algorithm string.
         * SHA256withECDSA = SHA-256 hash + ECDSA sign in a single atomic operation.
         * The Keystore handles the hashing internally on the secure hardware,
         * ensuring the pre-image never needs to leave the TEE boundary.
         */
        private const val SIGNATURE_ALGORITHM = "SHA256withECDSA"

        /** SHA-256 digest algorithm for standalone hashing. */
        private const val HASH_ALGORITHM = "SHA-256"
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // Lazy-loaded Keystore instance
    // ─────────────────────────────────────────────────────────────────────────────
    private val keyStore: KeyStore by lazy {
        KeyStore.getInstance(KEYSTORE_PROVIDER).apply { load(null) }
    }

    // ═════════════════════════════════════════════════════════════════════════════
    // TASK 2a: Standalone SHA-256 Hashing
    // ═════════════════════════════════════════════════════════════════════════════

    /**
     * Compute the SHA-256 hash of arbitrary data.
     *
     * Use this to hash raw image pixel data before signing, or to compute
     * the C2PA claim hash that gets signed.
     *
     * @param data  Raw bytes to hash (e.g., camera frame pixels).
     * @return      32-byte SHA-256 digest.
     * @throws      SecurityException if the hash algorithm is not available.
     */
    fun hashData(data: ByteArray): ByteArray {
        return try {
            val digest = MessageDigest.getInstance(HASH_ALGORITHM)
            val hash = digest.digest(data)
            Log.d(TAG, "SHA-256 hash computed: ${hash.size} bytes, " +
                    "prefix=${hash.take(4).joinToString("") { "%02x".format(it) }}...")
            hash
        } catch (e: Exception) {
            Log.e(TAG, "❌ Hashing failed: ${e.message}", e)
            throw SecurityException("Failed to compute SHA-256 hash", e)
        }
    }

    // ═════════════════════════════════════════════════════════════════════════════
    // TASK 2b: ECDSA Signing with Hardware-Backed Private Key
    // ═════════════════════════════════════════════════════════════════════════════

    /**
     * Sign a payload using the hardware-backed ECDSA private key.
     *
     * IMPORTANT: The [payload] is typically the raw C2PA claim bytes or a
     * pre-computed hash. The [Signature] instance with "SHA256withECDSA" will
     * hash the payload internally before signing. If you've already hashed
     * the data, use [signPreHashedPayload] instead (which uses NONEwithECDSA).
     *
     * The private key NEVER leaves the TEE/StrongBox hardware module.
     * The signing operation happens entirely inside the secure enclave.
     *
     * @param payload  The raw bytes to be hashed-then-signed.
     * @return         DER-encoded ECDSA signature bytes, or null on failure.
     *                 Typical size: 70-72 bytes for P-256.
     */
    fun signPayload(payload: ByteArray): ByteArray? {
        return try {
            // ── Step 1: Retrieve the private key from hardware ──────────
            val privateKey = getPrivateKey()
                ?: throw SecurityException("No signing key found under alias " +
                        "'${TrueLensKeyStoreManager.KEY_ALIAS}'. " +
                        "Call TrueLensKeyStoreManager.generateOrLoadKeyPair() first.")

            // ── Step 2: Initialize the Signature engine ─────────────────
            // The "SHA256withECDSA" algorithm atomically:
            //   1. Computes SHA-256(payload) inside the hardware
            //   2. Signs the digest with the EC private key
            // This is more secure than hashing in software + signing in hardware.
            val signature = Signature.getInstance(SIGNATURE_ALGORITHM)
            signature.initSign(privateKey)

            // ── Step 3: Feed the payload data ───────────────────────────
            signature.update(payload)

            // ── Step 4: Produce the DER-encoded signature ───────────────
            val signatureBytes = signature.sign()

            Log.i(TAG, "✅ Payload signed successfully. " +
                    "Signature size: ${signatureBytes.size} bytes.")
            signatureBytes

        } catch (e: Exception) {
            Log.e(TAG, "❌ Signing failed: ${e.message}", e)
            null
        }
    }

    /**
     * Sign a PRE-HASHED payload (e.g., a 32-byte SHA-256 digest).
     *
     * Uses "NONEwithECDSA" to avoid double-hashing. This is the method
     * the Rust/JNI bridge should call when the C2PA library has already
     * computed the claim hash and just needs a raw ECDSA signature over it.
     *
     * @param hash  The pre-computed hash (must be exactly 32 bytes for SHA-256).
     * @return      DER-encoded ECDSA signature bytes, or null on failure.
     */
    fun signPreHashedPayload(hash: ByteArray): ByteArray? {
        return try {
            require(hash.size == 32) {
                "Pre-hashed payload must be exactly 32 bytes (SHA-256). Got: ${hash.size}"
            }

            val privateKey = getPrivateKey()
                ?: throw SecurityException("No signing key found. Generate key first.")

            // NONEwithECDSA: signs the raw bytes without any additional hashing.
            // The input is assumed to already be a hash digest.
            val signature = Signature.getInstance("NONEwithECDSA")
            signature.initSign(privateKey)
            signature.update(hash)

            val signatureBytes = signature.sign()

            Log.i(TAG, "✅ Pre-hashed payload signed. " +
                    "Signature size: ${signatureBytes.size} bytes.")
            signatureBytes

        } catch (e: Exception) {
            Log.e(TAG, "❌ Pre-hash signing failed: ${e.message}", e)
            null
        }
    }

    // ═════════════════════════════════════════════════════════════════════════════
    // Signature Verification (for local self-test / debugging)
    // ═════════════════════════════════════════════════════════════════════════════

    /**
     * Verify an ECDSA signature against the original payload using the
     * public key from the Keystore.
     *
     * This is a LOCAL verification utility — production verification should
     * use the C2PA validation pipeline.
     *
     * @param payload        The original data that was signed.
     * @param signatureBytes The DER-encoded ECDSA signature to verify.
     * @return               true if the signature is valid, false otherwise.
     */
    fun verifySignature(payload: ByteArray, signatureBytes: ByteArray): Boolean {
        return try {
            val cert = keyStore.getCertificate(TrueLensKeyStoreManager.KEY_ALIAS)
                ?: throw SecurityException("No certificate found for verification.")

            val verifier = Signature.getInstance(SIGNATURE_ALGORITHM)
            verifier.initVerify(cert.publicKey)
            verifier.update(payload)
            val isValid = verifier.verify(signatureBytes)

            Log.i(TAG, if (isValid) "✅ Signature verification PASSED."
                       else "❌ Signature verification FAILED.")
            isValid

        } catch (e: Exception) {
            Log.e(TAG, "❌ Verification error: ${e.message}", e)
            false
        }
    }

    // ═════════════════════════════════════════════════════════════════════════════
    // Private Helpers
    // ═════════════════════════════════════════════════════════════════════════════

    /**
     * Retrieves the hardware-backed private key from the Android Keystore.
     *
     * The returned [PrivateKey] is a PROXY object — it delegates all
     * cryptographic operations to the secure hardware. The actual key material
     * is never accessible in application memory.
     *
     * @return The private key proxy, or null if the key doesn't exist.
     */
    private fun getPrivateKey(): PrivateKey? {
        return try {
            val entry = keyStore.getEntry(TrueLensKeyStoreManager.KEY_ALIAS, null)
            if (entry is KeyStore.PrivateKeyEntry) {
                entry.privateKey
            } else {
                Log.e(TAG, "Keystore entry is not a PrivateKeyEntry. Type: ${entry?.javaClass?.name}")
                null
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error retrieving private key: ${e.message}", e)
            null
        }
    }
}
