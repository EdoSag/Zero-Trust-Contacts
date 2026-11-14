package dev.sagron.zerotrustcontacts

import android.app.Activity
import android.app.AlertDialog
import android.appwidget.AppWidgetManager
import android.content.Intent
import android.content.res.Configuration
import android.os.Bundle

/**
 * Picks what a tap on a Favourites widget does (W7): call, or send a
 * message. Shown when the widget is placed and from the launcher's widget
 * settings. Asks for the contacts permission first if the app doesn't have it.
 */
class FavoritesWidgetConfigureActivity : Activity() {
    private var widgetId = AppWidgetManager.INVALID_APPWIDGET_ID
    private val requestReadContacts = 3101

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setResult(RESULT_CANCELED)
        widgetId = intent?.extras?.getInt(AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID)
            ?: AppWidgetManager.INVALID_APPWIDGET_ID
        if (widgetId == AppWidgetManager.INVALID_APPWIDGET_ID) {
            finish()
            return
        }
        if (!ContactWidgetPhotos.canRead(this)) {
            requestPermissions(arrayOf(android.Manifest.permission.READ_CONTACTS), requestReadContacts)
            return
        }
        ask()
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        // Without it the widget says so and opens the app; still placed.
        if (requestCode == requestReadContacts) ask()
    }

    private fun ask() {
        val modes = arrayOf(ContactActionActivity.ACTION_CALL, ContactActionActivity.ACTION_MESSAGE)
        val labels = arrayOf(getString(R.string.fw_mode_call), getString(R.string.fw_mode_message))
        val current = modes.indexOf(FavoritesWidgetProvider.mode(this, widgetId)).coerceAtLeast(0)
        val night = (resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) ==
            Configuration.UI_MODE_NIGHT_YES
        AlertDialog.Builder(
            this,
            if (night) android.R.style.Theme_DeviceDefault_Dialog_Alert else android.R.style.Theme_DeviceDefault_Light_Dialog_Alert,
        )
            .setTitle(R.string.fw_mode_title)
            .setSingleChoiceItems(labels, current) { dialog, which ->
                dialog.dismiss()
                FavoritesWidgetProvider.saveMode(this, widgetId, modes[which])
                FavoritesWidgetProvider.update(this, AppWidgetManager.getInstance(this), widgetId)
                FavoritesRefreshJob.schedule(this)
                setResult(RESULT_OK, Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId))
                finish()
            }
            .setNegativeButton(android.R.string.cancel) { dialog, _ -> dialog.cancel() }
            .setOnCancelListener { finish() }
            .show()
    }
}
