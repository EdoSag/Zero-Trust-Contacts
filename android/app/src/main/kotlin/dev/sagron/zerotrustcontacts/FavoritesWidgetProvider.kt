package dev.sagron.zerotrustcontacts

import android.app.ActivityOptions
import android.app.PendingIntent
import android.app.job.JobInfo
import android.app.job.JobParameters
import android.app.job.JobScheduler
import android.app.job.JobService
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.provider.ContactsContract
import android.view.View
import android.widget.RemoteViews
import androidx.core.widget.RemoteViewsCompat

/**
 * Favourites (W7): the address book's starred contacts as a grid of photos
 * (or initials) and first names. Tapping one calls, or sends a message,
 * whichever was picked when the widget was placed
 * (FavoritesWidgetConfigureActivity). The grid scrolls and gets more columns
 * as the widget grows.
 *
 * Reads only the phone's address book (the same data any dialer shows), never
 * the vault, so like the single contact widget it needs no privacy switch.
 * Favourites starred in ZT Contacts reach it through the phone account.
 * A content-triggered job redraws it when the address book changes.
 */
class FavoritesWidgetProvider : AppWidgetProvider() {

    companion object {
        private const val PREFS = "contact_quick_widget_prefs"
        private const val MAX_FAVORITES = 24

        // Thumbnails stay small: every tile travels to the launcher at once.
        private const val PHOTO_PX = 72

        fun modeKey(widgetId: Int) = "favorites_mode_$widgetId"

        fun mode(context: Context, widgetId: Int): String =
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .getString(modeKey(widgetId), ContactActionActivity.ACTION_CALL) ?: ContactActionActivity.ACTION_CALL

        fun saveMode(context: Context, widgetId: Int, mode: String) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString(modeKey(widgetId), mode).apply()
        }

        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            manager.getAppWidgetIds(ComponentName(context, FavoritesWidgetProvider::class.java))
                .forEach { update(context, manager, it) }
        }

        /**
         * Called when the app comes to the front: once contacts may be read
         * (also when allowed in system settings), placed widgets drop the
         * permission message and start following address book changes.
         */
        fun refreshIfPlaced(context: Context) {
            val ids = AppWidgetManager.getInstance(context)
                .getAppWidgetIds(ComponentName(context, FavoritesWidgetProvider::class.java))
            if (ids.isEmpty() || !ContactWidgetPhotos.canRead(context)) return
            FavoritesRefreshJob.schedule(context)
            updateAll(context)
        }

        private data class Favorite(val id: Long, val name: String, val lookupUri: String?)

        private fun favorites(context: Context): List<Favorite> {
            if (!ContactWidgetPhotos.canRead(context)) return emptyList()
            return try {
                context.contentResolver.query(
                    ContactsContract.Contacts.CONTENT_URI,
                    arrayOf(
                        ContactsContract.Contacts._ID,
                        ContactsContract.Contacts.LOOKUP_KEY,
                        ContactsContract.Contacts.DISPLAY_NAME_PRIMARY,
                    ),
                    "${ContactsContract.Contacts.STARRED} = 1",
                    null,
                    "${ContactsContract.Contacts.DISPLAY_NAME_PRIMARY} COLLATE NOCASE ASC",
                )?.use { cursor ->
                    val out = mutableListOf<Favorite>()
                    while (cursor.moveToNext() && out.size < MAX_FAVORITES) {
                        val id = cursor.getLong(0)
                        val lookup = cursor.getString(1)
                        out.add(
                            Favorite(
                                id = id,
                                name = cursor.getString(2)?.trim().orEmpty(),
                                lookupUri = lookup?.let { ContactsContract.Contacts.getLookupUri(id, it)?.toString() },
                            ),
                        )
                    }
                    out
                } ?: emptyList()
            } catch (e: Exception) {
                emptyList()
            }
        }

        fun update(context: Context, manager: AppWidgetManager, widgetId: Int) {
            val views = RemoteViews(context.packageName, R.layout.favorites_widget)
            val mode = mode(context, widgetId)
            val canRead = ContactWidgetPhotos.canRead(context)
            val openApp = PendingIntent.getActivity(
                context,
                widgetId,
                Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            views.setOnClickPendingIntent(R.id.favorites_header, openApp)
            views.setTextViewText(
                R.id.favorites_caption,
                context.getString(if (mode == ContactActionActivity.ACTION_MESSAGE) R.string.fw_tap_message else R.string.fw_tap_call),
            )
            views.setEmptyView(R.id.favorites_grid, R.id.favorites_empty)
            views.setTextViewText(
                R.id.favorites_empty,
                context.getString(if (canRead) R.string.fw_empty else R.string.fw_permission),
            )
            views.setOnClickPendingIntent(R.id.favorites_empty, openApp)
            views.setPendingIntentTemplate(R.id.favorites_grid, tapTemplate(context, widgetId))

            val items = RemoteViewsCompat.RemoteCollectionItems.Builder()
                .setHasStableIds(true)
                .setViewTypeCount(1)
            for (favorite in favorites(context)) {
                val tile = RemoteViews(context.packageName, R.layout.favorites_widget_tile)
                val name = favorite.name.ifEmpty { "?" }
                tile.setTextViewText(R.id.fav_name, ContactWidgetPhotos.firstName(name))
                tile.setTextViewText(R.id.fav_initials, ContactWidgetPhotos.initials(name))
                val photo = ContactWidgetPhotos.circlePhoto(context, favorite.id, PHOTO_PX)
                if (photo != null) {
                    tile.setImageViewBitmap(R.id.fav_photo, photo)
                    tile.setViewVisibility(R.id.fav_photo, View.VISIBLE)
                } else {
                    tile.setViewVisibility(R.id.fav_photo, View.GONE)
                }
                val phone = ContactWidgetPhotos.primaryPhone(context, favorite.id)
                tile.setContentDescription(
                    R.id.fav_tile,
                    context.getString(
                        when {
                            phone == null -> R.string.fw_open_named
                            mode == ContactActionActivity.ACTION_MESSAGE -> R.string.fw_message_named
                            else -> R.string.fw_call_named
                        },
                        name,
                    ),
                )
                tile.setOnClickFillInIntent(
                    R.id.fav_tile,
                    Intent()
                        .putExtra(ContactActionActivity.EXTRA_ACTION, if (phone == null) ContactActionActivity.ACTION_OPEN else mode)
                        .putExtra(ContactActionActivity.EXTRA_PHONE, phone)
                        .putExtra(ContactActionActivity.EXTRA_CONTACT_ID, favorite.id)
                        .putExtra(ContactActionActivity.EXTRA_LOOKUP, favorite.lookupUri),
                )
                items.addItem(favorite.id, tile)
            }
            RemoteViewsCompat.setRemoteAdapter(context, views, widgetId, R.id.favorites_grid, items.build())
            manager.updateAppWidget(widgetId, views)
        }

        /** One template per widget; each tile fills in its contact. Explicit, so safe as mutable. */
        private fun tapTemplate(context: Context, widgetId: Int): PendingIntent {
            val intent = Intent(context, ContactActionActivity::class.java)
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
            if (Build.VERSION.SDK_INT < 34) return PendingIntent.getActivity(context, widgetId, intent, flags)
            val options = ActivityOptions.makeBasic()
            if (Build.VERSION.SDK_INT >= 35) {
                options.setPendingIntentCreatorBackgroundActivityStartMode(
                    ActivityOptions.MODE_BACKGROUND_ACTIVITY_START_ALLOWED,
                )
            } else {
                @Suppress("DEPRECATION")
                options.pendingIntentBackgroundActivityStartMode =
                    ActivityOptions.MODE_BACKGROUND_ACTIVITY_START_ALLOWED
            }
            return PendingIntent.getActivity(context, widgetId, intent, flags, options.toBundle())
        }
    }

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        appWidgetIds.forEach { update(context, appWidgetManager, it) }
        FavoritesRefreshJob.schedule(context)
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        update(context, appWidgetManager, appWidgetId)
    }

    override fun onEnabled(context: Context) {
        FavoritesRefreshJob.schedule(context)
    }

    override fun onDisabled(context: Context) {
        FavoritesRefreshJob.cancel(context)
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        val editor = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
        appWidgetIds.forEach { editor.remove(modeKey(it)) }
        editor.apply()
    }
}

