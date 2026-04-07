package com.example.camera_app.crypto

import android.util.Base64
import android.util.Log

/**
 * TrueLensJniBridge
 * =================
 * The JNI (Java Native Interface) bridge between the Android/Kotlin cryptographic
 * engine and the native Rust C2PA library (c2pa-rs).
 *
 * Architecture Overview:
 * ┌─────────────────────────────────────────────────────────────────────┐
 * │  Rust (c2pa-rs)                                                    │
 * │    │                                                               │
 * │    ├─ Builds C2PA manifest & claim                                 │
 * │    ├─ Computes claim hash (SHA-256)                                │
 * │    ├─ Calls JNI: requestSignature(claimHash) ──────────────┐       │
 * │    │                                                       │       │
 * │    │  ┌────────────────────────────────────────────────┐    │       │
 * │    │  │  Kotlin (this bridge)                          │◄───┘       │
 * │    │  │    │                                           │           │
 * │    │  │    ├─ Receives claim hash from Rust            │           │
 * │    │  │    ├─ Calls TrueLensSigner.signPreHashedPayload│           │
 * │    │  │    ├─ Hardware signs inside TEE/StrongBox      │           │
 * │    │  │    └─ Returns DER signature to Rust ───────────┼───┐       │
 * │    │  └────────────────────────────────────────────────┘   │       │
 * │    │                                                       │       │
 * │    ├─ Receives DER-encoded ECDSA signature ◄───────────────┘       │
 * │    ├─ Embeds signature in C2PA JUMBF box                          │
 * │    └─ Done                                                         │
 * └─────────────────────────────────────────────────────────────────────┘
 *
 * JNI Naming Convention:
 * - Native function names follow JNI mangling rules:
 *   Java_com_example_camera_1app_crypto_TrueLensJniBridge_<methodName>
 *   (Note: underscore in "camera_app" becomes "_1" in JNI naming)
 *
 * Threading:
 * - Rust may call these functions from any thread.
 * - Android Keystore operations are thread-safe.
 * - No main-thread requirement for crypto operations.
 */
class TrueLensJniBridge private constructor() {

    companion object {
        private const val TAG = "TrueLensJniBridge"

        /**
         * Name of the native Rust shared library.
         * This corresponds to the .so file built by cargo-ndk:
         *   - libc2pa_bridge.so (ARM64)
         *   - libc2pa_bridge.so (ARMv7)
         *   - libc2pa_bridge.so (x86_64 emulator)
         */
        private const val NATIVE_LIB_NAME = "c2pa_bridge"

        // ─────────────────────────────────────────────────────────────
        // Singleton pattern for the bridge
        // ─────────────────────────────────────────────────────────────
        @Volatile
        private var instance: TrueLensJniBridge? = null

        /** Lazily-initialized crypto components */
        private val keyStoreManager = TrueLensKeyStoreManager()
        private val signer = TrueLensSigner()

        /**
         * Whether the native library has been loaded.
         * Prevents double-loading crashes.
         */
        private var nativeLibLoaded = false

        /**
         * Get the singleton bridge instance.
         * Thread-safe via double-checked locking.
         */
        fun getInstance(): TrueLensJniBridge {
            return instance ?: synchronized(this) {
                instance ?: TrueLensJniBridge().also { instance = it }
            }
        }

        /**
         * Load the native Rust library.
         * Call this once during Application.onCreate() or Activity.onCreate().
         *
         * @return true if the library loaded successfully, false otherwise.
         */
        fun loadNativeLibrary(): Boolean {
            return try {
                if (!nativeLibLoaded) {
                    System.loadLibrary(NATIVE_LIB_NAME)
                    nativeLibLoaded = true
                    Log.i(TAG, "✅ Native library '$NATIVE_LIB_NAME' loaded successfully.")
                }
                true
            } catch (e: UnsatisfiedLinkError) {
                Log.e(TAG, "❌ Failed to load native library '$NATIVE_LIB_NAME': ${e.message}", e)
                nativeLibLoaded = false
                false
            }
        }
    }

    // ═════════════════════════════════════════════════════════════════════════════
    // TASK 3a: Native (Rust → Kotlin) External Function Declarations
    // ═════════════════════════════════════════════════════════════════════════════
    //
    // These are functions IMPLEMENTED IN RUST that Kotlin can call.
    // The Rust code implements these as #[no_mangle] pub extern "C" fn ...
    // ═════════════════════════════════════════════════════════════════════════════

    /**
     * Initialize the Rust C2PA engine.
     * Called once at app startup after loading the native library.
     *
     * @return 0 on success, negative error code on failure.
     */
    external fun nativeInitC2paEngine(): Int

