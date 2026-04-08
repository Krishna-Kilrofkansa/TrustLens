package com.example.camera_app

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Color
import android.graphics.SurfaceTexture
import android.hardware.camera2.*
import android.os.Handler
import android.os.Looper
import android.view.Surface
import android.view.TextureView
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.TextView
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView

class RawCameraView(
    private val context: Context,
    id: Int,
    creationParams: Map<String?, Any?>?,
    messenger: BinaryMessenger
) : PlatformView, MethodChannel.MethodCallHandler, TextureView.SurfaceTextureListener {

    private val methodChannel: MethodChannel = MethodChannel(messenger, "truelens_raw_camera_$id")
    private val frameLayout: FrameLayout = FrameLayout(context)
    private val textureView: TextureView = TextureView(context)
    private val loadingText: TextView = TextView(context)
    
    private val cameraManager: CameraManager = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
    private var cameraDevice: CameraDevice? = null
    private var captureSession: CameraCaptureSession? = null
    private var isFrontCamera = false
    
    private val mainHandler = Handler(Looper.getMainLooper())

    init {
        methodChannel.setMethodCallHandler(this)

        textureView.surfaceTextureListener = this
        textureView.layoutParams = FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT
        )
        
        loadingText.text = "Initializing Native RAW Camera..."
        loadingText.setTextColor(Color.WHITE)
        loadingText.textSize = 18f
        loadingText.layoutParams = FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.WRAP_CONTENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        ).apply {
            gravity = android.view.Gravity.CENTER
        }
        
        frameLayout.setBackgroundColor(Color.parseColor("#0F172A"))
        frameLayout.addView(textureView)
        frameLayout.addView(loadingText)
    }

    override fun getView(): View = frameLayout

    override fun dispose() {
        methodChannel.setMethodCallHandler(null)
        closeCamera()
    }

    private fun closeCamera() {
        captureSession?.close()
        captureSession = null
        cameraDevice?.close()
        cameraDevice = null
    }

    override fun onMethodCall(call: io.flutter.plugin.common.MethodCall, result: MethodChannel.Result) {
        if (call.method == "captureRaw") {
            println("TrueLens: Executing Native Android RAW capture")
            val mockRawBytes = ByteArray(1024) { 0xFF.toByte() } 
            result.success(mockRawBytes)
        } else if (call.method == "flipCamera") {
            isFrontCamera = !isFrontCamera
            closeCamera()
            openCamera()
            result.success(null)
        } else {
            result.notImplemented()
        }
    }

    override fun onSurfaceTextureAvailable(surfaceTexture: SurfaceTexture, width: Int, height: Int) {
        openCamera()
    }

    private fun openCamera() {
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
            mainHandler.post { loadingText.text = "Camera Permission Required" }
            return
        }

        try {
            val targetFacing = if (isFrontCamera) CameraCharacteristics.LENS_FACING_FRONT else CameraCharacteristics.LENS_FACING_BACK
            val cameraId = cameraManager.cameraIdList.firstOrNull { id ->
                val characteristics = cameraManager.getCameraCharacteristics(id)
                val facing = characteristics.get(CameraCharacteristics.LENS_FACING)
                facing == targetFacing
            }

            if (cameraId != null) {
                cameraManager.openCamera(cameraId, cameraStateCallback, mainHandler)
            } else {
                mainHandler.post { loadingText.text = "Camera not found" }
            }
        } catch (e: CameraAccessException) {
            e.printStackTrace()
            mainHandler.post { loadingText.text = "Camera Access Error" }
        }
    }

    private val cameraStateCallback = object : CameraDevice.StateCallback() {
        override fun onOpened(camera: CameraDevice) {
            cameraDevice = camera
            startPreview()
        }

        override fun onDisconnected(camera: CameraDevice) {
            camera.close()
            cameraDevice = null
        }

        override fun onError(camera: CameraDevice, error: Int) {
            camera.close()
            cameraDevice = null
            mainHandler.post { loadingText.text = "Camera Device Error $error" }
        }
    }

    private fun startPreview() {
        try {
            val surfaceTexture = textureView.surfaceTexture
            if (surfaceTexture == null) return
            // Default 1080p preview size structural placeholder
            surfaceTexture.setDefaultBufferSize(1920, 1080)

            val surface = Surface(surfaceTexture)
            val captureRequestBuilder = cameraDevice!!.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW)
            captureRequestBuilder.addTarget(surface)

            cameraDevice!!.createCaptureSession(
                listOf(surface),
                object : CameraCaptureSession.StateCallback() {
                    override fun onConfigured(session: CameraCaptureSession) {
                        if (cameraDevice == null) return
                        captureSession = session
                        try {
                            captureRequestBuilder.set(CaptureRequest.CONTROL_AF_MODE, CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE)
                            session.setRepeatingRequest(captureRequestBuilder.build(), null, mainHandler)
                            
                            // Hide loading text once preview starts
                            mainHandler.post { loadingText.visibility = View.GONE }
                        } catch (e: CameraAccessException) {
                            e.printStackTrace()
                        }
                    }

                    override fun onConfigureFailed(session: CameraCaptureSession) {
                        mainHandler.post { loadingText.text = "Camera Session Config Failed" }
                    }
                },
                mainHandler
            )
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    override fun onSurfaceTextureSizeChanged(surface: SurfaceTexture, width: Int, height: Int) {}
    override fun onSurfaceTextureDestroyed(surface: SurfaceTexture): Boolean = true
    override fun onSurfaceTextureUpdated(surface: SurfaceTexture) {}
}
