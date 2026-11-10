package dev.sagron.zerotrustcontacts

import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.ContactsContract
import android.provider.ContactsContract.CommonDataKinds
import android.provider.OpenableColumns
import java.io.ByteArrayOutputStream

/**
 * Things other apps hand to ZT Contacts:
 *
 *  - a vCard (.vcf) file opened with or shared to the app, and
 *  - "add a contact" requests (the dialer's "Create new contact", a
 *    messaging app's "Add to contacts", a scanned business card).
 *
 * Each is turned into a plain map for the Flutter side, which waits until
 * the vault is unlocked and then shows it to the user before anything is
 * saved.
 */
object IncomingIntents {
    private const val MAX_VCARD_BYTES = 25 * 1024 * 1024
    private const val HANDLED = "dev.sagron.zerotrustcontacts.HANDLED"
    private val vCardTypes = setOf("text/x-vcard", "text/vcard", "text/directory")

    /** Null when [intent] is not one of these (or was already taken). */
    fun read(context: Context, intent: Intent?): Map<String, Any?>? {
        if (intent == null || intent.getBooleanExtra(HANDLED, false)) return null
        val incoming: Map<String, Any?>? = when (intent.action) {
            Intent.ACTION_INSERT, Intent.ACTION_INSERT_OR_EDIT -> readInsert(intent)
            Intent.ACTION_VIEW -> {
                val uri = intent.data
                if (uri != null && isVCard(context, intent, uri)) readVCard(context, uri) else null
            }
            Intent.ACTION_SEND -> {
                val stream = streamOf(intent)
                val text = intent.getStringExtra(Intent.EXTRA_TEXT)
                when {
                    stream != null -> readVCard(context, stream)
                    text != null && text.contains("BEGIN:VCARD", ignoreCase = true) -> mapOf(
                        "kind" to "vcard",
                        "bytes" to text.toByteArray(Charsets.UTF_8),
                        "name" to "Shared contact",
                    )
                    else -> null
                }
            }
            else -> null
        }
        // So the same file isn't offered again if the screen is rebuilt.
        if (incoming != null) intent.putExtra(HANDLED, true)
        return incoming
    }

    @Suppress("DEPRECATION")
    private fun streamOf(intent: Intent): Uri? =
        intent.getParcelableExtra(Intent.EXTRA_STREAM) as? Uri

    private fun isVCard(context: Context, intent: Intent, uri: Uri): Boolean {
        var type: String? = intent.type
        if (type == null) {
            type = try {
                context.contentResolver.getType(uri)
            } catch (error: Exception) {
                null
            }
        }
        if (type != null && type.lowercase() in vCardTypes) return true
        return uri.lastPathSegment?.lowercase()?.endsWith(".vcf") == true
    }

    private fun readVCard(context: Context, uri: Uri): Map<String, Any?>? {
        val out = ByteArrayOutputStream()
        try {
            val input = context.contentResolver.openInputStream(uri) ?: return null
            input.use { stream ->
                val buffer = ByteArray(64 * 1024)
                while (true) {
                    val read = stream.read(buffer)
                    if (read < 0) break
                    out.write(buffer, 0, read)
                    if (out.size() > MAX_VCARD_BYTES) return null
                }
            }
        } catch (error: Exception) {
            return null
        }
        val bytes: ByteArray = out.toByteArray()
        return mapOf("kind" to "vcard", "bytes" to bytes, "name" to fileName(context, uri))
    }

