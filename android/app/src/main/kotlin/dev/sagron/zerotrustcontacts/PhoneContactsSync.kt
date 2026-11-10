package dev.sagron.zerotrustcontacts

import android.accounts.Account
import android.accounts.AccountManager
import android.app.Activity
import android.content.ContentProviderOperation
import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.provider.ContactsContract
import android.provider.ContactsContract.CommonDataKinds
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Copies chosen fields of vault contacts into the phone's own contacts
 * database, under a "ZT Contacts" account, so the dialer, caller ID and
 * messaging apps can show them. The vault stays the source of truth: the
 * Flutter side decides what to write (and only what the user picked), this
 * side just applies it. Turning it off removes the account, which removes
 * every contact it wrote.
 *
 * Contacts apps may also edit, add and delete contacts in the account.
 * Those changes are marked by Android (DIRTY, DELETED, or no SOURCE_ID for
 * a new one); [changes] reports them so the Flutter side can put them in
 * the vault, and [acknowledge] clears the marks.
 *
 * Each written raw contact keeps the vault contact id in SOURCE_ID and a
 * hash of what was written in SYNC1, so only changed contacts are rewritten.
 */
object PhoneContactsSync {
    const val ACCOUNT_TYPE = "dev.sagron.zerotrustcontacts.account"
    const val ACCOUNT_NAME = "ZT Contacts"

    private val account = Account(ACCOUNT_NAME, ACCOUNT_TYPE)

    /** Handles `phoneSync.*` calls; returns null for any other method. */
    fun handle(activity: Activity, call: MethodCall, result: MethodChannel.Result): Unit? {
        if (!call.method.startsWith("phoneSync.")) return null
        val context = activity.applicationContext
        Thread {
            try {
                val value: Any? = when (call.method) {
                    "phoneSync.state" -> state(context)
                    "phoneSync.apply" -> apply(
                        context,
                        call.argument<List<Map<String, Any?>>>("upserts").orEmpty(),
                        call.argument<List<String>>("deletes").orEmpty(),
                    )
                    "phoneSync.disable" -> disable(context)
                    "phoneSync.changes" -> changes(context)
                    "phoneSync.acknowledge" -> acknowledge(
                        context,
                        call.argument<List<Map<String, Any?>>>("items").orEmpty(),
                    )
                    else -> {
                        activity.runOnUiThread { result.notImplemented() }
                        return@Thread
                    }
                }
                activity.runOnUiThread { result.success(value) }
            } catch (error: SecurityException) {
                activity.runOnUiThread {
                    result.error("permission_denied", "Contacts permission is required.", null)
                }
            } catch (error: Exception) {
                activity.runOnUiThread {
                    result.error("phone_sync_failed", error.localizedMessage, null)
                }
            }
        }.start()
        return Unit
    }

    private fun hasAccount(context: Context): Boolean =
        AccountManager.get(context).getAccountsByType(ACCOUNT_TYPE).isNotEmpty()

    /** Whether the account exists, and what it holds: vault id -> hash. */
    private fun state(context: Context): Map<String, Any> {
        val hashes = mutableMapOf<String, String>()
        if (hasAccount(context)) {
            context.contentResolver.query(
                ContactsContract.RawContacts.CONTENT_URI,
                arrayOf(ContactsContract.RawContacts.SOURCE_ID, ContactsContract.RawContacts.SYNC1),
                "${ContactsContract.RawContacts.ACCOUNT_TYPE} = ? AND " +
                    "${ContactsContract.RawContacts.ACCOUNT_NAME} = ? AND " +
                    "${ContactsContract.RawContacts.DELETED} = 0",
                arrayOf(ACCOUNT_TYPE, ACCOUNT_NAME),
                null,
            )?.use { cursor ->
                while (cursor.moveToNext()) {
                    val id = cursor.getString(0) ?: continue
                    hashes[id] = cursor.getString(1).orEmpty()
                }
            }
        }
        return mapOf("enabled" to hasAccount(context), "hashes" to hashes)
    }

