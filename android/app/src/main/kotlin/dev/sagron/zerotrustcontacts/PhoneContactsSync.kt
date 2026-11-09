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
            strings(entry["phones"]).forEach {
                data(
                    CommonDataKinds.Phone.CONTENT_ITEM_TYPE,
                    mapOf(
                        CommonDataKinds.Phone.NUMBER to it,
                        CommonDataKinds.Phone.TYPE to CommonDataKinds.Phone.TYPE_MOBILE,
                    ),
                )
            }
            strings(entry["emails"]).forEach {
                data(
                    CommonDataKinds.Email.CONTENT_ITEM_TYPE,
                    mapOf(
                        CommonDataKinds.Email.ADDRESS to it,
                        CommonDataKinds.Email.TYPE to CommonDataKinds.Email.TYPE_OTHER,
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
            strings(entry["addresses"]).forEach {
                data(
                    CommonDataKinds.StructuredPostal.CONTENT_ITEM_TYPE,
                    mapOf(
                        CommonDataKinds.StructuredPostal.FORMATTED_ADDRESS to it,
                        CommonDataKinds.StructuredPostal.TYPE to CommonDataKinds.StructuredPostal.TYPE_HOME,
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