    private fun fileName(context: Context, uri: Uri): String {
        try {
            context.contentResolver.query(
                uri,
                arrayOf(OpenableColumns.DISPLAY_NAME),
                null,
                null,
                null,
            )?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val name = cursor.getString(0)
                    if (!name.isNullOrBlank()) return name
                }
            }
        } catch (error: Exception) {
            // Some providers don't answer; fall back to the path.
        }
        return uri.lastPathSegment?.substringAfterLast('/')?.takeIf { it.isNotBlank() }
            ?: "contacts.vcf"
    }

    /** The details another app filled in for a new contact. */
    private fun readInsert(intent: Intent): Map<String, Any?> {
        val extras = intent.extras

        @Suppress("DEPRECATION")
        fun value(key: String): Any? = extras?.get(key)
        fun text(key: String): String =
            value(key)?.toString()?.trim().orEmpty()

        val phones = ArrayList<Map<String, String>>()
        val emails = ArrayList<Map<String, String>>()
        val addresses = ArrayList<Map<String, String>>()
        val other = ArrayList<String>()
        val birthdays = ArrayList<String>()
        var displayName = text(ContactsContract.Intents.Insert.NAME)
        var firstName = ""
        var lastName = ""
        var company = text(ContactsContract.Intents.Insert.COMPANY)
        var notes = text(ContactsContract.Intents.Insert.NOTES)

        fun add(list: ArrayList<Map<String, String>>, entry: String, type: String) {
            if (entry.isNotEmpty() && list.none { it["value"] == entry }) {
                list.add(mapOf("value" to entry, "type" to type))
            }
        }

        fun typeCode(key: String): Int? = when (val raw = value(key)) {
            is Number -> raw.toInt()
            is String -> raw.toIntOrNull()
            else -> null
        }

        for ((numberKey, typeKey) in listOf(
            ContactsContract.Intents.Insert.PHONE to ContactsContract.Intents.Insert.PHONE_TYPE,
            ContactsContract.Intents.Insert.SECONDARY_PHONE to
                ContactsContract.Intents.Insert.SECONDARY_PHONE_TYPE,
            ContactsContract.Intents.Insert.TERTIARY_PHONE to
                ContactsContract.Intents.Insert.TERTIARY_PHONE_TYPE,
        )) {
            add(phones, text(numberKey), phoneType(typeCode(typeKey)))
        }
        for ((addressKey, typeKey) in listOf(
            ContactsContract.Intents.Insert.EMAIL to ContactsContract.Intents.Insert.EMAIL_TYPE,
            ContactsContract.Intents.Insert.SECONDARY_EMAIL to
                ContactsContract.Intents.Insert.SECONDARY_EMAIL_TYPE,
            ContactsContract.Intents.Insert.TERTIARY_EMAIL to
                ContactsContract.Intents.Insert.TERTIARY_EMAIL_TYPE,
        )) {
            add(emails, text(addressKey), homeWorkOther(typeCode(typeKey)))
        }
        add(
            addresses,
            text(ContactsContract.Intents.Insert.POSTAL),
            homeWorkOther(typeCode(ContactsContract.Intents.Insert.POSTAL_TYPE)),
        )

        // Newer apps pass full rows instead of (or as well as) the extras.
        @Suppress("DEPRECATION")
        val rows = try {
            intent.getParcelableArrayListExtra<ContentValues>(ContactsContract.Intents.Insert.DATA)
        } catch (error: Exception) {
            null
        }
        for (row in rows.orEmpty()) {
            val data1 = row.getAsString(ContactsContract.Data.DATA1)?.trim().orEmpty()
            val type = row.getAsInteger(ContactsContract.Data.DATA2)
            when (row.getAsString(ContactsContract.Data.MIMETYPE)) {
                CommonDataKinds.StructuredName.CONTENT_ITEM_TYPE -> {
                    if (displayName.isEmpty()) displayName = data1
                    firstName = row.getAsString(ContactsContract.Data.DATA2)?.trim().orEmpty()
                    lastName = row.getAsString(ContactsContract.Data.DATA3)?.trim().orEmpty()
                }
                CommonDataKinds.Phone.CONTENT_ITEM_TYPE -> add(phones, data1, phoneType(type))
                CommonDataKinds.Email.CONTENT_ITEM_TYPE -> add(emails, data1, homeWorkOther(type))
                CommonDataKinds.StructuredPostal.CONTENT_ITEM_TYPE ->
                    add(addresses, data1, homeWorkOther(type))
                CommonDataKinds.Organization.CONTENT_ITEM_TYPE ->
                    if (company.isEmpty()) company = data1
                CommonDataKinds.Note.CONTENT_ITEM_TYPE -> if (notes.isEmpty()) notes = data1
                CommonDataKinds.Website.CONTENT_ITEM_TYPE ->
                    if (data1.isNotEmpty()) other.add(data1)
                CommonDataKinds.Event.CONTENT_ITEM_TYPE ->
                    if (type == CommonDataKinds.Event.TYPE_BIRTHDAY && data1.isNotEmpty()) {
                        birthdays.add(data1)
                    }
            }
        }

        return mapOf(
            "kind" to "insert",
            // "Add to contacts" may mean an existing contact; "Create new
            // contact" does not.
            "allowExisting" to (intent.action == Intent.ACTION_INSERT_OR_EDIT),
            "displayName" to displayName,
            "firstName" to firstName,
            "lastName" to lastName,
            "company" to company,
            "notes" to notes,
            "phones" to phones,
            "emails" to emails,
            "addresses" to addresses,
            "other" to other,
            "birthdays" to birthdays,
        )
    }

    private fun phoneType(code: Int?): String = when (code) {
        CommonDataKinds.Phone.TYPE_MOBILE, CommonDataKinds.Phone.TYPE_WORK_MOBILE -> "mobile"
        CommonDataKinds.Phone.TYPE_HOME -> "home"
        CommonDataKinds.Phone.TYPE_WORK, CommonDataKinds.Phone.TYPE_COMPANY_MAIN -> "work"
        CommonDataKinds.Phone.TYPE_MAIN -> "main"
        null -> "mobile"
        else -> "other"
    }

    /** Email and postal types share these codes: 1 home, 2 work, 3 other. */
    private fun homeWorkOther(code: Int?): String = when (code) {
        1 -> "home"
        2 -> "work"
        null -> ""
        else -> "other"
    }
}