    /**
     * Instruct the Rust C2PA library to build a C2PA manifest, compute the
     * claim hash, sign it (via callback to Kotlin), and return the complete
     * JUMBF (C2PA) manifest box ready for embedding into a JPEG.
     *
     * @param imageData      Raw image bytes (JPEG baseline without C2PA box).
     * @param timestampUtc   ISO-8601 timestamp string (e.g., "2026-04-07T15:35:00Z").
     * @param latitude       GPS latitude as a double.
     * @param longitude      GPS longitude as a double.
     * @param deviceModel    Device model string for C2PA metadata.
     * @return               Complete JUMBF manifest bytes, or null on error.
     */
    external fun nativeBuildC2paManifest(
        imageData: ByteArray,
        timestampUtc: String,
        latitude: Double,
        longitude: Double,
        deviceModel: String
    ): ByteArray?

    /**
     * Verify a C2PA-signed image.
     *
     * @param signedImageData   The complete JPEG with embedded JUMBF C2PA box.
     * @return                  JSON string containing verification results,
     *                          or null on error.
     */
    external fun nativeVerifyC2paImage(signedImageData: ByteArray): String?

    /**
     * Clean up / release Rust-side resources.
     * Call this during application shutdown.
     */
    external fun nativeDestroyC2paEngine()

    // ═════════════════════════════════════════════════════════════════════════════
    // TASK 3b: Kotlin → Rust Callback Functions
    // ═════════════════════════════════════════════════════════════════════════════
    //
    // These functions are CALLED BY RUST via JNI to request cryptographic
    // operations from the Android hardware. Rust discovers and calls these
    // methods using JNIEnv::call_method().
    //
    // ⚠️  IMPORTANT: These method names and signatures must EXACTLY match
    //     what the Rust JNI code calls. Changing them requires updating the
    //     Rust side as well.
    // ═════════════════════════════════════════════════════════════════════════════

    /**
     * Called by Rust when it needs the Android hardware to sign a claim hash.
     *
     * The Rust C2PA library computes the claim hash, then calls this method
     * via JNI. This method delegates to [TrueLensSigner.signPreHashedPayload]
     * which performs the ECDSA signature inside the TEE/StrongBox.
     *
     * JNI Signature: ([B)[B
     *   - Takes: byte[] (the 32-byte SHA-256 claim hash)
     *   - Returns: byte[] (DER-encoded ECDSA signature)
     *
     * @param claimHash  32-byte SHA-256 hash of the C2PA claim, computed by Rust.
     * @return           DER-encoded ECDSA signature, or empty array on failure.
     */
    @JvmStatic
    @Suppress("unused") // Called from Rust via JNI reflection
    fun requestHardwareSignature(claimHash: ByteArray): ByteArray {
        Log.d(TAG, "📥 Rust requested hardware signature for ${claimHash.size}-byte hash.")

        // Validate input
        if (claimHash.size != 32) {
            Log.e(TAG, "❌ Invalid claim hash size: ${claimHash.size} (expected 32)")
            return ByteArray(0)
        }

        // Ensure the signing key exists
        if (!keyStoreManager.hasKey()) {
            Log.e(TAG, "❌ No signing key available. Generating one now...")
            val generated = keyStoreManager.generateOrLoadKeyPair()
            if (!generated) {
                Log.e(TAG, "❌ Key generation failed. Cannot sign.")
                return ByteArray(0)
            }
        }

        // Perform the hardware-backed signature
        val signature = signer.signPreHashedPayload(claimHash)
        if (signature != null) {
            Log.i(TAG, "📤 Returning ${signature.size}-byte signature to Rust.")
            return signature
        }

        Log.e(TAG, "❌ Signing returned null. Returning empty array.")
        return ByteArray(0)
    }

    /**
     * Called by Rust to retrieve the device's X.509 certificate (DER-encoded).
     * The C2PA manifest needs the signer's certificate to build the trust chain.
     *
     * JNI Signature: ()[B
     *   - Takes: nothing
     *   - Returns: byte[] (DER-encoded X.509 certificate)
     *
     * @return DER-encoded X.509 certificate bytes, or empty array on failure.
     */
    @JvmStatic
    @Suppress("unused") // Called from Rust via JNI reflection
    fun requestSignerCertificate(): ByteArray {
        Log.d(TAG, "📥 Rust requested signer certificate.")

        return try {
            val certChain = keyStoreManager.getCertificateChain()
            if (certChain != null && certChain.isNotEmpty()) {
                val certBytes = certChain[0].encoded
                Log.i(TAG, "📤 Returning ${certBytes.size}-byte certificate to Rust.")
                certBytes
            } else {
                Log.e(TAG, "❌ No certificate chain available.")
                ByteArray(0)
            }
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error retrieving certificate: ${e.message}", e)
            ByteArray(0)
        }
    }

