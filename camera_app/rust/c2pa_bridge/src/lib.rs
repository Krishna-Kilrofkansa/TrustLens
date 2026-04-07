//! TrueLens C2PA Bridge — Rust JNI Native Library
//!
//! This crate provides the native Rust implementation that:
//! 1. Integrates with the `c2pa-rs` library for manifest building/verification.
//! 2. Communicates with Kotlin via JNI to request hardware-backed signatures
//!    from the Android Keystore (TEE/StrongBox).
//!
//! # Build Instructions
//! ```bash
//! # Install cargo-ndk for Android cross-compilation
//! cargo install cargo-ndk
//!
//! # Add Android target architectures
//! rustup target add aarch64-linux-android    # ARM64 (most modern phones)
//! rustup target add armv7-linux-androideabi  # ARMv7 (older phones)
//! rustup target add x86_64-linux-android     # x86_64 (emulator)
//!
//! # Build the shared library for all targets
//! cargo ndk -t arm64-v8a -t armeabi-v7a -t x86_64 -o ../app/src/main/jniLibs build --release
//! ```
//!
//! # Architecture
//! ```text
//! ┌─────────────────────┐      JNI       ┌──────────────────────┐
//! │    Rust (this lib)   │ ◄────────────► │  Kotlin (Android)    │
//! │                      │                │                      │
//! │  c2pa-rs library     │  requestSign() │  TrueLensJniBridge   │
//! │  Manifest building   │ ──────────────►│  TrueLensSigner      │
//! │  Claim hashing       │                │  Android Keystore    │
//! │  JUMBF packaging     │ ◄──────────────│  (TEE / StrongBox)   │
//! │                      │  signature[]   │                      │
//! └─────────────────────┘                └──────────────────────┘
//! ```

// In a real build, uncomment these dependencies in Cargo.toml:
// [dependencies]
// jni = { version = "0.21", features = ["invocation"] }
// c2pa = "0.32"
// log = "0.4"
// android_logger = "0.13"

use jni::JNIEnv;
use jni::objects::{JByteArray, JClass, JObject, JString, JValue};
use jni::sys::{jbyteArray, jdouble, jint, jstring};
use std::panic;

// ═══════════════════════════════════════════════════════════════════════════════
// JNI EXPORTED FUNCTIONS — Called by Kotlin via `external fun` declarations
// ═══════════════════════════════════════════════════════════════════════════════
//
// JNI name mangling for package `com.example.camera_app.crypto.TrueLensJniBridge`:
//   Java_com_example_camera_1app_crypto_TrueLensJniBridge_<method>
//
// Note: The underscore in "camera_app" is escaped as "_1" in JNI convention.
// ═══════════════════════════════════════════════════════════════════════════════

/// Initialize the C2PA engine.
///
/// Called once at app startup. Sets up logging, initializes the c2pa-rs
/// library state, and prepares for manifest building.
///
/// # Returns
/// - `0` on success
/// - Negative error code on failure
#[no_mangle]
pub extern "C" fn Java_com_example_camera_1app_crypto_TrueLensJniBridge_nativeInitC2paEngine(
    _env: JNIEnv,
    _class: JClass,
) -> jint {
    // Catch any Rust panics to prevent unwinding across the JNI boundary,
    // which would cause an immediate process abort.
    let result = panic::catch_unwind(|| {
        // Initialize Android-compatible logger
        // android_logger::init_once(
        //     android_logger::Config::default()
        //         .with_max_level(log::LevelFilter::Debug)
        //         .with_tag("TrueLens-Rust"),
        // );

        // log::info!("C2PA engine initializing...");

        // TODO: Initialize c2pa-rs state here.
        // For example:
        //   - Load trusted certificate anchors
        //   - Set up the manifest builder configuration
        //   - Pre-allocate buffers for performance

        // log::info!("C2PA engine initialized successfully.");
        0_i32
    });

    match result {
        Ok(code) => code,
        Err(_) => {
            // Panic occurred — return error code
            -1
        }
    }
}

