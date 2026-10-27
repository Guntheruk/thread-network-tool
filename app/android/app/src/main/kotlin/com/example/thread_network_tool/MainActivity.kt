package com.example.thread_network_tool

import android.app.Activity
import android.content.Intent
import android.content.IntentSender
import android.os.Handler
import android.os.Looper
import com.google.android.gms.common.ConnectionResult
import com.google.android.gms.common.GoogleApiAvailability
import com.google.android.gms.common.api.ApiException
import com.google.android.gms.common.api.CommonStatusCodes
import com.google.android.gms.threadnetwork.ThreadNetwork
import com.google.android.gms.threadnetwork.ThreadNetworkCredentials
import com.google.android.gms.threadnetwork.ThreadNetworkStatusCodes
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "thread_network/android_credentials"
    private var nextRequestCode = 42117
    private val timeoutMillis = 45_000L
    private val handler = Handler(Looper.getMainLooper())
    private var pending: MethodChannel.Result? = null
    private var activeOperationId: String? = null
    private var activeRequestCode: Int? = null
    private var generation = 0
    private var timeout: Runnable? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "availability" -> result.success(status(readiness()))
                    "fetchPreferred" -> fetchPreferred(call.argument<String>("operationId"), result)
                    "cancelPending" -> {
                        val requestedId = call.argument<String>("operationId")
                        if (requestedId != null && requestedId == activeOperationId) {
                            finish(generation, "cancelled")
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // This checks the service only. It does not query the credential store.
    private fun readiness(): String = try {
        if (GoogleApiAvailability.getInstance().isGooglePlayServicesAvailable(this) ==
            ConnectionResult.SUCCESS
        ) "available" else "missingSdk"
    } catch (_: LinkageError) {
        "missingSdk"
    } catch (_: RuntimeException) {
        "failure"
    }

    private fun fetchPreferred(operationId: String?, result: MethodChannel.Result) {
        if (operationId == null || operationId.length !in 1..64) {
            result.success(status("failure"))
            return
        }
        if (pending != null) {
            result.success(status("busy"))
            return
        }
        val ready = readiness()
        if (ready != "available") {
            result.success(status(ready))
            return
        }
        pending = result
        activeOperationId = operationId
        val requestGeneration = ++generation
        val requestCode = nextRequestCode
        nextRequestCode = if (nextRequestCode == 65000) 42117 else nextRequestCode + 1
        activeRequestCode = requestCode
        val deadline = Runnable { finish(requestGeneration, "timedOut") }
        timeout = deadline
        handler.postDelayed(deadline, timeoutMillis)
        try {
            ThreadNetwork.getNetworkClient(this).getPreferredCredentials()
                .addOnSuccessListener { response ->
                    if (pending == null || requestGeneration != generation) return@addOnSuccessListener
                    val sender = response.intentSender
                    if (sender == null) {
                        finish(requestGeneration, "notConfigured")
                    } else {
                        try {
                            startIntentSenderForResult(sender, requestCode, null, 0, 0, 0)
                        } catch (_: IntentSender.SendIntentException) {
                            finish(requestGeneration, "failure")
                        } catch (_: SecurityException) {
                            finish(requestGeneration, "permissionDenied")
                        } catch (_: RuntimeException) {
                            finish(requestGeneration, "failure")
                        }
                    }
                }
                .addOnFailureListener { error ->
                    finish(requestGeneration, mapFailure(error))
                }
        } catch (_: LinkageError) {
            finish(requestGeneration, "missingSdk")
        } catch (_: SecurityException) {
            finish(requestGeneration, "permissionDenied")
        } catch (_: RuntimeException) {
            finish(requestGeneration, "failure")
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != activeRequestCode || pending == null) return
        val requestGeneration = generation
        if (resultCode != Activity.RESULT_OK) {
            finish(
                requestGeneration,
                if (resultCode == Activity.RESULT_CANCELED) "cancelled" else "failure"
            )
            return
        }
        if (data == null) {
            finish(requestGeneration, "failure")
            return
        }
        try {
            val bytes = ThreadNetworkCredentials.fromIntentSenderResultData(data)
                .activeOperationalDataset
            if (bytes.isEmpty() || bytes.size > 254) {
                finish(requestGeneration, "failure")
            } else {
                finish(requestGeneration, "available", bytes)
            }
        } catch (_: LinkageError) {
            finish(requestGeneration, "missingSdk")
        } catch (_: RuntimeException) {
            // Parsing failures and platform error text can contain sensitive values.
            finish(requestGeneration, "failure")
        }
    }

    private fun mapFailure(error: Exception): String {
        if (error !is ApiException) return "failure"
        return when (error.statusCode) {
            ThreadNetworkStatusCodes.LOCAL_NETWORK_NOT_CONNECTED -> "localNetworkDisconnected"
            ThreadNetworkStatusCodes.PLATFORM_NOT_SUPPORTED -> "unavailable"
            ThreadNetworkStatusCodes.PERMISSION_DENIED -> "permissionDenied"
            CommonStatusCodes.CANCELED -> "cancelled"
            CommonStatusCodes.TIMEOUT -> "timedOut"
            CommonStatusCodes.SERVICE_DISABLED,
            CommonStatusCodes.SERVICE_VERSION_UPDATE_REQUIRED -> "missingSdk"
            else -> "failure"
        }
    }

    private fun finish(requestGeneration: Int, state: String, bytes: ByteArray? = null) {
        if (pending == null || requestGeneration != generation) return
        val result = pending
        pending = null
        activeOperationId = null
        activeRequestCode = null
        timeout?.let(handler::removeCallbacks)
        timeout = null
        generation++
        result?.success(status(state, bytes))
    }

    private fun status(state: String, bytes: ByteArray? = null): Map<String, Any> =
        if (state == "available" && bytes != null) mapOf("status" to state, "dataset" to bytes)
        else mapOf("status" to state)

    override fun onDestroy() {
        finish(generation, "unavailable")
        super.onDestroy()
    }
}