    private fun ensureAccount(context: Context) {
        if (hasAccount(context)) return
        AccountManager.get(context).addAccountExplicitly(account, null, null)
        // Show this account's contacts in contacts apps even though they're
        // in no group.
        context.contentResolver.insert(
            asSyncAdapter(ContactsContract.Settings.CONTENT_URI),
            ContentValues().apply {
                put(ContactsContract.Settings.ACCOUNT_NAME, ACCOUNT_NAME)
                put(ContactsContract.Settings.ACCOUNT_TYPE, ACCOUNT_TYPE)
                put(ContactsContract.Settings.UNGROUPED_VISIBLE, 1)
                put(ContactsContract.Settings.SHOULD_SYNC, 0)
            },
        )
    }

    /** Removes the account and with it every contact it wrote. */
    private fun disable(context: Context): Boolean {
        context.contentResolver.delete(
            asSyncAdapter(ContactsContract.RawContacts.CONTENT_URI),
            "${ContactsContract.RawContacts.ACCOUNT_TYPE} = ?",
            arrayOf(ACCOUNT_TYPE),
        )
        val manager = AccountManager.get(context)
        for (existing in manager.getAccountsByType(ACCOUNT_TYPE)) {
            manager.removeAccountExplicitly(existing)
        }
        return true
    }

    private fun apply(
        context: Context,
        upserts: List<Map<String, Any?>>,
        deletes: List<String>,
    ): Int {
        ensureAccount(context)
        val rawIds = rawIdsBySourceId(context)
        val batch = Batch(context)

        for (sourceId in deletes) {
            val rawId = rawIds[sourceId] ?: continue
            batch.add(
                ContentProviderOperation
                    .newDelete(asSyncAdapter(ContactsContract.RawContacts.CONTENT_URI))
                    .withSelection("${ContactsContract.RawContacts._ID} = ?", arrayOf(rawId.toString()))
                    .build(),
            )
        }
        batch.flush()

        for (entry in upserts) {
            val sourceId = entry["id"] as? String ?: continue
            val photo = entry["photo"] as? ByteArray
            batch.startContact(photo?.size ?: 0)
            val existing = rawIds[sourceId]
            val rawValues = ContentValues().apply {
                put(ContactsContract.RawContacts.SYNC1, entry["hash"] as? String ?: "")
                put(ContactsContract.RawContacts.STARRED, if (entry["starred"] == true) 1 else 0)
                put(
                    ContactsContract.RawContacts.SEND_TO_VOICEMAIL,
                    if (entry["sendToVoicemail"] == true) 1 else 0,
                )
            }
            val rawRef: (ContentProviderOperation.Builder) -> ContentProviderOperation.Builder
            if (existing != null) {
                batch.add(
                    ContentProviderOperation
                        .newUpdate(asSyncAdapter(ContactsContract.RawContacts.CONTENT_URI))
                        .withSelection("${ContactsContract.RawContacts._ID} = ?", arrayOf(existing.toString()))
                        .withValues(rawValues)
                        .build(),
                )
                batch.add(
                    ContentProviderOperation
                        .newDelete(asSyncAdapter(ContactsContract.Data.CONTENT_URI))
                        .withSelection("${ContactsContract.Data.RAW_CONTACT_ID} = ?", arrayOf(existing.toString()))
                        .build(),
                )
                rawRef = { it.withValue(ContactsContract.Data.RAW_CONTACT_ID, existing) }
            } else {
                val index = batch.size
                batch.add(
                    ContentProviderOperation
                        .newInsert(asSyncAdapter(ContactsContract.RawContacts.CONTENT_URI))
                        .withValue(ContactsContract.RawContacts.ACCOUNT_TYPE, ACCOUNT_TYPE)
                        .withValue(ContactsContract.RawContacts.ACCOUNT_NAME, ACCOUNT_NAME)
                        .withValue(ContactsContract.RawContacts.SOURCE_ID, sourceId)
                        .withValues(rawValues)
                        .build(),
                )
                rawRef = { it.withValueBackReference(ContactsContract.Data.RAW_CONTACT_ID, index) }
            }

            fun data(mimeType: String, values: Map<String, Any?>) {
                val builder = rawRef(
                    ContentProviderOperation.newInsert(asSyncAdapter(ContactsContract.Data.CONTENT_URI)),
                ).withValue(ContactsContract.Data.MIMETYPE, mimeType)
                for ((key, value) in values) builder.withValue(key, value)
                batch.add(builder.build())
            }

            data(
                CommonDataKinds.StructuredName.CONTENT_ITEM_TYPE,
                mapOf(
                    CommonDataKinds.StructuredName.DISPLAY_NAME to entry["displayName"],
                    CommonDataKinds.StructuredName.GIVEN_NAME to entry["firstName"],
                    CommonDataKinds.StructuredName.FAMILY_NAME to entry["lastName"],
                ),
            )
            val phoneTypes = typeNames(entry["phoneTypes"])
            strings(entry["phones"]).forEachIndexed { i, number ->
                data(
                    CommonDataKinds.Phone.CONTENT_ITEM_TYPE,
                    mapOf(
                        CommonDataKinds.Phone.NUMBER to number,
                        CommonDataKinds.Phone.TYPE to phoneTypeCode(phoneTypes.getOrNull(i)),
                    ),
                )
            }
            val emailTypes = typeNames(entry["emailTypes"])
            strings(entry["emails"]).forEachIndexed { i, address ->
                data(
                    CommonDataKinds.Email.CONTENT_ITEM_TYPE,
                    mapOf(
                        CommonDataKinds.Email.ADDRESS to address,
                        CommonDataKinds.Email.TYPE to emailTypeCode(emailTypes.getOrNull(i)),
                    ),
                )
            }
            (entry["company"] as? String)?.takeIf { it.isNotBlank() }?.let {
                data(
                    CommonDataKinds.Organization.CONTENT_ITEM_TYPE,
                    mapOf(
                        CommonDataKinds.Organization.COMPANY to it,
                        CommonDataKinds.Organization.TYPE to CommonDataKinds.Organization.TYPE_WORK,
                    ),
                )
            }
            val addressTypes = typeNames(entry["addressTypes"])
            strings(entry["addresses"]).forEachIndexed { i, address ->
                data(
                    CommonDataKinds.StructuredPostal.CONTENT_ITEM_TYPE,
                    mapOf(
                        CommonDataKinds.StructuredPostal.FORMATTED_ADDRESS to address,
                        CommonDataKinds.StructuredPostal.TYPE to addressTypeCode(addressTypes.getOrNull(i)),
                    ),
                )
            }
            strings(entry["birthdays"]).forEach {
                data(
                    CommonDataKinds.Event.CONTENT_ITEM_TYPE,
                    mapOf(
                        CommonDataKinds.Event.START_DATE to it,
                        CommonDataKinds.Event.TYPE to CommonDataKinds.Event.TYPE_BIRTHDAY,
                    ),
                )
            }
            (entry["notes"] as? String)?.takeIf { it.isNotBlank() }?.let {
                data(CommonDataKinds.Note.CONTENT_ITEM_TYPE, mapOf(CommonDataKinds.Note.NOTE to it))
            }
            photo?.let { PhotoScaling.toJpeg(it, 512) }?.let {
                data(CommonDataKinds.Photo.CONTENT_ITEM_TYPE, mapOf(CommonDataKinds.Photo.PHOTO to it))
            }
        }
        batch.flush()
        return upserts.size + deletes.size
    }

