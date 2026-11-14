package dev.sagron.zerotrustcontacts

import android.Manifest
import android.content.ContentUris
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.Rect
import android.provider.ContactsContract
import androidx.core.content.ContextCompat

/** Address book photos and initials for the contact widgets. */
object ContactWidgetPhotos {
    fun canRead(context: Context): Boolean =
        ContextCompat.checkSelfPermission(context, Manifest.permission.READ_CONTACTS) ==
            PackageManager.PERMISSION_GRANTED

    /**
     * The contact's photo cut to a circle of at most [maxPx] pixels; null when
     * there is none or no permission. [highRes] reads the full photo (single
     * contact widget); the grid uses the small thumbnail to keep every tile
     * within the widget's memory budget.
     */
    fun circlePhoto(context: Context, contactId: Long, maxPx: Int, highRes: Boolean = false): Bitmap? {
        if (!canRead(context)) return null
        return try {
            val uri = ContentUris.withAppendedId(ContactsContract.Contacts.CONTENT_URI, contactId)
            ContactsContract.Contacts.openContactPhotoInputStream(context.contentResolver, uri, highRes)
                ?.use { BitmapFactory.decodeStream(it) }
                ?.let { circle(it, maxPx) }
        } catch (e: Exception) {
            null
        }
    }

    fun circle(source: Bitmap, maxPx: Int): Bitmap {
        val size = minOf(source.width, source.height, maxPx)
        val out = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(out)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        canvas.drawOval(0f, 0f, size.toFloat(), size.toFloat(), paint)
        paint.xfermode = PorterDuffXfermode(PorterDuff.Mode.SRC_IN)
        val side = minOf(source.width, source.height)
        val src = Rect(
            (source.width - side) / 2,
            (source.height - side) / 2,
            (source.width + side) / 2,
            (source.height + side) / 2,
        )
        canvas.drawBitmap(source, src, Rect(0, 0, size, size), paint)
        return out
    }

    /** "Dana Levi" -> "DL"; one name -> its first letter. */
    fun initials(name: String): String {
        val parts = name.trim().split(Regex("\\s+")).filter { it.isNotEmpty() }
        val letters = when {
            parts.isEmpty() -> "?"
            parts.size == 1 -> parts[0].take(1)
            else -> parts.first().take(1) + parts.last().take(1)
        }
        return letters.uppercase()
    }

    fun firstName(name: String): String =
        name.trim().split(Regex("\\s+")).firstOrNull()?.ifEmpty { null } ?: name

    /** The contact's default number, else its first one; null when it has none. */
    fun primaryPhone(context: Context, contactId: Long): String? {
        if (!canRead(context)) return null
        return try {
            context.contentResolver.query(
                ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
                arrayOf(ContactsContract.CommonDataKinds.Phone.NUMBER),
                "${ContactsContract.CommonDataKinds.Phone.CONTACT_ID} = ?",
                arrayOf(contactId.toString()),
                "${ContactsContract.CommonDataKinds.Phone.IS_SUPER_PRIMARY} DESC, " +
                    "${ContactsContract.CommonDataKinds.Phone.IS_PRIMARY} DESC",
            )?.use { cursor ->
                while (cursor.moveToNext()) {
                    val number = cursor.getString(0)?.trim()
                    if (!number.isNullOrEmpty()) return@use number
                }
                null
            }
        } catch (e: Exception) {
            null
        }
    }
}
