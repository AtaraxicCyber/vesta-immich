package app.alextran.immich.vesta

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.wifi.WifiNetworkSpecifier
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import java.nio.charset.StandardCharsets
import java.util.concurrent.Executors

private const val CHANNEL = "vesta.pairing/wifi"
private const val JOIN_TIMEOUT_MS = 15_000L
private const val REQUEST_TIMEOUT_MS = 15_000

/**
 * Joins a Vesta unit's temporary setup AP (SSID/password come from the
 * scanned claim label, never hardcoded) and relays the WiFi-handoff POST to
 * it over that specific network -- not the phone's default route, since the
 * setup AP has no internet and joining it as the default network would kill
 * the phone's own connectivity for the duration of the request.
 *
 * WifiNetworkSpecifier (API 29+) is deliberately chosen over
 * WifiNetworkSuggestion: it's scoped to this app's process, doesn't persist
 * in the OS's saved-network list, and needs no location permission -- exactly
 * the "invisible to the customer" one-shot join PHASE1-SETUP-REDESIGN.md
 * calls for. Below API 29 there is no equivalent; callers fall back to
 * asking the customer to join the setup network manually via Settings.
 */
class VestaWifiPairingPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
  private var channel: MethodChannel? = null
  private var appContext: Context? = null
  private var connectivityManager: ConnectivityManager? = null
  private var activeCallback: ConnectivityManager.NetworkCallback? = null
  private var activeNetwork: Network? = null
  private val mainHandler = Handler(Looper.getMainLooper())
  private val ioExecutor = Executors.newCachedThreadPool()

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    appContext = binding.applicationContext
    connectivityManager =
      binding.applicationContext.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
    channel = MethodChannel(binding.binaryMessenger, CHANNEL)
    channel?.setMethodCallHandler(this)
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    releaseNetwork()
    channel?.setMethodCallHandler(null)
    channel = null
    appContext = null
    connectivityManager = null
  }

  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    when (call.method) {
      "isSupported" -> result.success(Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q)
      "joinSetupNetwork" -> {
        val ssid = call.argument<String>("ssid")
        val password = call.argument<String>("password")
        if (ssid.isNullOrEmpty()) {
          result.error("bad_args", "ssid required", null)
          return
        }
        joinSetupNetwork(ssid, password.orEmpty(), result)
      }
      "postJson" -> {
        val path = call.argument<String>("path")
        val body = call.argument<String>("body")
        if (path.isNullOrEmpty() || body == null) {
          result.error("bad_args", "path and body required", null)
          return
        }
        postJson(path, body, result)
      }
      "releaseSetupNetwork" -> {
        releaseNetwork()
        result.success(null)
      }
      else -> result.notImplemented()
    }
  }

  private fun joinSetupNetwork(ssid: String, password: String, result: MethodChannel.Result) {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
      result.error("unsupported", "WifiNetworkSpecifier requires Android 10+", null)
      return
    }
    val cm = connectivityManager ?: run {
      result.error("no_context", "Plugin not attached", null)
      return
    }
    releaseNetwork()

    val specifierBuilder = WifiNetworkSpecifier.Builder().setSsid(ssid)
    if (password.isNotEmpty()) {
      specifierBuilder.setWpa2Passphrase(password)
    }
    val specifier = specifierBuilder.build()

    val request = NetworkRequest.Builder()
      .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
      .removeCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
      .setNetworkSpecifier(specifier)
      .build()

    var settled = false
    val timeoutRunnable = Runnable {
      if (!settled) {
        settled = true
        releaseNetwork()
        result.error("timeout", "Timed out joining $ssid", null)
      }
    }

    val callback = object : ConnectivityManager.NetworkCallback() {
      override fun onAvailable(network: Network) {
        if (settled) return
        settled = true
        mainHandler.removeCallbacks(timeoutRunnable)
        activeNetwork = network
        result.success(true)
      }

      override fun onUnavailable() {
        if (settled) return
        settled = true
        mainHandler.removeCallbacks(timeoutRunnable)
        activeCallback = null
        result.error("unavailable", "Could not join $ssid", null)
      }
    }
    activeCallback = callback
    mainHandler.postDelayed(timeoutRunnable, JOIN_TIMEOUT_MS)
    cm.requestNetwork(request, callback)
  }

  private fun postJson(path: String, body: String, result: MethodChannel.Result) {
    val network = activeNetwork ?: run {
      result.error("not_joined", "No active setup-network connection", null)
      return
    }
    ioExecutor.execute {
      try {
        val url = URL("http://192.168.10.1$path")
        val connection = network.openConnection(url) as HttpURLConnection
        connection.requestMethod = "POST"
        connection.doOutput = true
        connection.connectTimeout = REQUEST_TIMEOUT_MS
        connection.readTimeout = REQUEST_TIMEOUT_MS
        connection.setRequestProperty("Content-Type", "application/json")
        OutputStreamWriter(connection.outputStream, StandardCharsets.UTF_8).use {
          it.write(body)
        }
        val status = connection.responseCode
        val stream = if (status in 200..299) connection.inputStream else connection.errorStream
        val responseBody = stream?.bufferedReader(StandardCharsets.UTF_8)?.use { it.readText() } ?: ""
        connection.disconnect()
        mainHandler.post {
          result.success(mapOf("status" to status, "body" to responseBody))
        }
      } catch (e: Exception) {
        mainHandler.post {
          result.error("request_failed", e.message, null)
        }
      }
    }
  }

  private fun releaseNetwork() {
    val cm = connectivityManager
    val callback = activeCallback
    if (cm != null && callback != null) {
      try {
        cm.unregisterNetworkCallback(callback)
      } catch (_: IllegalArgumentException) {
        // Already unregistered -- fine.
      }
    }
    activeCallback = null
    activeNetwork = null
  }
}