/**
 * Redraws the Favourites widgets when the address book changes (a contact
 * starred, renamed, given a photo). A content-triggered job runs once per
 * change, so it schedules itself again each time.
 */
class FavoritesRefreshJob : JobService() {
    companion object {
        private const val JOB_ID = 4107

        fun schedule(context: Context) {
            val scheduler = context.getSystemService(JobScheduler::class.java) ?: return
            if (!ContactWidgetPhotos.canRead(context)) return
            val job = JobInfo.Builder(JOB_ID, ComponentName(context, FavoritesRefreshJob::class.java))
                .addTriggerContentUri(
                    JobInfo.TriggerContentUri(
                        ContactsContract.Contacts.CONTENT_URI,
                        JobInfo.TriggerContentUri.FLAG_NOTIFY_FOR_DESCENDANTS,
                    ),
                )
                .setTriggerContentUpdateDelay(2_000)
                .setTriggerContentMaxDelay(30_000)
                .build()
            try {
                scheduler.schedule(job)
            } catch (e: Exception) {
                // Too many jobs or not allowed: the widget refreshes on its next update.
            }
        }

        fun cancel(context: Context) {
            context.getSystemService(JobScheduler::class.java)?.cancel(JOB_ID)
        }
    }

    override fun onStartJob(params: JobParameters?): Boolean {
        FavoritesWidgetProvider.updateAll(this)
        val manager = AppWidgetManager.getInstance(this)
        if (manager.getAppWidgetIds(ComponentName(this, FavoritesWidgetProvider::class.java)).isNotEmpty()) {
            schedule(this)
        }
        return false
    }

    override fun onStopJob(params: JobParameters?): Boolean = false
}
