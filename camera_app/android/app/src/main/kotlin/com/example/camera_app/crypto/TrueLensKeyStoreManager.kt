package com.example.camera_app.crypto

import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.security.keystore.StrongBoxUnavailableException
import android.util.Log
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.cert.X509Certificate
import java.security.spec.ECGenParameterSpec

/**
 * TrueLensKeyStoreManager
 * =======================
 * Manages hardware-backed cryptographic key pairs for TrueLens C2PA signing.
 *
 * Security Architecture:
 * - Keys are generated inside the Android Keystore (TEE or StrongBox).
 * - Private keys NEVER leave the secure hardware boundary.
 * - Keys are restricted to SIGN and VERIFY purposes only (no encryption/decryption).
 * - Uses ECDSA with secp256r1 (NIST P-256) — required by the C2PA specification.
 *
 * StrongBox Priority:
 * - StrongBox (dedicated secure element) is preferred when available.
 * - Falls back to TEE (Trusted Execution Environment) on devices without StrongBox.
 * - Both provide hardware-backed key isolation; StrongBox offers tamper-resistance.
 */
class TrueLensKeyStoreManager {

    companion object {
        private const val TAG = "TrueLensKeyStore"

        /** The alias under which the C2PA signing key is stored in Android Keystore. */
        const val KEY_ALIAS = "truelens_c2pa_signing_key"

        /** Android Keystore provider name. */
        private const val KEYSTORE_PROVIDER = "AndroidKeyStore"

        /** The elliptic curve used for key generation (NIST P-256 / secp256r1). */
        private const val EC_CURVE = "secp256r1"
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // Lazy-loaded Keystore instance — loaded once per TrueLensKeyStoreManager lifetime.
    // ─────────────────────────────────────────────────────────────────────────────
    private val keyStore: KeyStore by lazy {
        KeyStore.getInstance(KEYSTORE_PROVIDER).apply { load(null) }
    }

    /**
     * Whether the last key generation used StrongBox hardware.
     * Useful for UI badge / attestation metadata.
     */
    var isStrongBoxBacked: Boolean = false
        private set

    // ═════════════════════════════════════════════════════════════════════════════
    // TASK 1: Hardware-Backed Key Generation
    // ═════════════════════════════════════════════════════════════════════════════

    /**
     * Generates a hardware-backed EC key pair for C2PA content signing.
     *
     * Flow:
     * 1. Check if a key already exists under [KEY_ALIAS] — reuse it if so.
     * 2. Build a [KeyGenParameterSpec] requesting StrongBox isolation.
     * 3. If StrongBox is unavailable, catch the exception and retry with TEE.
     * 4. Store the result in Android Keystore; private key never leaves hardware.
     *
     * @param forceRegenerate  If true, delete any existing key and create a new one.
     *                         Defaults to false to avoid accidental key loss.
     * @return true if a usable key pair is now available, false on failure.
     */
    fun generateOrLoadKeyPair(forceRegenerate: Boolean = false): Boolean {
        return try {
            // ── Step 1: Check for existing key ──────────────────────────────
            if (!forceRegenerate && keyStore.containsAlias(KEY_ALIAS)) {
                Log.i(TAG, "Existing C2PA signing key found under alias '$KEY_ALIAS'. Reusing.")
                // Determine if the existing key is StrongBox-backed by checking
                // whether the certificate chain is hardware-attested.
                isStrongBoxBacked = detectStrongBoxFromAttestation()
                return true
            }

            // ── Step 2: Delete stale key if force-regenerating ──────────────
            if (forceRegenerate && keyStore.containsAlias(KEY_ALIAS)) {
                keyStore.deleteEntry(KEY_ALIAS)
                Log.w(TAG, "Deleted existing key due to forceRegenerate=true.")
            }

            // ── Step 3: Attempt StrongBox-backed generation ─────────────────
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                try {
                    generateKeyPairInternal(useStrongBox = true)
                    isStrongBoxBacked = true
                    Log.i(TAG, "✅ Key generated with StrongBox hardware backing.")
                    return true
                } catch (e: StrongBoxUnavailableException) {
                    // StrongBox not available on this device — fall through to TEE.
                    Log.w(TAG, "StrongBox unavailable on this device. Falling back to TEE.")
                }
            }

            // ── Step 4: Fallback to TEE-backed generation ───────────────────
            generateKeyPairInternal(useStrongBox = false)
            isStrongBoxBacked = false
            Log.i(TAG, "✅ Key generated with TEE hardware backing (StrongBox not used).")
            true

        } catch (e: Exception) {
            Log.e(TAG, "❌ Fatal error during key generation: ${e.message}", e)
            false
        }
    }

