package dev.sagron.zerotrustcontacts

import android.Manifest
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
    private val requestCodeReadContacts = 2001
    private var pendingPermissionResult: MethodChannel.Result? = null
    private var channel: MethodChannel? = null
    private var pendingOpenedContact: Map<String, Any?>? = null

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

                    else -> result.notImplemented()
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

    private fun sourcePriority(source: String): Int {
        return when (source) {
            "SIM card" -> 3
            "Account" -> 2
            else -> 1
        }
    }

    private fun ensureContactsPermission() {
        if (!hasReadContactsPermission()) {
            throw SecurityException("READ_CONTACTS permission not granted.")
        }
    }

    private fun cacheContactFromIntent(intent: Intent?) {
        pendingOpenedContact = readContactFromIntent(intent) ?: pendingOpenedContact
    }

    private fun flushPendingOpenedContact() {
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
