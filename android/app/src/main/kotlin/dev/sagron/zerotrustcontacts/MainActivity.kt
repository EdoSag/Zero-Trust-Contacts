package dev.sagron.zerotrustcontacts

import android.Manifest
import android.content.ContentUris
import android.content.Intent
import android.content.pm.PackageManager
import android.database.Cursor
import android.net.Uri
import android.os.Bundle
import android.provider.ContactsContract
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

class MainActivity : FlutterFragmentActivity() {
    private val channelName = "zerotrust_contacts/device_contacts"
    private val googleAccountType = "com.google"
    private val requestCodeReadContacts = 2001
    private val requestCodeWriteContacts = 2002
    private var pendingPermissionResult: MethodChannel.Result? = null
    private var pendingWritePermissionResult: MethodChannel.Result? = null
    private var channel: MethodChannel? = null
    private var pendingOpenedContact: Map<String, Any?>? = null

    /** A vCard file or an "add a contact" request from another app. */
    private var pendingIncoming: Map<String, Any?>? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        cacheContactFromIntent(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        channel
            ?.setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestContactsPermission" -> handlePermissionRequest(result)
                    "requestWriteContactsPermission" -> handleWritePermissionRequest(result)
                    "consumePendingOpenedContact" -> {
                        val contact = pendingOpenedContact?.let { payload ->
                            val uri = payload["uri"] as? String
                            if (uri != null && !payload.containsKey("id") && hasReadContactsPermission()) {
                                buildOpenedContact(Uri.parse(uri)) ?: payload
                            } else {
                                payload
                            }
                        }
                        result.success(contact)
                        pendingOpenedContact = null
                    }
                    "consumePendingIncoming" -> {
                        result.success(pendingIncoming)
                        pendingIncoming = null
                    }
                    "launchDialer" -> {
                        val phoneNumber = call.argument<String>("phoneNumber")
                        if (phoneNumber.isNullOrBlank()) {
                            result.error("invalid_argument", "Missing phone number.", null)
                            return@setMethodCallHandler
                        }
                        launchDialer(phoneNumber)
                        result.success(true)
                    }

                    "launchSms" -> {
                        val phoneNumber = call.argument<String>("phoneNumber")
                        if (phoneNumber.isNullOrBlank()) {
                            result.error("invalid_argument", "Missing phone number.", null)
                            return@setMethodCallHandler
                        }
                        launchSms(phoneNumber)
                        result.success(true)
                    }

                    "getDeviceContacts" -> {
                        val selectedAccount = call.argument<String>("selectedAccount")
                        try {
                            result.success(getDeviceContacts(selectedAccount))
                        } catch (error: SecurityException) {
                            result.error(
                                "permission_denied",
                                "Contacts permission is required to read contacts.",
                                null,
                            )
                        } catch (error: Exception) {
                            result.error(
                                "contacts_read_failed",
                                error.localizedMessage,
                                null,
                            )
                        }
                    }

                    "getContactSourceStats" -> {
                        val selectedAccount = call.argument<String>("selectedAccount")
                        try {
                            result.success(getContactSourceStats(selectedAccount))
                        } catch (error: SecurityException) {
                            result.error(
                                "permission_denied",
                                "Contacts permission is required to read contact sources.",
                                null,
                            )
                        } catch (error: Exception) {
                            result.error(
                                "contacts_stats_failed",
                                error.localizedMessage,
                                null,
                            )
                        }
                    }

                    "getImportAccounts" -> {
                        val accountType = call.argument<String>("accountType") ?: googleAccountType
                        try {
                            result.success(getImportAccounts(accountType))
                        } catch (error: SecurityException) {
                            result.error(
                                "permission_denied",
                                "Contacts permission is required to list accounts.",
                                null,
                            )
                        } catch (error: Exception) {
                            result.error("accounts_read_failed", error.localizedMessage, null)
                        }
                    }

                    "getAllImportAccounts" -> {
                        try {
                            result.success(getAllImportAccounts())
                        } catch (error: SecurityException) {
                            result.error(
                                "permission_denied",
                                "Contacts permission is required to list accounts.",
                                null,
                            )
                        } catch (error: Exception) {
                            result.error("accounts_read_failed", error.localizedMessage, null)
                        }
                    }

                    "getSimContacts" -> {
                        Thread {
                            try {
                                val contacts = SimContacts.read(this)
                                runOnUiThread { result.success(contacts) }
                            } catch (error: SecurityException) {
                                runOnUiThread {
                                    result.error(
                                        "permission_denied",
                                        "Contacts permission is required to read the SIM card.",
                                        null,
                                    )
                                }
                            } catch (error: Exception) {
                                runOnUiThread {
                                    result.error("sim_read_failed", error.localizedMessage, null)
                                }
                            }
                        }.start()
                    }

                    "getAccountContacts" -> {
                        val accountType = call.argument<String>("accountType") ?: googleAccountType
                        val accountName = call.argument<String>("accountName")
                        if (accountName.isNullOrBlank()) {
                            result.error("invalid_argument", "Missing account name.", null)
                            return@setMethodCallHandler
                        }
                        // Reading every row can take a moment on big address books,
                        // so keep it off the UI thread.
                        Thread {
                            try {
                                val contacts = getAccountContacts(accountType, accountName)
                                runOnUiThread { result.success(contacts) }
                            } catch (error: SecurityException) {
                                runOnUiThread {
                                    result.error(
                                        "permission_denied",
                                        "Contacts permission is required to read contacts.",
                                        null,
                                    )
                                }
                            } catch (error: Exception) {
                                runOnUiThread {
                                    result.error("contacts_read_failed", error.localizedMessage, null)
                                }
                            }
                        }.start()
                    }

                    "getRawContactPhoto" -> {
                        val rawId = call.argument<Number>("rawContactId")?.toLong()
                        if (rawId == null) {
                            result.error("invalid_argument", "Missing raw contact id.", null)
                            return@setMethodCallHandler
                        }
                        Thread {
                            try {
                                val bytes = readRawContactPhoto(rawId)
                                runOnUiThread { result.success(bytes) }
                            } catch (error: SecurityException) {
                                runOnUiThread {
                                    result.error("permission_denied", "Contacts permission is required.", null)
                                }
                            } catch (error: Exception) {
                                runOnUiThread { result.success(null) }
                            }
                        }.start()
                    }

                    else -> PhoneContactsSync.handle(this, call, result) ?: result.notImplemented()
                }
            }
        flushPendingOpenedContact()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        cacheContactFromIntent(intent)
        flushPendingOpenedContact()
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == requestCodeWriteContacts) {
            val granted = grantResults.isNotEmpty() &&
                grantResults.all { it == PackageManager.PERMISSION_GRANTED }
            pendingWritePermissionResult?.success(granted)
            pendingWritePermissionResult = null
            return
        }
        if (requestCode != requestCodeReadContacts) {
            return
        }

        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        pendingPermissionResult?.success(granted)
        pendingPermissionResult = null
    }

    private fun handlePermissionRequest(result: MethodChannel.Result) {
        if (hasReadContactsPermission()) {
            result.success(true)
            return
        }

        if (pendingPermissionResult != null) {
            result.error(
                "permission_request_in_progress",
                "A contacts permission request is already in progress.",
                null,
            )
            return
        }

        pendingPermissionResult = result
        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.READ_CONTACTS),
            requestCodeReadContacts,
        )
    }

    /** Read and write contacts, for "Show in Phone and Messages". */
    private fun handleWritePermissionRequest(result: MethodChannel.Result) {
        val needed = arrayOf(Manifest.permission.READ_CONTACTS, Manifest.permission.WRITE_CONTACTS)
        if (needed.all { ContextCompat.checkSelfPermission(this, it) == PackageManager.PERMISSION_GRANTED }) {
            result.success(true)
            return
        }
        if (pendingWritePermissionResult != null) {
            result.error("permission_request_in_progress", "A contacts permission request is already in progress.", null)
            return
        }
        pendingWritePermissionResult = result
        ActivityCompat.requestPermissions(this, needed, requestCodeWriteContacts)
    }

    private fun hasReadContactsPermission(): Boolean {
        return ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.READ_CONTACTS,
        ) == PackageManager.PERMISSION_GRANTED
    }

    private fun getDeviceContacts(selectedAccount: String?): List<Map<String, String>> {
        ensureContactsPermission()

        val sources = buildContactSources(selectedAccount)
        val projection = arrayOf(
            ContactsContract.CommonDataKinds.Phone.CONTACT_ID,
            ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME_PRIMARY,
            ContactsContract.CommonDataKinds.Phone.NUMBER,
        )
        val contactsById = linkedMapOf<Long, MutableMap<String, String>>()

        contentResolver.query(
            ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
            projection,
            null,
            null,
            "${ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME_PRIMARY} COLLATE NOCASE ASC",
        )?.use { cursor ->
            val idIndex =
                cursor.getColumnIndexOrThrow(ContactsContract.CommonDataKinds.Phone.CONTACT_ID)
            val nameIndex = cursor.getColumnIndexOrThrow(
                ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME_PRIMARY,
            )
            val phoneIndex =
                cursor.getColumnIndexOrThrow(ContactsContract.CommonDataKinds.Phone.NUMBER)

            while (cursor.moveToNext()) {
                val contactId = cursor.getLong(idIndex)
                // Copies the app itself put on the phone are already in the vault.
                if (sources[contactId] == ownSource) continue
                val name = cursor.getString(nameIndex)?.trim().orEmpty()
                val phone = cursor.getString(phoneIndex)?.trim().orEmpty()

                val existingContact = contactsById[contactId]
                if (existingContact == null) {
                    contactsById[contactId] = mutableMapOf(
                        "id" to contactId.toString(),
                        "name" to if (name.isNotEmpty()) name else "Unnamed Contact",
                        "phone" to phone,
                        "source" to (sources[contactId] ?: "Phone"),
                    )
                } else if ((existingContact["phone"] ?: "").isEmpty() && phone.isNotEmpty()) {
                    existingContact["phone"] = phone
                }
            }
        }

        return contactsById.values.toList()
    }

    private fun getContactSourceStats(selectedAccount: String?): Map<String, Int> {
        ensureContactsPermission()
        val sources = buildContactSources(selectedAccount)

        var accountCount = 0
        var simCount = 0
        var phoneCount = 0
        for (source in sources.values) {
            when (source) {
                ownSource -> Unit
                "Account" -> accountCount += 1
                "SIM card" -> simCount += 1
                else -> phoneCount += 1
            }
        }

        return mapOf(
            "accountCount" to accountCount,
            "simCount" to simCount,
            "phoneCount" to phoneCount,
        )
    }

    private fun buildContactSources(selectedAccount: String?): Map<Long, String> {
        val selectedAccountNormalized = selectedAccount
            ?.trim()
            ?.lowercase(Locale.US)
            .orEmpty()

        val contactSources = mutableMapOf<Long, String>()
        val projection = arrayOf(
            ContactsContract.RawContacts.CONTACT_ID,
            ContactsContract.RawContacts.ACCOUNT_TYPE,
            ContactsContract.RawContacts.ACCOUNT_NAME,
            ContactsContract.RawContacts.DELETED,
        )

        contentResolver.query(
            ContactsContract.RawContacts.CONTENT_URI,
            projection,
            null,
            null,
            null,
        )?.use { cursor ->
            val contactIdIndex =
                cursor.getColumnIndexOrThrow(ContactsContract.RawContacts.CONTACT_ID)
            val accountTypeIndex =
                cursor.getColumnIndexOrThrow(ContactsContract.RawContacts.ACCOUNT_TYPE)
            val accountNameIndex =
                cursor.getColumnIndexOrThrow(ContactsContract.RawContacts.ACCOUNT_NAME)
            val deletedIndex = cursor.getColumnIndexOrThrow(ContactsContract.RawContacts.DELETED)

            while (cursor.moveToNext()) {
                val deleted = cursor.getInt(deletedIndex) == 1
                if (deleted) {
                    continue
                }

                val contactId = cursor.getLong(contactIdIndex)
                if (contactId <= 0L) {
                    continue
                }

                val accountType = cursor.getString(accountTypeIndex)
                val accountName = cursor.getString(accountNameIndex)
                val candidateSource = classifySource(
                    accountType = accountType,
                    accountName = accountName,
                    selectedAccountNormalized = selectedAccountNormalized,
                )
                val existingSource = contactSources[contactId]
                if (existingSource == null || sourcePriority(candidateSource) > sourcePriority(
                        existingSource,
                    )
                ) {
                    contactSources[contactId] = candidateSource
                }
            }
        }

        return contactSources
    }

    private fun classifySource(
        accountType: String?,
        accountName: String?,
        selectedAccountNormalized: String,
    ): String {
        if (accountType == PhoneContactsSync.ACCOUNT_TYPE) {
            return ownSource
        }
        val normalizedType = accountType?.lowercase(Locale.US).orEmpty()
        val normalizedName = accountName?.lowercase(Locale.US).orEmpty()

        if (
            normalizedType.contains("sim") ||
            normalizedName.contains("sim")
        ) {
            return "SIM card"
        }

        if (
            normalizedType.contains("google") ||
            (selectedAccountNormalized.isNotEmpty() &&
                normalizedName == selectedAccountNormalized)
        ) {
            return "Account"
        }

        return "Phone"
    }

    private val ownSource = "ZT Contacts"

    private fun sourcePriority(source: String): Int {
        return when (source) {
            ownSource -> 0
            "SIM card" -> 3
            "Account" -> 2
            else -> 1
        }
    }

    /**
     * Raw contacts of one account. An empty type or name stands for "none":
     * contacts saved to the phone itself have no account.
     */
    private fun accountSelection(accountType: String, accountName: String): String {
        val type = if (accountType.isEmpty()) {
            "${ContactsContract.RawContacts.ACCOUNT_TYPE} IS NULL"
        } else {
            "${ContactsContract.RawContacts.ACCOUNT_TYPE} = ?"
        }
        val name = if (accountName.isEmpty()) {
            "${ContactsContract.RawContacts.ACCOUNT_NAME} IS NULL"
        } else {
            "${ContactsContract.RawContacts.ACCOUNT_NAME} = ?"
        }
        return "$type AND $name AND ${ContactsContract.RawContacts.DELETED} = 0"
    }

    private fun accountSelectionArgs(accountType: String, accountName: String): Array<String> =
        listOf(accountType, accountName).filter { it.isNotEmpty() }.toTypedArray()

    /**
     * Every account on this phone that holds contacts (Google, Samsung,
     * Outlook/Exchange, SIM card, the phone itself…), except ZT Contacts'
     * own caller-ID copy, with counts.
     */
    private fun getAllImportAccounts(): List<Map<String, Any>> {
        ensureContactsPermission()
        val counts = linkedMapOf<Pair<String, String>, Int>()
        contentResolver.query(
            ContactsContract.RawContacts.CONTENT_URI,
            arrayOf(
                ContactsContract.RawContacts.ACCOUNT_TYPE,
                ContactsContract.RawContacts.ACCOUNT_NAME,
            ),
            "${ContactsContract.RawContacts.DELETED} = 0",
            null,
            "${ContactsContract.RawContacts.ACCOUNT_NAME} COLLATE NOCASE ASC",
        )?.use { cursor ->
            while (cursor.moveToNext()) {
                val type = cursor.getString(0)?.trim().orEmpty()
                val name = cursor.getString(1)?.trim().orEmpty()
                if (type == PhoneContactsSync.ACCOUNT_TYPE) continue
                val key = type to name
                counts[key] = (counts[key] ?: 0) + 1
            }
        }
        return counts.map { (key, count) ->
            mapOf(
                "type" to key.first,
                "name" to key.second,
                "kind" to accountKind(key.first, key.second),
                "count" to count,
            )
        }
    }

    /** google, sim, exchange, samsung, phone or other: picks the icon and wording. */
    private fun accountKind(type: String, name: String): String {
        val t = type.lowercase(Locale.US)
        val n = name.lowercase(Locale.US)
        return when {
            t == googleAccountType -> "google"
            t.contains("sim") || t.contains("icc") || n.contains("sim") -> "sim"
            t.contains("exchange") || t.contains("outlook") ||
                t.contains("microsoft") || t.contains("office") -> "exchange"
            t.isEmpty() || t.contains("phone") || t.contains("local") ||
                n == "phone" || n == "device" -> "phone"
            t.contains("samsung") || t.contains("osp") -> "samsung"
            else -> "other"
        }
    }

    /** Accounts of [accountType] that have contacts on this phone, with counts. */
    private fun getImportAccounts(accountType: String): List<Map<String, Any>> {
        ensureContactsPermission()
        val counts = linkedMapOf<String, Int>()
        contentResolver.query(
            ContactsContract.RawContacts.CONTENT_URI,
            arrayOf(ContactsContract.RawContacts.ACCOUNT_NAME),
            "${ContactsContract.RawContacts.ACCOUNT_TYPE} = ? AND ${ContactsContract.RawContacts.DELETED} = 0",
            arrayOf(accountType),
            "${ContactsContract.RawContacts.ACCOUNT_NAME} COLLATE NOCASE ASC",
        )?.use { cursor ->
            val nameIndex = cursor.getColumnIndexOrThrow(ContactsContract.RawContacts.ACCOUNT_NAME)
            while (cursor.moveToNext()) {
                val name = cursor.getString(nameIndex)?.trim().orEmpty()
                if (name.isNotEmpty()) {
                    counts[name] = (counts[name] ?: 0) + 1
                }
            }
        }
        return counts.map { (name, count) -> mapOf("name" to name, "count" to count) }
    }

    /**
     * Every contact stored in one account, with all the fields the vault keeps.
     * Read straight from the phone's contacts database: no network, no Google API.
     */
    private fun getAccountContacts(
        accountType: String,
        accountName: String,
    ): List<Map<String, Any>> {
        ensureContactsPermission()

        val contacts = linkedMapOf<Long, MutableMap<String, Any>>()
        contentResolver.query(
            ContactsContract.RawContacts.CONTENT_URI,
            arrayOf(ContactsContract.RawContacts._ID, ContactsContract.RawContacts.STARRED),
            accountSelection(accountType, accountName),
            accountSelectionArgs(accountType, accountName),
            null,
        )?.use { cursor ->
            val idIndex = cursor.getColumnIndexOrThrow(ContactsContract.RawContacts._ID)
            val starredIndex = cursor.getColumnIndexOrThrow(ContactsContract.RawContacts.STARRED)
            while (cursor.moveToNext()) {
                val rawId = cursor.getLong(idIndex)
                contacts[rawId] = mutableMapOf(
                    "rawId" to rawId,
                    "hasPhoto" to false,
                    "isFavorite" to (cursor.getInt(starredIndex) == 1),
                    "phones" to mutableListOf<String>(),
                    "emails" to mutableListOf<String>(),
                    "addresses" to mutableListOf<String>(),
                    "labels" to mutableListOf<String>(),
                    "birthdays" to mutableListOf<String>(),
                    "other" to mutableListOf<String>(),
                    // Kinds (mobile, work…), keyed "phone\n<number>".
                    "types" to mutableMapOf<String, String>(),
                )
            }
        }
        if (contacts.isEmpty()) {
            return emptyList()
        }

        val groupTitles = readUserGroupTitles(accountType, accountName)
        val projection = arrayOf(
            ContactsContract.Data.RAW_CONTACT_ID,
            ContactsContract.Data.MIMETYPE,
            ContactsContract.Data.DATA1,
            ContactsContract.Data.DATA2,
            ContactsContract.Data.DATA3,
            ContactsContract.Data.DATA4,
            ContactsContract.Data.DATA5,
            ContactsContract.Data.DATA14,
            ContactsContract.Data.DATA15,
        )

        contacts.keys.chunked(400).forEach { chunk ->
            val placeholders = chunk.joinToString(",") { "?" }
            contentResolver.query(
                ContactsContract.Data.CONTENT_URI,
                projection,
                "${ContactsContract.Data.RAW_CONTACT_ID} IN ($placeholders)",
                chunk.map { it.toString() }.toTypedArray(),
                null,
            )?.use { cursor ->
                while (cursor.moveToNext()) {
                    val contact = contacts[cursor.getLong(0)] ?: continue
                    val mimeType = cursor.getString(1) ?: continue
                    if (mimeType == ContactsContract.CommonDataKinds.Photo.CONTENT_ITEM_TYPE) {
                        // DATA14: full-size photo file id, DATA15: thumbnail bytes.
                        if (!cursor.isNull(7) || !cursor.isNull(8)) contact["hasPhoto"] = true
                        continue
                    }
                    val data1 = cursor.getString(2)?.trim().orEmpty()
                    applyDataRow(contact, mimeType, data1, cursor, groupTitles)
                }
            }
        }

        return contacts.values.filter { contact ->
            listOf("displayName", "firstName", "lastName", "company").any {
                (contact[it] as? String).orEmpty().isNotBlank()
            } || (contact["phones"] as List<*>).isNotEmpty() ||
                (contact["emails"] as List<*>).isNotEmpty()
        }
    }

    @Suppress("UNCHECKED_CAST")
    private fun applyDataRow(
        contact: MutableMap<String, Any>,
        mimeType: String,
        data1: String,
        cursor: Cursor,
        groupTitles: Map<Long, String>,
    ) {
        fun list(key: String) = contact[key] as MutableList<String>
        fun column(index: Int) = cursor.getString(index)?.trim().orEmpty()
        fun remember(field: String, value: String, type: String) {
            if (type.isNotEmpty()) {
                (contact["types"] as MutableMap<String, String>)["$field\n$value"] = type
            }
        }
        val typeCode = column(3).toIntOrNull()

        when (mimeType) {
            ContactsContract.CommonDataKinds.StructuredName.CONTENT_ITEM_TYPE -> {
                contact["displayName"] = data1
                contact["firstName"] = listOf(column(3), column(6))
                    .filter { it.isNotEmpty() }
                    .joinToString(" ")
                contact["lastName"] = column(4)
            }
            ContactsContract.CommonDataKinds.Phone.CONTENT_ITEM_TYPE ->
                if (data1.isNotEmpty()) {
                    list("phones").add(data1)
                    remember("phone", data1, PhoneContactsSync.phoneTypeName(typeCode))
                }
            ContactsContract.CommonDataKinds.Email.CONTENT_ITEM_TYPE ->
                if (data1.isNotEmpty()) {
                    list("emails").add(data1)
                    remember("email", data1, PhoneContactsSync.emailTypeName(typeCode))
                }
            ContactsContract.CommonDataKinds.StructuredPostal.CONTENT_ITEM_TYPE ->
                if (data1.isNotEmpty()) {
                    val address = data1.replace("\n", ", ")
                    list("addresses").add(address)
                    remember("address", address, PhoneContactsSync.addressTypeName(typeCode))
                }
            ContactsContract.CommonDataKinds.Organization.CONTENT_ITEM_TYPE -> {
                val title = column(5)
                contact["company"] = listOf(title, data1).filter { it.isNotEmpty() }.joinToString(", ")
            }
            ContactsContract.CommonDataKinds.Note.CONTENT_ITEM_TYPE ->
                if (data1.isNotEmpty()) contact["notes"] = data1
            ContactsContract.CommonDataKinds.Event.CONTENT_ITEM_TYPE -> {
                if (data1.isEmpty()) return
                val type = cursor.getInt(3)
                if (type == ContactsContract.CommonDataKinds.Event.TYPE_BIRTHDAY) {
                    list("birthdays").add(data1)
                } else if (type == ContactsContract.CommonDataKinds.Event.TYPE_ANNIVERSARY) {
                    list("other").add("Anniversary: $data1")
                }
            }
            ContactsContract.CommonDataKinds.GroupMembership.CONTENT_ITEM_TYPE -> {
                val title = data1.toLongOrNull()?.let { groupTitles[it] }
                if (!title.isNullOrBlank()) list("labels").add(title)
            }
            ContactsContract.CommonDataKinds.Website.CONTENT_ITEM_TYPE ->
                if (data1.isNotEmpty()) list("other").add(data1)
            ContactsContract.CommonDataKinds.Nickname.CONTENT_ITEM_TYPE ->
                if (data1.isNotEmpty()) list("other").add("Nickname: $data1")
        }
    }

    /** User-made labels only; system groups such as "My Contacts" are skipped. */
    private fun readUserGroupTitles(accountType: String, accountName: String): Map<Long, String> {
        val titles = mutableMapOf<Long, String>()
        contentResolver.query(
            ContactsContract.Groups.CONTENT_URI,
            arrayOf(
                ContactsContract.Groups._ID,
                ContactsContract.Groups.TITLE,
                ContactsContract.Groups.SYSTEM_ID,
            ),
            // Groups use the same account_type / account_name / deleted columns.
            accountSelection(accountType, accountName),
            accountSelectionArgs(accountType, accountName),
            null,
        )?.use { cursor ->
            while (cursor.moveToNext()) {
                if (!cursor.isNull(2)) continue
                val title = cursor.getString(1)?.trim().orEmpty()
                if (title.isNotEmpty()) titles[cursor.getLong(0)] = title
            }
        }
        return titles
    }

    /**
     * One raw contact's photo as a JPEG of at most [maxPhotoSide] px: the
     * full-size display photo when there is one, else the thumbnail. Read
     * from the phone's contacts database; nothing goes to Google.
     */
    private fun readRawContactPhoto(rawId: Long): ByteArray? {
        ensureContactsPermission()
        val rawUri = ContentUris.withAppendedId(ContactsContract.RawContacts.CONTENT_URI, rawId)
        val displayUri = Uri.withAppendedPath(
            rawUri,
            ContactsContract.RawContacts.DisplayPhoto.CONTENT_DIRECTORY,
        )
        val full = try {
            contentResolver.openAssetFileDescriptor(displayUri, "r")?.use { fd ->
                fd.createInputStream().use { it.readBytes() }
            }
        } catch (error: Exception) {
            null
        }
        val original = full ?: contentResolver.query(
            ContactsContract.Data.CONTENT_URI,
            arrayOf(ContactsContract.CommonDataKinds.Photo.PHOTO),
            "${ContactsContract.Data.RAW_CONTACT_ID} = ? AND ${ContactsContract.Data.MIMETYPE} = ?",
            arrayOf(rawId.toString(), ContactsContract.CommonDataKinds.Photo.CONTENT_ITEM_TYPE),
            null,
        )?.use { cursor -> if (cursor.moveToFirst() && !cursor.isNull(0)) cursor.getBlob(0) else null }
        return original?.let { PhotoScaling.toJpeg(it, maxPhotoSide) }
    }

    private val maxPhotoSide = 800

    private fun ensureContactsPermission() {
        if (!hasReadContactsPermission()) {
            throw SecurityException("READ_CONTACTS permission not granted.")
        }
    }

    private fun cacheContactFromIntent(intent: Intent?) {
        val incoming = try {
            IncomingIntents.read(this, intent)
        } catch (error: Exception) {
            null
        }
        if (incoming != null) {
            pendingIncoming = incoming
            return
        }
        pendingOpenedContact = readContactFromIntent(intent) ?: pendingOpenedContact
    }

    private fun flushPendingOpenedContact() {
        // Only a nudge: the Flutter side fetches it once the vault is open.
        if (pendingIncoming != null) channel?.invokeMethod("incomingReceived", null)
        val contact = pendingOpenedContact ?: return
        channel?.invokeMethod("contactIntentReceived", contact)
    }

    private fun readContactFromIntent(intent: Intent?): Map<String, Any?>? {
        if (intent == null) {
            return null
        }
        val action = intent.action ?: return null
        if (action != Intent.ACTION_VIEW && action != Intent.ACTION_EDIT) {
            return null
        }

        val contactUri = intent.data ?: return null
        return buildOpenedContact(contactUri)
    }

    private fun buildOpenedContact(contactUri: Uri): Map<String, Any?>? {
        if (!hasReadContactsPermission()) {
            return mapOf(
                "uri" to contactUri.toString(),
                "source" to "Phone",
            )
        }

        val resolvedUri = resolveContactUri(contactUri) ?: contactUri
        val projection = arrayOf(
            ContactsContract.Contacts._ID,
            ContactsContract.Contacts.LOOKUP_KEY,
            ContactsContract.Contacts.DISPLAY_NAME_PRIMARY,
        )

        contentResolver.query(
            resolvedUri,
            projection,
            null,
            null,
            null,
        )?.use { cursor ->
            if (!cursor.moveToFirst()) {
                return null
            }

            val id = cursor.getLongValue(ContactsContract.Contacts._ID)
            if (id <= 0L) {
                return null
            }
            val lookupKey = cursor.getStringValue(ContactsContract.Contacts.LOOKUP_KEY)
            val displayName = cursor
                .getStringValue(ContactsContract.Contacts.DISPLAY_NAME_PRIMARY)
                ?.trim()
                .orEmpty()
            val phones = readPhoneNumbers(id)
            val source = buildContactSources(null)[id] ?: "Phone"

            return mapOf(
                "id" to "device_$id",
                "deviceId" to id.toString(),
                "lookupKey" to (lookupKey ?: ""),
                "displayName" to if (displayName.isNotEmpty()) displayName else "Unnamed Contact",
                "firstName" to displayName,
                "phones" to phones,
                "source" to source,
                "uri" to resolvedUri.toString(),
            )
        }

        return null
    }

    private fun resolveContactUri(uri: Uri): Uri? {
        return ContactsContract.Contacts.lookupContact(contentResolver, uri)
    }

    private fun readPhoneNumbers(contactId: Long): List<String> {
        val numbers = linkedSetOf<String>()
        contentResolver.query(
            ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
            arrayOf(ContactsContract.CommonDataKinds.Phone.NUMBER),
            "${ContactsContract.CommonDataKinds.Phone.CONTACT_ID} = ?",
            arrayOf(contactId.toString()),
            null,
        )?.use { cursor ->
            val numberIndex =
                cursor.getColumnIndexOrThrow(ContactsContract.CommonDataKinds.Phone.NUMBER)
            while (cursor.moveToNext()) {
                val number = cursor.getString(numberIndex)?.trim().orEmpty()
                if (number.isNotEmpty()) {
                    numbers.add(number)
                }
            }
        }
        return numbers.toList()
    }

    private fun launchDialer(phoneNumber: String) {
        val intent = Intent(
            Intent.ACTION_DIAL,
            Uri.parse("tel:${Uri.encode(phoneNumber.trim())}"),
        ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        startActivity(intent)
    }

    private fun launchSms(phoneNumber: String) {
        val intent = Intent(
            Intent.ACTION_SENDTO,
            Uri.parse("smsto:${Uri.encode(phoneNumber.trim())}"),
        ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        startActivity(intent)
    }

    private fun Cursor.getLongValue(columnName: String): Long {
        val index = getColumnIndex(columnName)
        return if (index >= 0 && !isNull(index)) getLong(index) else -1L
    }

    private fun Cursor.getStringValue(columnName: String): String? {
        val index = getColumnIndex(columnName)
        return if (index >= 0 && !isNull(index)) getString(index) else null
    }
}