    /**
     * Contacts in the account that a contacts app changed, added or
     * deleted since the last [acknowledge].
     */
    private fun changes(context: Context): List<Map<String, Any?>> {
        if (!hasAccount(context)) return emptyList()
        val out = ArrayList<Map<String, Any?>>()
        context.contentResolver.query(
            ContactsContract.RawContacts.CONTENT_URI,
            arrayOf(
                ContactsContract.RawContacts._ID,
                ContactsContract.RawContacts.SOURCE_ID,
                ContactsContract.RawContacts.DELETED,
                ContactsContract.RawContacts.STARRED,
            ),
            "${ContactsContract.RawContacts.ACCOUNT_TYPE} = ? AND " +
                "${ContactsContract.RawContacts.ACCOUNT_NAME} = ? AND (" +
                "${ContactsContract.RawContacts.DIRTY} = 1 OR " +
                "${ContactsContract.RawContacts.DELETED} = 1 OR " +
                "${ContactsContract.RawContacts.SOURCE_ID} IS NULL)",
            arrayOf(ACCOUNT_TYPE, ACCOUNT_NAME),
            null,
        )?.use { cursor ->
            while (cursor.moveToNext()) {
                val rawId = cursor.getLong(0)
                val deleted = cursor.getInt(2) == 1
                val change = HashMap<String, Any?>()
                change["rawId"] = rawId
                change["sourceId"] = cursor.getString(1)
                change["deleted"] = deleted
                change["starred"] = cursor.getInt(3) == 1
                if (!deleted) readData(context, rawId, change)
                out.add(change)
            }
        }
        return out
    }