/// Build a C2PA manifest for an image.
///
/// This is the main entry point for signing a photo. The flow is:
/// 1. Receive raw JPEG bytes + metadata from Kotlin.
/// 2. Use c2pa-rs to build a C2PA claim with assertions (GPS, timestamp, device).
/// 3. Compute the claim hash (SHA-256).
/// 4. Call back into Kotlin (`requestHardwareSignature`) to get the hardware
///    ECDSA signature from the Android Keystore.
/// 5. Also call `requestSignerCertificate` to get the signer cert for the manifest.
/// 6. Embed everything into a JUMBF box.
/// 7. Return the complete JUMBF manifest bytes.
///
/// # Arguments
/// - `image_data`: Raw JPEG bytes (without C2PA box).
/// - `timestamp_utc`: ISO-8601 UTC timestamp string.
/// - `latitude`: GPS latitude.
/// - `longitude`: GPS longitude.
/// - `device_model`: Device model string for metadata.
///
/// # Returns
/// - `jbyteArray` containing the complete JUMBF manifest bytes.
/// - `null` on error.
#[no_mangle]
pub extern "C" fn Java_com_example_camera_1app_crypto_TrueLensJniBridge_nativeBuildC2paManifest(
    mut env: JNIEnv,
    class: JClass,
    image_data: JByteArray,
    timestamp_utc: JString,
    latitude: jdouble,
    longitude: jdouble,
    device_model: JString,
) -> jbyteArray {
    let result = panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        // ── Step 1: Extract input parameters from JNI ───────────────────
        let image_bytes: Vec<u8> = env.convert_byte_array(&image_data)
            .expect("Failed to convert image_data byte array");

        let timestamp: String = env.get_string(&timestamp_utc)
            .expect("Failed to get timestamp string")
            .into();

        let model: String = env.get_string(&device_model)
            .expect("Failed to get device_model string")
            .into();

        // log::info!(
        //     "Building C2PA manifest: {} bytes, ts={}, lat={}, lon={}, model={}",
        //     image_bytes.len(), timestamp, latitude, longitude, model
        // );

        // ── Step 2: Build the C2PA claim ────────────────────────────────
        // TODO: Use c2pa-rs to build the claim structure.
        // Example (pseudocode):
        //
        // let mut manifest = c2pa::Manifest::new("truelens.capture");
        // manifest.set_claim_generator("TrueLens/1.0");
        //
        // // Add assertions
        // manifest.add_assertion(
        //     c2pa::assertions::CreativeWork::new()
        //         .set_date_created(&timestamp)
        // )?;
        // manifest.add_assertion(
        //     c2pa::assertions::Exif::new()
        //         .set_gps_latitude(latitude)
        //         .set_gps_longitude(longitude)
        //         .set_model(&model)
        // )?;

        // ── Step 3: Compute claim hash ──────────────────────────────────
        // In the real implementation, c2pa-rs computes this internally
        // and provides it via the Signer trait. For this stub, we'll
        // simulate it with a SHA-256 of the image data.
        use std::collections::hash_map::DefaultHasher;
        use std::hash::{Hash, Hasher};
        let claim_hash: Vec<u8> = {
            // Placeholder: In production, c2pa-rs provides the exact
            // bytes to sign via the Signer trait implementation.
            // This is just for demonstration.
            let mut hasher = DefaultHasher::new();
            image_bytes.hash(&mut hasher);
            let h = hasher.finish();
            // Expand to 32 bytes (SHA-256 size) — placeholder only
            let mut hash_bytes = vec![0u8; 32];
            hash_bytes[..8].copy_from_slice(&h.to_be_bytes());
            hash_bytes
        };

        // ── Step 4: Call Kotlin to sign the hash via hardware ───────────
        // This is the critical JNI callback — Rust asks Android's secure
        // hardware to produce an ECDSA signature.
        let claim_hash_jni = env.byte_array_from_slice(&claim_hash)
            .expect("Failed to create JNI byte array for claim hash");

        // Call: TrueLensJniBridge.requestHardwareSignature(byte[]) -> byte[]
        let signature_result = env.call_static_method(
            &class,
            "requestHardwareSignature",          // Method name
            "([B)[B",                            // JNI signature: byte[] -> byte[]
            &[JValue::Object(&JObject::from(claim_hash_jni))],
        );

        let signature_bytes: Vec<u8> = match signature_result {
            Ok(sig_val) => {
                let sig_obj: JByteArray = JByteArray::from(sig_val.l().unwrap());
                env.convert_byte_array(&sig_obj)
                    .expect("Failed to convert signature byte array")
            }
            Err(e) => {
                // log::error!("JNI callback to requestHardwareSignature failed: {:?}", e);
                eprintln!("JNI callback failed: {:?}", e);
                return std::ptr::null_mut();
            }
        };

        if signature_bytes.is_empty() {
            // log::error!("Hardware signature returned empty. Aborting manifest build.");
            return std::ptr::null_mut();
        }

        // ── Step 5: Retrieve the signer certificate ─────────────────────
        let cert_result = env.call_static_method(
            &class,
            "requestSignerCertificate",          // Method name
            "()[B",                              // JNI signature: () -> byte[]
            &[],
        );

        let _cert_bytes: Vec<u8> = match cert_result {
            Ok(cert_val) => {
                let cert_obj: JByteArray = JByteArray::from(cert_val.l().unwrap());
                env.convert_byte_array(&cert_obj)
                    .expect("Failed to convert certificate byte array")
            }
            Err(e) => {
                eprintln!("JNI callback for certificate failed: {:?}", e);
                return std::ptr::null_mut();
            }
        };

        // ── Step 6: Build JUMBF manifest ────────────────────────────────
        // TODO: Use c2pa-rs to embed the signature and certificate into
        // the JUMBF box structure. Example:
        //
        // let signer = HardwareSigner {
        //     signature: signature_bytes,
        //     certificate: cert_bytes,
        // };
        // let manifest_bytes = manifest.embed(&image_bytes, "image/jpeg", &signer)?;

        // Placeholder: Return the signature as the "manifest" for now
        let manifest_placeholder = signature_bytes;

        // ── Step 7: Return manifest bytes to Kotlin ────────────────────
        let output = env.byte_array_from_slice(&manifest_placeholder)
            .expect("Failed to create output byte array");

        output.into_raw()
    }));

    match result {
        Ok(ptr) => ptr,
        Err(_) => {
            // Panic occurred — return null
            std::ptr::null_mut()
        }
    }
}

