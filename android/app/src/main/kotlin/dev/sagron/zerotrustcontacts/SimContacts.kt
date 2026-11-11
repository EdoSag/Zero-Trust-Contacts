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
        val found = linkedMapOf<String, Map<String, Any>>()
        fun add(name: String, number: String, emails: List<String>) {
            val n = name.trim()
            val p = number.trim()
            if (n.isEmpty() && p.isEmpty()) return
            val key = "$n\n${p.filter { it.isDigit() || it == '+' }}"
            if (key !in found) {
                found[key] = mapOf("name" to n, "number" to p, "emails" to emails)
            }
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            // Android 12+: the official SIM phonebook, for the default SIM.
            val subId = SubscriptionManager.getDefaultSubscriptionId()
            if (subId != SubscriptionManager.INVALID_SUBSCRIPTION_ID) {
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
                    // Not supported on this phone: fall back below.
                }
            }
        }

        // The older provider most phones still have (also covers dual-SIM
        // phones where the default SIM above is empty).
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
        return found.values.toList()
    }

    private fun Cursor.text(index: Int): String =
        if (isNull(index)) "" else getString(index).orEmpty()
}