    /** Adds the name, phones, emails and the rest of raw contact [rawId] to [into]. */
    private fun readData(context: Context, rawId: Long, into: HashMap<String, Any?>) {
        val phones = ArrayList<Map<String, String>>()
        val emails = ArrayList<Map<String, String>>()
        val addresses = ArrayList<Map<String, String>>()
        val birthdays = ArrayList<String>()
        context.contentResolver.query(
            ContactsContract.Data.CONTENT_URI,
            arrayOf(
                ContactsContract.Data.MIMETYPE,
                ContactsContract.Data.DATA1,
                ContactsContract.Data.DATA2,
                ContactsContract.Data.DATA3,
            ),
            "${ContactsContract.Data.RAW_CONTACT_ID} = ?",
            arrayOf(rawId.toString()),
            null,
        )?.use { cursor ->
            while (cursor.moveToNext()) {
                val mime = cursor.getString(0) ?: continue
                // The photo row holds bytes in other columns; everything
                // read here is text.
                if (mime == CommonDataKinds.Photo.CONTENT_ITEM_TYPE) continue
                val data1 = cursor.getString(1)?.trim().orEmpty()
                val data2 = cursor.getString(2)
                val type = data2?.toIntOrNull()
                when (mime) {
                    CommonDataKinds.StructuredName.CONTENT_ITEM_TYPE -> {
                        into["displayName"] = data1
                        into["firstName"] = data2?.trim().orEmpty()
                        into["lastName"] = cursor.getString(3)?.trim().orEmpty()
                    }
                    CommonDataKinds.Phone.CONTENT_ITEM_TYPE ->
                        if (data1.isNotEmpty()) {
                            phones.add(mapOf("value" to data1, "type" to phoneTypeName(type)))
                        }
                    CommonDataKinds.Email.CONTENT_ITEM_TYPE ->
                        if (data1.isNotEmpty()) {
                            emails.add(mapOf("value" to data1, "type" to emailTypeName(type)))
                        }
                    CommonDataKinds.StructuredPostal.CONTENT_ITEM_TYPE ->
                        if (data1.isNotEmpty()) {
                            addresses.add(mapOf("value" to data1, "type" to addressTypeName(type)))
                        }
                    CommonDataKinds.Organization.CONTENT_ITEM_TYPE -> into["company"] = data1
                    CommonDataKinds.Note.CONTENT_ITEM_TYPE -> into["notes"] = data1
                    CommonDataKinds.Event.CONTENT_ITEM_TYPE ->
                        if (type == CommonDataKinds.Event.TYPE_BIRTHDAY && data1.isNotEmpty()) {
                            birthdays.add(data1)
                        }
                }
            }
        }
        into["phones"] = phones
        into["emails"] = emails
        into["addresses"] = addresses
        into["birthdays"] = birthdays
    }

    /**
     * Clears the marks on changes the vault has taken in. Each item has the
     * `rawId`; `deleted` removes the row for good, otherwise it is tied to
     * the vault contact `sourceId` and rewritten from the vault on the next
     * [apply].
     */
    private fun acknowledge(context: Context, items: List<Map<String, Any?>>): Int {
        val batch = Batch(context)
        for (item in items) {
            val rawId = (item["rawId"] as? Number)?.toLong() ?: continue
            val selection = "${ContactsContract.RawContacts._ID} = ?"
            val args = arrayOf(rawId.toString())
            if (item["deleted"] == true) {
                batch.add(
                    ContentProviderOperation
                        .newDelete(asSyncAdapter(ContactsContract.RawContacts.CONTENT_URI))
                        .withSelection(selection, args)
                        .build(),
                )
            } else {
                val sourceId = item["sourceId"] as? String ?: continue
                batch.add(
                    ContentProviderOperation
                        .newUpdate(asSyncAdapter(ContactsContract.RawContacts.CONTENT_URI))
                        .withSelection(selection, args)
                        .withValue(ContactsContract.RawContacts.DIRTY, 0)
                        .withValue(ContactsContract.RawContacts.SOURCE_ID, sourceId)
                        // No hash: the next apply writes the vault's version.
                        .withValue(ContactsContract.RawContacts.SYNC1, "")
                        .build(),
                )
            }
        }
        batch.flush()
        return items.size
    }

    private fun typeNames(value: Any?): List<String?> =
        (value as? List<*>).orEmpty().map { it as? String }