    /**
     * Called by Rust to retrieve the full certificate chain (DER-encoded).
     * Each certificate is concatenated with a 4-byte big-endian length prefix.
     *
     * Wire format: [len1:u32][cert1:bytes][len2:u32][cert2:bytes]...
     *
     * @return Length-prefixed concatenated DER certificates, or empty on failure.
     */
    @JvmStatic
    @Suppress("unused") // Called from Rust via JNI reflection
    fun requestCertificateChain(): ByteArray {
        Log.d(TAG, "📥 Rust requested full certificate chain.")

        return try {
            val certChain = keyStoreManager.getCertificateChain()
            if (certChain == null || certChain.isEmpty()) {
                Log.e(TAG, "❌ No certificate chain available.")
                return ByteArray(0)
            }

            // Serialize: [4-byte length BE][cert DER bytes] for each cert
            val buffer = mutableListOf<Byte>()
            for (cert in certChain) {
                val certBytes = cert.encoded
                val len = certBytes.size
                // Big-endian 4-byte length prefix
                buffer.add(((len shr 24) and 0xFF).toByte())
                buffer.add(((len shr 16) and 0xFF).toByte())
                buffer.add(((len shr 8) and 0xFF).toByte())
                buffer.add((len and 0xFF).toByte())
                buffer.addAll(certBytes.toList())
            }

            val result = buffer.toByteArray()
            Log.i(TAG, "📤 Returning ${certChain.size} certificates " +
                    "(${result.size} bytes total) to Rust.")
            result

        } catch (e: Exception) {
            Log.e(TAG, "❌ Error building certificate chain: ${e.message}", e)
            ByteArray(0)
        }
    }

    /**
     * Called by Rust to check whether the device has hardware-backed key storage.
     *
     * JNI Signature: ()Z
     *   - Returns: boolean
     *
     * @return true if keys are StrongBox-backed, false if TEE-backed.
     */
    @JvmStatic
    @Suppress("unused") // Called from Rust via JNI reflection
    fun isStrongBoxBacked(): Boolean {
        return keyStoreManager.isStrongBoxBacked
    }

    // ═════════════════════════════════════════════════════════════════════════════
    // High-Level Convenience API (Kotlin-side orchestration)
    // ═════════════════════════════════════════════════════════════════════════════

    /**
     * Initialize the complete TrueLens crypto pipeline.
     * Call this once during app startup.
     *
     * 1. Generates (or loads) the hardware-backed signing key.
     * 2. Loads the native Rust library.
     * 3. Initializes the Rust C2PA engine.
     *
     * @return true if all initialization steps succeeded.
     */
    fun initialize(): Boolean {
        Log.i(TAG, "═══════════════════════════════════════════")
        Log.i(TAG, "  TrueLens Crypto Pipeline — Initializing  ")
        Log.i(TAG, "═══════════════════════════════════════════")

        // Step 1: Generate or load hardware-backed key pair
        val keyReady = keyStoreManager.generateOrLoadKeyPair()
        if (!keyReady) {
            Log.e(TAG, "❌ Key generation/loading failed. Aborting initialization.")
            return false
        }
        Log.i(TAG, "🔑 Key ready. StrongBox: ${keyStoreManager.isStrongBoxBacked}")

        // Step 2: Load native Rust library
        val libLoaded = loadNativeLibrary()
        if (!libLoaded) {
            Log.w(TAG, "⚠️  Native library not loaded. C2PA manifest building " +
                    "will not be available. Signing-only mode active.")
            // Don't return false — signing still works without the Rust lib.
            // The Rust lib is needed for manifest building, but the crypto core
            // (key gen + signing) is fully functional without it.
        }

        // Step 3: Initialize Rust engine (only if lib loaded)
        if (libLoaded) {
            val initResult = nativeInitC2paEngine()
            if (initResult != 0) {
                Log.e(TAG, "❌ Rust C2PA engine initialization failed: code $initResult")
                return false
            }
            Log.i(TAG, "⚙️  Rust C2PA engine initialized.")
        }

        Log.i(TAG, "═══════════════════════════════════════════")
        Log.i(TAG, "  TrueLens Crypto Pipeline — Ready ✅     ")
        Log.i(TAG, "═══════════════════════════════════════════")
        return true
    }

    /**
     * Sign raw image data and return the signature + metadata bundle.
     * This is a convenience wrapper for use from Kotlin/Flutter without
     * going through the full Rust C2PA pipeline.
     *
     * @param rawImageBytes  The raw image pixel data.
     * @return A map containing hash, signature, certificate, and metadata.
     */
    fun signImage(rawImageBytes: ByteArray): Map<String, Any?> {
        val hash = signer.hashData(rawImageBytes)
        val signature = signer.signPayload(rawImageBytes)
        val publicKey = keyStoreManager.getPublicKeyBytes()

        return mapOf(
            "hash" to Base64.encodeToString(hash, Base64.NO_WRAP),
            "signature" to signature?.let { Base64.encodeToString(it, Base64.NO_WRAP) },
            "publicKey" to publicKey?.let { Base64.encodeToString(it, Base64.NO_WRAP) },
            "isStrongBoxBacked" to keyStoreManager.isStrongBoxBacked,
            "algorithm" to "SHA256withECDSA",
            "curve" to "secp256r1",
            "signedAt" to System.currentTimeMillis()
        )
    }
}
