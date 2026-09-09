package dev.lennelis.funkin_editors

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private lateinit var saf: SafBridge

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        saf = SafBridge(applicationContext)
        saf.activity = this

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler(saf)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        // The folder picker's result comes back here. Anything else is a
        // plugin's, so it still has to reach super.
        if (::saf.isInitialized && saf.onActivityResult(requestCode, resultCode, data)) return
        super.onActivityResult(requestCode, resultCode, data)
    }

    companion object {
        private const val CHANNEL = "dev.lennelis.funkin/saf"
    }
}
