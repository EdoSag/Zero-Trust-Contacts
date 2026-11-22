package dev.sagron.zerotrustcontacts

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.widget.RemoteViews
import androidx.core.widget.RemoteViewsCompat
import org.json.JSONObject
import java.time.LocalDate
import java.time.temporal.ChronoUnit

/**
 * Upcoming birthdays (W8): the address book's coming birthdays and
 * anniversaries, soonest first, with "Today", "Tomorrow" or "In 3 days".
 *
 * The vault can't be read while it is locked, so the app leaves a small
 * snapshot here each time it is unlocked ([save]): each occasion's month and
 * day, and the name only when "Show names in the birthdays widget" is on
 * (off by default, like every Zero-Trust widget's details). Redrawn every
 * hour from that snapshot, so the days move on by themselves.
 */
class BirthdaysWidgetProvider : AppWidgetProvider() {

    companion object {
        private const val PREFS = "birthdays_widget"
        private const val KEY = "snapshot"
        private const val MAX_ROWS = 30

        /** Opens the app on its Birthdays page (after unlocking). */
        const val OPEN_BIRTHDAYS = "birthdays"

        fun save(context: Context, json: String) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString(KEY, json).apply()
            updateAll(context)
        }

        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            manager.getAppWidgetIds(ComponentName(context, BirthdaysWidgetProvider::class.java))
                .forEach { update(context, manager, it) }
        }

        private data class Row(
            val name: String?,
            val anniversary: Boolean,
            val days: Long,
            val years: Int?,
        )

        private fun rows(context: Context, today: LocalDate): List<Row> {
            val raw = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY, null)
                ?: return emptyList()
            return try {
                val json = JSONObject(raw)
                val showNames = json.optBoolean("names", false)
                val items = json.optJSONArray("items") ?: return emptyList()
                val out = mutableListOf<Row>()
                for (i in 0 until items.length()) {
                    val item = items.optJSONObject(i) ?: continue
                    val next = nextDate(today, item.optInt("m"), item.optInt("d")) ?: continue
                    val year = if (item.has("y")) item.optInt("y") else null
                    val years = year?.let { next.year - it }?.takeIf { it in 1..149 }
                    out.add(
                        Row(
                            name = if (showNames) item.optString("n").ifBlank { null } else null,
                            anniversary = item.optString("k") == "a",
                            days = ChronoUnit.DAYS.between(today, next),
                            years = years,
                        ),
                    )
                }
                out.sortedBy { it.days }.take(MAX_ROWS)
            } catch (e: Exception) {
                emptyList()
            }
        }

        /** The next [month]/[day] on or after [today]; 29 February is 28 February in other years. */
        private fun nextDate(today: LocalDate, month: Int, day: Int): LocalDate? {
            if (month !in 1..12 || day !in 1..31) return null
            fun inYear(y: Int): LocalDate? = try {
                val leap = java.time.Year.isLeap(y.toLong())
                LocalDate.of(y, month, if (month == 2 && day == 29 && !leap) 28 else day)
            } catch (e: Exception) {
                null
            }
            val thisYear = inYear(today.year) ?: return null
            return if (thisYear.isBefore(today)) inYear(today.year + 1) else thisYear
        }

        private fun openBirthdays(context: Context, widgetId: Int): PendingIntent =
            PendingIntent.getActivity(
                context,
                widgetId,
                Intent(context, MainActivity::class.java)
                    .setAction(Intent.ACTION_VIEW)
                    .putExtra(MainActivity.EXTRA_OPEN, OPEN_BIRTHDAYS)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )

        fun update(context: Context, manager: AppWidgetManager, widgetId: Int) {
            val views = RemoteViews(context.packageName, R.layout.birthdays_widget)
            val open = openBirthdays(context, widgetId)
            views.setOnClickPendingIntent(R.id.birthdays_header, open)
            views.setOnClickPendingIntent(R.id.birthdays_empty, open)
            views.setEmptyView(R.id.birthdays_list, R.id.birthdays_empty)
            // Every row opens the same page: the template needs no fill-in data.
            views.setPendingIntentTemplate(
                R.id.birthdays_list,
                PendingIntent.getActivity(
                    context,
                    widgetId + 100_000,
                    Intent(context, MainActivity::class.java)
                        .setAction(Intent.ACTION_VIEW)
                        .putExtra(MainActivity.EXTRA_OPEN, OPEN_BIRTHDAYS)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE,
                ),
            )

            val items = RemoteViewsCompat.RemoteCollectionItems.Builder()
                .setHasStableIds(true)
                .setViewTypeCount(1)
            rows(context, LocalDate.now()).forEachIndexed { index, row ->
                val view = RemoteViews(context.packageName, R.layout.birthdays_widget_row)
                view.setTextViewText(R.id.bw_icon, if (row.anniversary) "💍" else "🎂")
                val kind = context.getString(if (row.anniversary) R.string.bw_anniversary else R.string.bw_birthday)
                view.setTextViewText(
                    R.id.bw_name,
                    row.name ?: context.getString(
                        if (row.anniversary) R.string.bw_hidden_anniversary else R.string.bw_hidden_birthday,
                    ),
                )
                val what = when {
                    row.name == null -> ""
                    row.years == null -> kind
                    row.anniversary -> context.getString(R.string.bw_years_married, row.years)
                    else -> context.getString(R.string.bw_turns, row.years)
                }
                view.setTextViewText(R.id.bw_what, what)
                view.setViewVisibility(R.id.bw_what, if (what.isEmpty()) android.view.View.GONE else android.view.View.VISIBLE)
                view.setTextViewText(
                    R.id.bw_when,
                    when (row.days) {
                        0L -> context.getString(R.string.bw_today)
                        1L -> context.getString(R.string.bw_tomorrow)
                        else -> context.getString(R.string.bw_in_days, row.days.toInt())
                    },
                )
                view.setOnClickFillInIntent(R.id.bw_row, Intent())
                items.addItem(index.toLong(), view)
            }
            RemoteViewsCompat.setRemoteAdapter(context, views, widgetId, R.id.birthdays_list, items.build())
            manager.updateAppWidget(widgetId, views)
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        // A new time zone or a clock change can move "Today".
        if (intent.action == Intent.ACTION_TIMEZONE_CHANGED || intent.action == Intent.ACTION_TIME_CHANGED) {
            updateAll(context)
        }
    }

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        appWidgetIds.forEach { update(context, appWidgetManager, it) }
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        update(context, appWidgetManager, appWidgetId)
    }
}