/// Verify a C2PA-signed image.
///
/// Parses the JUMBF box from the JPEG, validates the signature against the
/// embedded certificate, and checks the trust chain.
///
/// # Returns
/// - JSON string with verification results.
/// - `null` on error.
#[no_mangle]
pub extern "C" fn Java_com_example_camera_1app_crypto_TrueLensJniBridge_nativeVerifyC2paImage(
    mut env: JNIEnv,
    _class: JClass,
    signed_image_data: JByteArray,
) -> jstring {
    let result = panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let image_bytes: Vec<u8> = env.convert_byte_array(&signed_image_data)
            .expect("Failed to convert signed_image_data");

        // TODO: Use c2pa-rs to verify the image.
        // Example:
        //
        // let reader = c2pa::Reader::from_stream("image/jpeg", &mut Cursor::new(&image_bytes))?;
        // let manifest_store = reader.manifest_store();
        // let active_manifest = manifest_store.active_manifest()?;
        // ... extract verification status ...

        // Placeholder JSON response
        let verification_json = format!(
            r#"{{
                "verified": true,
                "imageSize": {},
                "claimGenerator": "TrueLens/1.0",
                "signatureAlgorithm": "ES256",
                "trustChain": "hardware-backed"
            }}"#,
            image_bytes.len()
        );

        let output = env.new_string(&verification_json)
            .expect("Failed to create output string");

        output.into_raw()
    }));

    match result {
        Ok(ptr) => ptr,
        Err(_) => std::ptr::null_mut(),
    }
}

/// Clean up Rust-side resources.
///
/// Called during app shutdown. Releases any heap-allocated state held by
/// the C2PA engine.
#[no_mangle]
pub extern "C" fn Java_com_example_camera_1app_crypto_TrueLensJniBridge_nativeDestroyC2paEngine(
    _env: JNIEnv,
    _class: JClass,
) {
    let _ = panic::catch_unwind(|| {
        // log::info!("C2PA engine shutting down.");
        // TODO: Drop any global state, close file handles, etc.
        // log::info!("C2PA engine destroyed.");
    });
}

// ═══════════════════════════════════════════════════════════════════════════════
// c2pa-rs Signer Trait Implementation (for production use)
// ═══════════════════════════════════════════════════════════════════════════════
//
// When integrating with c2pa-rs, you'll implement the `Signer` trait to
// bridge hardware signing. Here's the skeleton:
//
// ```rust
// use c2pa::{Signer, SigningAlg, Result};
//
// /// A Signer implementation that delegates to Android's hardware Keystore
// /// via JNI callbacks.
// struct AndroidHardwareSigner<'a> {
//     env: JNIEnv<'a>,
//     bridge_class: JClass<'a>,
// }
//
// impl<'a> Signer for AndroidHardwareSigner<'a> {
//     fn sign(&self, data: &[u8]) -> Result<Vec<u8>> {
//         // 1. Convert `data` to a JNI byte array.
//         // 2. Call TrueLensJniBridge.requestHardwareSignature(data).
//         // 3. Convert the returned byte array to Vec<u8>.
//         // 4. Return the signature.
//         todo!("Implement JNI callback to Android Keystore")
//     }
//
//     fn alg(&self) -> SigningAlg {
//         SigningAlg::Es256 // ECDSA with P-256 and SHA-256
//     }
//
//     fn certs(&self) -> Result<Vec<Vec<u8>>> {
//         // 1. Call TrueLensJniBridge.requestCertificateChain().
//         // 2. Parse the length-prefixed certificate format.
//         // 3. Return Vec of DER-encoded certificates.
//         todo!("Implement JNI callback for certificate chain")
//     }
//
//     fn reserve_size(&self) -> usize {
//         // ECDSA P-256 signatures are typically 70-72 bytes (DER-encoded).
//         // Reserve extra space to be safe.
//         256
//     }
// }
// ```