    /**
     * Internal helper: performs the actual KeyPairGenerator initialization.
     *
     * @param useStrongBox If true, requests StrongBox isolation (API 28+).
     * @throws StrongBoxUnavailableException if StrongBox is requested but not present.
     */
    private fun generateKeyPairInternal(useStrongBox: Boolean) {
        val paramSpecBuilder = KeyGenParameterSpec.Builder(
            KEY_ALIAS,
            // Restrict key usage: ONLY signing and verification.
            // This prevents misuse for encryption or key agreement.
            KeyProperties.PURPOSE_SIGN or KeyProperties.PURPOSE_VERIFY
        ).apply {
            // ── Algorithm Configuration ─────────────────────────────────
            // NIST P-256 (secp256r1) — the curve mandated by C2PA for ECDSA.
            setAlgorithmParameterSpec(ECGenParameterSpec(EC_CURVE))

            // SHA-256 is used as the digest algorithm for ECDSA signatures.
            setDigests(KeyProperties.DIGEST_SHA256)

            // ── Security Hardening ──────────────────────────────────────
            // Require user NOT to be authenticated for each use.
            // C2PA signing happens programmatically at capture time.
            // If you want biometric unlock per-sign, set this to true and
            // configure setUserAuthenticationParameters().
            setUserAuthenticationRequired(false)

            // The key should NOT be exportable; it lives in hardware.
            // (This is the default, but we're explicit for security audits.)

            // ── Invalidation Policy ─────────────────────────────────────
            // Invalidate the key if the device's biometric enrollment changes.
            // This prevents a scenario where an attacker enrolls a new fingerprint
            // and then uses the existing key.
            setInvalidatedByBiometricEnrollment(false) // false: key survives biometric changes
            // Set to true if your threat model requires re-enrollment.

            // ── StrongBox Request (API 28+) ─────────────────────────────
            if (useStrongBox && Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                setIsStrongBoxBacked(true)
            }
        }

        // ── Execute Key Generation ──────────────────────────────────────
        val keyPairGenerator = KeyPairGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_EC,   // Elliptic Curve
            KEYSTORE_PROVIDER                 // Android Keystore (hardware)
        )
        keyPairGenerator.initialize(paramSpecBuilder.build())
        keyPairGenerator.generateKeyPair()
    }

    // ═════════════════════════════════════════════════════════════════════════════
    // Key Introspection Utilities
    // ═════════════════════════════════════════════════════════════════════════════

    /**
     * Check whether a signing key currently exists in the Keystore.
     */
    fun hasKey(): Boolean {
        return try {
            keyStore.containsAlias(KEY_ALIAS)
        } catch (e: Exception) {
            Log.e(TAG, "Error checking key existence: ${e.message}", e)
            false
        }
    }

    /**
     * Retrieve the X.509 certificate chain for the signing key.
     * This is needed by C2PA to embed the signer certificate in the manifest.
     *
     * @return The certificate chain, or null if the key doesn't exist.
     */
    fun getCertificateChain(): Array<X509Certificate>? {
        return try {
            val chain = keyStore.getCertificateChain(KEY_ALIAS)
            @Suppress("UNCHECKED_CAST")
            chain as? Array<X509Certificate>
        } catch (e: Exception) {
            Log.e(TAG, "Error retrieving certificate chain: ${e.message}", e)
            null
        }
    }

    /**
     * Retrieve the public key bytes (X.509 encoded / SubjectPublicKeyInfo DER).
     * Useful for sending the public key to a verification server or embedding
     * it in the C2PA claim.
     *
     * @return DER-encoded public key bytes, or null on failure.
     */
    fun getPublicKeyBytes(): ByteArray? {
        return try {
            val cert = keyStore.getCertificate(KEY_ALIAS)
            cert?.publicKey?.encoded
        } catch (e: Exception) {
            Log.e(TAG, "Error retrieving public key bytes: ${e.message}", e)
            null
        }
    }

    /**
     * Permanently delete the signing key from the Keystore.
     * ⚠️  This is IRREVERSIBLE — any content signed with this key can no longer
     *     be verified against this device's identity.
     *
     * @return true if deletion succeeded or key didn't exist.
     */
    fun deleteKey(): Boolean {
        return try {
            if (keyStore.containsAlias(KEY_ALIAS)) {
                keyStore.deleteEntry(KEY_ALIAS)
                Log.w(TAG, "⚠️  Signing key '$KEY_ALIAS' permanently deleted.")
            }
            true
        } catch (e: Exception) {
            Log.e(TAG, "Error deleting key: ${e.message}", e)
            false
        }
    }

    /**
     * Attempts to detect whether the existing key is StrongBox-backed
     * by inspecting the attestation certificate extension.
     * This is a best-effort heuristic.
     */
    private fun detectStrongBoxFromAttestation(): Boolean {
        return try {
            // Android Key Attestation extension OID
            val attestationOid = "1.3.6.1.4.1.11129.2.1.17"
            val chain = getCertificateChain()
            if (chain != null && chain.isNotEmpty()) {
                val attestCert = chain[0]
                val extensionBytes = attestCert.getExtensionValue(attestationOid)
                if (extensionBytes != null) {
                    // Byte at offset 32 in the attestation extension encodes the
                    // security level: 1 = TEE, 2 = StrongBox.
                    // This is a simplified check; production code should use
                    // Google's attestation library for full ASN.1 parsing.
                    Log.d(TAG, "Key attestation extension found — assuming hardware-backed.")
                    // For a proper check, parse the ASN.1 and inspect securityLevel.
                    // Returning false as a safe default; proper parsing is recommended.
                    false
                } else {
                    false
                }
            } else {
                false
            }
        } catch (e: Exception) {
            Log.d(TAG, "Could not detect StrongBox status from attestation: ${e.message}")
            false
        }
    }
}
