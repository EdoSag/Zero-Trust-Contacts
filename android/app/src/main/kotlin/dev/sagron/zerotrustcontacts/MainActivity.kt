package dev.sagron.zerotrustcontacts

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
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

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestContactsPermission" -> handlePermissionRequest(result)
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
}
