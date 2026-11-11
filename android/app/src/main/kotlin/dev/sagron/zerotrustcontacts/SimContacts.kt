package dev.sagron.zerotrustcontacts

import android.content.Context
import android.database.Cursor
import android.net.Uri
import android.os.Build
import android.provider.SimPhonebookContract
import android.telephony.SubscriptionManager

/**
 * Reads the contacts stored on the SIM card itself (name, number and, on
 * some SIMs, an email). Many phones don't show these as an account, so the
 * account list alone would miss them.
 *
 * Read on the phone only; needs the contacts permission, nothing else.
 */
object SimContacts {
    fun read(context: Context): List<Map<String, Any>> {
        val found = linkedMapOf<String, SimContact>()
        fun add(name: String, number: String, emails: List<String>) {
            val n = name.trim()
            val p = number.trim()
            if (n.isEmpty() && p.isEmpty()) return
            val key = "$n\n${p.filter { it.isDigit() || it == '+' }}"
            // Both providers can list the same contact, and only the older
            // one has its emails: keep those instead of dropping the copy.
            found.getOrPut(key) { SimContact(n, p) }.emails.addAll(emails)
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            // Android 12+: the official SIM phonebook, for every SIM in the
            // phone (dual-SIM phones can use any subscription ids).
            for (subId in simSubscriptionIds(context)) {
                try {
                    val uri = SimPhonebookContract.SimRecords.getContentUri(
                        subId,
                        SimPhonebookContract.ElementaryFiles.EF_ADN,
                    )
                    context.contentResolver.query(
                        uri,
                        arrayOf(
                            SimPhonebookContract.SimRecords.NAME,
                            SimPhonebookContract.SimRecords.PHONE_NUMBER,
                        ),
                        null,
                        null,
                        null,
                    )?.use { cursor ->
                        while (cursor.moveToNext()) {
                            add(cursor.text(0), cursor.text(1), emptyList())
                        }
                    }
                } catch (error: SecurityException) {
                    throw error
                } catch (ignored: Exception) {
                    // This SIM can't be read: try the others, then fall back below.
                }
            }
        }

        // The older provider for Android 9-11 (and phones whose SIM
        // phonebook above is missing). Without the phone-state permission the
        // subscription ids can't be listed, so the usual ones are tried.
        for (uri in listOf("content://icc/adn", "content://icc/adn/subId/1", "content://icc/adn/subId/2")) {
            try {
                context.contentResolver.query(Uri.parse(uri), null, null, null, null)?.use { cursor ->
                    val name = cursor.getColumnIndex("name")
                    val number = cursor.getColumnIndex("number")
                    val emails = cursor.getColumnIndex("emails")
                    while (cursor.moveToNext()) {
                        add(
                            if (name >= 0) cursor.text(name) else "",
                            if (number >= 0) cursor.text(number) else "",
                            if (emails >= 0) {
                                cursor.text(emails).split(',').map { it.trim() }.filter { it.contains('@') }
                            } else {
                                emptyList()
                            },
                        )
                    }
                }
            } catch (error: SecurityException) {
                if (found.isEmpty()) throw error
            } catch (ignored: Exception) {
                // No SIM, or this slot doesn't exist.
            }
        }
        return found.values.map {
            mapOf("name" to it.name, "number" to it.number, "emails" to it.emails.toList())
        }
    }

    /** The subscription ids of the SIMs that have a contacts phonebook (ADN). */
    private fun simSubscriptionIds(context: Context): List<Int> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return emptyList()
        val ids = linkedSetOf<Int>()
        try {
            context.contentResolver.query(
                SimPhonebookContract.ElementaryFiles.CONTENT_URI,
                arrayOf(
                    SimPhonebookContract.ElementaryFiles.SUBSCRIPTION_ID,
                    SimPhonebookContract.ElementaryFiles.EF_TYPE,
                ),
                null,
                null,
                null,
            )?.use { cursor ->
                while (cursor.moveToNext()) {
                    if (cursor.getInt(1) == SimPhonebookContract.ElementaryFiles.EF_ADN) {
                        ids.add(cursor.getInt(0))
                    }
                }
            }
        } catch (error: SecurityException) {
            throw error
        } catch (ignored: Exception) {
            // Listing isn't supported: use the default SIM below.
        }
        if (ids.isEmpty()) {
            val subId = SubscriptionManager.getDefaultSubscriptionId()
            if (subId != SubscriptionManager.INVALID_SUBSCRIPTION_ID) ids.add(subId)
        }
        return ids.toList()
    }

    private class SimContact(val name: String, val number: String) {
        val emails = linkedSetOf<String>()
    }

    private fun Cursor.text(index: Int): String =
        if (isNull(index)) "" else getString(index).orEmpty()
}
