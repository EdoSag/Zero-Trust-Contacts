package dev.sagron.zerotrustcontacts

import android.Manifest
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
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

        /**
         * From about 2x2 (W7): big photo, name, number, Call and Message
         * buttons. They need about 185dp at the default font size, so the
         * large layout starts a little above that.
         */
        private const val LARGE_MIN_WIDTH_DP = 110
        private const val LARGE_MIN_HEIGHT_DP = 190

        /**
         * Below this height there is only room for the round photo (44dp plus
         * padding), so the name is hidden and the initials identify the contact.
         */
        private const val LABEL_MIN_HEIGHT_DP = 64

        fun updateAppWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int,
        ) {
            val configuration = loadConfiguration(context, appWidgetId)
            val options = appWidgetManager.getAppWidgetOptions(appWidgetId)
            val width = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 0)
            val height = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, 0)
            // 0 means the launcher has not reported a size yet: assume it fits.
            val tall = height == 0 || height >= LABEL_MIN_HEIGHT_DP
            val large = height >= LARGE_MIN_HEIGHT_DP && width >= LARGE_MIN_WIDTH_DP
            val wide = tall && width >= WIDE_MIN_WIDTH_DP && !large
            val views = RemoteViews(
                context.packageName,
                when {
                    large -> R.layout.contact_quick_widget_large
                    wide -> R.layout.contact_quick_widget_wide
                    else -> R.layout.contact_quick_widget
                },
            )
            if (configuration == null) {
                views.setTextViewText(R.id.widget_label, context.getString(R.string.cw_choose))
                if (wide || large) views.setTextViewText(R.id.widget_caption, context.getString(R.string.cw_tap_pick))
                if (large) views.setViewVisibility(R.id.widget_actions, View.GONE)
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
                    if (wide || large) configuration.contactName else firstName(configuration.contactName),
                )
                if (wide) views.setTextViewText(R.id.widget_caption, context.getString(if (calls) R.string.cw_tap_call else R.string.cw_tap_open))
                views.setTextViewText(R.id.widget_initials, initials(configuration.contactName))
                if (large) bindLarge(context, views, appWidgetId, configuration)
                val photo = ContactWidgetPhotos.circlePhoto(
                    context,
                    configuration.contactId,
                    if (large) 256 else 192,
                    highRes = large,
                )
                if (photo != null) {
                    views.setImageViewBitmap(R.id.widget_photo, photo)
                    views.setViewVisibility(R.id.widget_photo, View.VISIBLE)
                } else {
                    views.setViewVisibility(R.id.widget_photo, View.GONE)
                }
                if (!large) views.setViewVisibility(R.id.widget_icon, if (calls) View.VISIBLE else View.GONE)
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

            if (!wide && !large) {
                views.setViewVisibility(R.id.widget_label, if (tall) View.VISIBLE else View.GONE)
            }
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }

        private fun firstName(name: String): String = ContactWidgetPhotos.firstName(name)

        /** "Dana Levi" -> "DL"; one name -> its first letter. */
        internal fun initials(name: String): String = ContactWidgetPhotos.initials(name)

        /** Number under the name, and Call / Message buttons when it has one. */
        private fun bindLarge(
            context: Context,
            views: RemoteViews,
            appWidgetId: Int,
            configuration: ContactWidgetConfig,
        ) {
            val phone = configuration.phoneNumber
                ?: ContactWidgetPhotos.primaryPhone(context, configuration.contactId)
            views.setTextViewText(R.id.widget_caption, phone ?: "")
            views.setViewVisibility(R.id.widget_caption, if (phone == null) View.GONE else View.VISIBLE)
            views.setViewVisibility(R.id.widget_actions, if (phone == null) View.GONE else View.VISIBLE)
            if (phone == null) return
            fun action(action: String, requestCode: Int) = PendingIntent.getActivity(
                context,
                requestCode,
                ContactActionActivity.intent(context, action, phone, configuration.contactId, configuration.lookupUri)
                    .setData(Uri.parse("ztcontacts://widget/$appWidgetId/$action")),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            views.setOnClickPendingIntent(R.id.widget_call, action(ContactActionActivity.ACTION_CALL, appWidgetId * 4 + 1))
            views.setOnClickPendingIntent(R.id.widget_message, action(ContactActionActivity.ACTION_MESSAGE, appWidgetId * 4 + 2))
            views.setContentDescription(R.id.widget_call, context.getString(R.string.fw_call_named, configuration.contactName))
            views.setContentDescription(R.id.widget_message, context.getString(R.string.fw_message_named, configuration.contactName))
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
