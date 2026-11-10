package dev.sagron.zerotrustcontacts

import android.Manifest
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.Rect
import android.net.Uri
import android.os.Bundle
import android.provider.ContactsContract
import android.view.View
import android.widget.RemoteViews
import androidx.core.content.ContextCompat

data class ContactWidgetConfig(
    val contactId: Long,
    val contactName: String,
    val phoneNumber: String?,
    val lookupUri: String?,
    val actionMode: String,
)

class ContactQuickWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        appWidgetIds.forEach { appWidgetId ->
            updateAppWidget(context, appWidgetManager, appWidgetId)
        }
    }

    /** Resized: one cell shows photo over name, wider shows them side by side. */
    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        updateAppWidget(context, appWidgetManager, appWidgetId)
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        appWidgetIds.forEach { appWidgetId ->
            deleteConfiguration(context, appWidgetId)
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action != ACTION_WIDGET_TAP) {
            return
        }
        val appWidgetId = intent.getIntExtra(
            AppWidgetManager.EXTRA_APPWIDGET_ID,
            AppWidgetManager.INVALID_APPWIDGET_ID,
        )
        if (appWidgetId == AppWidgetManager.INVALID_APPWIDGET_ID) {
            return
        }
        handleWidgetTap(context, appWidgetId)
    }

    companion object {
        const val ACTION_MODE_CALL = "call"
        const val ACTION_MODE_DETAILS = "details"

        private const val PREFS_NAME = "contact_quick_widget_prefs"
        private const val KEY_CONTACT_ID_PREFIX = "contact_id_"
        private const val KEY_CONTACT_NAME_PREFIX = "contact_name_"
        private const val KEY_PHONE_PREFIX = "phone_"
        private const val KEY_LOOKUP_URI_PREFIX = "lookup_uri_"
        private const val KEY_MODE_PREFIX = "mode_"
        private const val ACTION_WIDGET_TAP =
            "dev.sagron.zerotrustcontacts.action.CONTACT_WIDGET_TAP"

        fun saveConfiguration(
            context: Context,
            appWidgetId: Int,
            contactId: Long,
            contactName: String,
            phoneNumber: String?,
            lookupUri: String?,
            actionMode: String,
        ) {
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .edit()
                .putLong(KEY_CONTACT_ID_PREFIX + appWidgetId, contactId)
                .putString(KEY_CONTACT_NAME_PREFIX + appWidgetId, contactName)
                .putString(KEY_PHONE_PREFIX + appWidgetId, phoneNumber ?: "")
                .putString(KEY_LOOKUP_URI_PREFIX + appWidgetId, lookupUri ?: "")
                .putString(KEY_MODE_PREFIX + appWidgetId, actionMode)
                .apply()
        }

        fun loadConfiguration(context: Context, appWidgetId: Int): ContactWidgetConfig? {
            val preferences = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val contactName = preferences.getString(KEY_CONTACT_NAME_PREFIX + appWidgetId, null)
                ?: return null
            val contactId = preferences.getLong(KEY_CONTACT_ID_PREFIX + appWidgetId, -1L)
            if (contactId <= 0L) {
                return null
            }
            val phone = preferences.getString(KEY_PHONE_PREFIX + appWidgetId, "")?.trim()
            val lookupUri = preferences.getString(KEY_LOOKUP_URI_PREFIX + appWidgetId, "")?.trim()
            val mode = preferences.getString(KEY_MODE_PREFIX + appWidgetId, ACTION_MODE_DETAILS)
                ?: ACTION_MODE_DETAILS
            return ContactWidgetConfig(
                contactId = contactId,
                contactName = contactName,
                phoneNumber = phone?.ifEmpty { null },
                lookupUri = lookupUri?.ifEmpty { null },
                actionMode = mode,
            )
        }

        fun deleteConfiguration(context: Context, appWidgetId: Int) {
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .edit()
                .remove(KEY_CONTACT_ID_PREFIX + appWidgetId)
                .remove(KEY_CONTACT_NAME_PREFIX + appWidgetId)
                .remove(KEY_PHONE_PREFIX + appWidgetId)
                .remove(KEY_LOOKUP_URI_PREFIX + appWidgetId)
                .remove(KEY_MODE_PREFIX + appWidgetId)
                .apply()
        }

        /** From about two cells wide, the name sits beside the photo. */
        private const val WIDE_MIN_WIDTH_DP = 140

        fun updateAppWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int,
        ) {
            val configuration = loadConfiguration(context, appWidgetId)
            val width = appWidgetManager.getAppWidgetOptions(appWidgetId)
                .getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 0)
            val wide = width >= WIDE_MIN_WIDTH_DP
            val views = RemoteViews(
                context.packageName,
                if (wide) R.layout.contact_quick_widget_wide else R.layout.contact_quick_widget,
            )
            if (configuration == null) {
                views.setTextViewText(R.id.widget_label, "Choose contact")
                if (wide) views.setTextViewText(R.id.widget_caption, "Tap to pick someone")
                views.setTextViewText(R.id.widget_initials, "+")
                views.setViewVisibility(R.id.widget_photo, View.GONE)
                views.setViewVisibility(R.id.widget_icon, View.GONE)
                val configureIntent = Intent(context, ContactWidgetConfigureActivity::class.java)
                    .putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
                val configurePendingIntent = PendingIntent.getActivity(
                    context,
                    appWidgetId,
                    configureIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                )
                views.setOnClickPendingIntent(R.id.widget_root, configurePendingIntent)
            } else {
                val calls = configuration.actionMode == ACTION_MODE_CALL
                views.setTextViewText(
                    R.id.widget_label,
                    if (wide) configuration.contactName else firstName(configuration.contactName),
                )
                if (wide) views.setTextViewText(R.id.widget_caption, if (calls) "Tap to call" else "Tap to open")
                views.setTextViewText(R.id.widget_initials, initials(configuration.contactName))
                val photo = loadPhoto(context, configuration)
                if (photo != null) {
                    views.setImageViewBitmap(R.id.widget_photo, photo)
                    views.setViewVisibility(R.id.widget_photo, View.VISIBLE)
                } else {
                    views.setViewVisibility(R.id.widget_photo, View.GONE)
                }
                views.setViewVisibility(R.id.widget_icon, if (calls) View.VISIBLE else View.GONE)
                val tapIntent = Intent(context, ContactQuickWidgetProvider::class.java)
                    .setAction(ACTION_WIDGET_TAP)
                    .putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
                val tapPendingIntent = PendingIntent.getBroadcast(
                    context,
                    appWidgetId,
                    tapIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                )
                views.setOnClickPendingIntent(R.id.widget_root, tapPendingIntent)
            }

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }

        private fun firstName(name: String): String =
            name.trim().split(Regex("\\s+")).firstOrNull()?.ifEmpty { null } ?: name

        /** "Dana Levi" -> "DL"; one name -> its first letter. */
        internal fun initials(name: String): String {
            val parts = name.trim().split(Regex("\\s+")).filter { it.isNotEmpty() }
            val letters = when {
                parts.isEmpty() -> "?"
                parts.size == 1 -> parts[0].take(1)
                else -> parts.first().take(1) + parts.last().take(1)
            }
            return letters.uppercase()
        }

        /** The address book photo, cut to a circle; null when there is none or no permission. */
        private fun loadPhoto(context: Context, configuration: ContactWidgetConfig): Bitmap? {
            if (ContextCompat.checkSelfPermission(context, Manifest.permission.READ_CONTACTS) !=
                PackageManager.PERMISSION_GRANTED
            ) {
                return null
            }
            return try {
                val uri = android.content.ContentUris.withAppendedId(
                    ContactsContract.Contacts.CONTENT_URI,
                    configuration.contactId,
                )
                ContactsContract.Contacts.openContactPhotoInputStream(context.contentResolver, uri, false)
                    ?.use { BitmapFactory.decodeStream(it) }
                    ?.let { circle(it) }
            } catch (e: Exception) {
                null
            }
        }

        private fun circle(source: Bitmap): Bitmap {
            val size = minOf(source.width, source.height, 192)
            val out = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(out)
            val paint = Paint(Paint.ANTI_ALIAS_FLAG)
            canvas.drawOval(0f, 0f, size.toFloat(), size.toFloat(), paint)
            paint.xfermode = PorterDuffXfermode(PorterDuff.Mode.SRC_IN)
            val side = minOf(source.width, source.height)
            val src = Rect((source.width - side) / 2, (source.height - side) / 2, (source.width + side) / 2, (source.height + side) / 2)
            canvas.drawBitmap(source, src, Rect(0, 0, size, size), paint)
            return out
        }

        fun updateAllWidgets(context: Context) {
            val appWidgetManager = AppWidgetManager.getInstance(context)
            val provider = ComponentName(context, ContactQuickWidgetProvider::class.java)
            val widgetIds = appWidgetManager.getAppWidgetIds(provider)
            widgetIds.forEach { widgetId ->
                updateAppWidget(context, appWidgetManager, widgetId)
            }
        }

        private fun handleWidgetTap(context: Context, appWidgetId: Int) {
            val configuration = loadConfiguration(context, appWidgetId)
            if (configuration == null) {
                val configureIntent = Intent(context, ContactWidgetConfigureActivity::class.java)
                    .putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                context.startActivity(configureIntent)
                return
            }

            if (configuration.actionMode == ACTION_MODE_CALL) {
                launchCall(context, configuration)
            } else {
                launchContactDetails(context, configuration)
            }
        }

        private fun launchCall(context: Context, configuration: ContactWidgetConfig) {
            val normalizedPhone = configuration.phoneNumber?.trim().orEmpty()
            if (normalizedPhone.isEmpty()) {
                launchContactDetails(context, configuration)
                return
            }

            val phoneUri = Uri.parse("tel:${Uri.encode(normalizedPhone)}")
            val hasCallPermission = ContextCompat.checkSelfPermission(
                context,
                Manifest.permission.CALL_PHONE,
            ) == PackageManager.PERMISSION_GRANTED
            val intent = Intent(
                if (hasCallPermission) Intent.ACTION_CALL else Intent.ACTION_DIAL,
                phoneUri,
            ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(intent)
        }

        private fun launchContactDetails(context: Context, configuration: ContactWidgetConfig) {
            val lookupUri = configuration.lookupUri?.let { Uri.parse(it) }
            val intent = Intent(Intent.ACTION_VIEW).apply {
                data = lookupUri ?: ContactsContract.Contacts.CONTENT_URI
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
        }
    }
}
