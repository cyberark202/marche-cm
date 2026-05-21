package com.marchecm.driver

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // FLAG_SECURE: prevents screenshots and screen recording (OWASP MASVS-PLATFORM-1)
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
    }
}