    private fun phoneTypeCode(name: String?): Int = when (name) {
        "home" -> CommonDataKinds.Phone.TYPE_HOME
        "work" -> CommonDataKinds.Phone.TYPE_WORK
        "main" -> CommonDataKinds.Phone.TYPE_MAIN
        "other" -> CommonDataKinds.Phone.TYPE_OTHER
        else -> CommonDataKinds.Phone.TYPE_MOBILE
    }

    private fun phoneTypeName(code: Int?): String = when (code) {
        CommonDataKinds.Phone.TYPE_MOBILE, CommonDataKinds.Phone.TYPE_WORK_MOBILE -> "mobile"
        CommonDataKinds.Phone.TYPE_HOME -> "home"
        CommonDataKinds.Phone.TYPE_WORK, CommonDataKinds.Phone.TYPE_COMPANY_MAIN -> "work"
        CommonDataKinds.Phone.TYPE_MAIN -> "main"
        null -> ""
        else -> "other"
    }

    private fun emailTypeCode(name: String?): Int = when (name) {
        "home" -> CommonDataKinds.Email.TYPE_HOME
        "work" -> CommonDataKinds.Email.TYPE_WORK
        else -> CommonDataKinds.Email.TYPE_OTHER
    }

    private fun emailTypeName(code: Int?): String = when (code) {
        CommonDataKinds.Email.TYPE_HOME -> "home"
        CommonDataKinds.Email.TYPE_WORK -> "work"
        null -> ""
        else -> "other"
    }

    private fun addressTypeCode(name: String?): Int = when (name) {
        "work" -> CommonDataKinds.StructuredPostal.TYPE_WORK
        "other" -> CommonDataKinds.StructuredPostal.TYPE_OTHER
        else -> CommonDataKinds.StructuredPostal.TYPE_HOME
    }

    private fun addressTypeName(code: Int?): String = when (code) {
        CommonDataKinds.StructuredPostal.TYPE_HOME -> "home"
        CommonDataKinds.StructuredPostal.TYPE_WORK -> "work"
        null -> ""
        else -> "other"
    }

    private fun rawIdsBySourceId(context: Context): Map<String, Long> {
        val ids = mutableMapOf<String, Long>()
        context.contentResolver.query(
            ContactsContract.RawContacts.CONTENT_URI,
            arrayOf(ContactsContract.RawContacts._ID, ContactsContract.RawContacts.SOURCE_ID),
            "${ContactsContract.RawContacts.ACCOUNT_TYPE} = ? AND " +
                "${ContactsContract.RawContacts.ACCOUNT_NAME} = ?",
            arrayOf(ACCOUNT_TYPE, ACCOUNT_NAME),
            null,
        )?.use { cursor ->
            while (cursor.moveToNext()) {
                val sourceId = cursor.getString(1) ?: continue
                ids[sourceId] = cursor.getLong(0)
            }
        }
        return ids
    }

    private fun strings(value: Any?): List<String> =
        (value as? List<*>).orEmpty().mapNotNull { (it as? String)?.takeIf(String::isNotBlank) }

    private fun asSyncAdapter(uri: Uri): Uri = uri.buildUpon()
        .appendQueryParameter(ContactsContract.CALLER_IS_SYNCADAPTER, "true")
        .appendQueryParameter(ContactsContract.RawContacts.ACCOUNT_NAME, ACCOUNT_NAME)
        .appendQueryParameter(ContactsContract.RawContacts.ACCOUNT_TYPE, ACCOUNT_TYPE)
        .build()

    /**
     * Operations applied in batches small enough for one binder transaction
     * (about 1 MB, photos included). A batch is only cut between contacts,
     * so a new contact's back reference always points into its own batch.
     */
    private class Batch(private val context: Context) {
        private val ops = ArrayList<ContentProviderOperation>()
        private var bytes = 0

        val size: Int get() = ops.size

        fun startContact(photoBytes: Int) {
            if (ops.size >= 300 || bytes + photoBytes > 400_000) flush()
            bytes += photoBytes
        }

        fun add(op: ContentProviderOperation) {
            ops.add(op)
        }

        fun flush() {
            if (ops.isEmpty()) return
            context.contentResolver.applyBatch(ContactsContract.AUTHORITY, ops)
            ops.clear()
            bytes = 0
        }
    }
}
