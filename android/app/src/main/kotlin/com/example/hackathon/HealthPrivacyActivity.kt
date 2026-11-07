package com.example.hackathon

import android.app.Activity
import android.os.Bundle
import android.widget.TextView

class HealthPrivacyActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(TextView(this).apply {
            text = "Blood pressure data\n\nSentinel reads blood pressure only after you grant permission. " +
                "Choosing Connect and upload in Preferences uploads readings from the last 29 days " +
                "to your signed-in Firebase account. Readings include measurement times and source metadata. " +
                "Refresh runs while the app is active, even after the health editor closes.\n\n" +
                "Stop tracking in Preferences to end collection. Revoke blood pressure access in Health Connect settings. " +
                "Stopping or revoking access does not delete previously uploaded records. " +
                "Use Delete uploaded readings in Preferences to remove cloud records."
            textSize = 18f
            setPadding(32, 48, 32, 32)
        })
    }
}
