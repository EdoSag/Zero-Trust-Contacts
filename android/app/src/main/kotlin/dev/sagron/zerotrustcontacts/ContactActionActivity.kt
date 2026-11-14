package dev.sagron.zerotrustcontacts

import android.Manifest
import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Bundle
import android.provider.ContactsContract
import androidx.core.content.ContextCompat

/**
 * Carries out a tap on a contact widget (call, message, or open the contact)
 * and closes at once. Widgets start it directly, as an activity, so the call
 * screen or messages app may open from the home screen; a broadcast receiver
 * is not always allowed to start them on newer Android. Not exported: only
 * this app's widgets can start it.
 */
class ContactActionActivity : Activity() {
    companion object {
        const val EXTRA_ACTION = "zt_contact_action"
        const val EXTRA_PHONE = "zt_contact_phone"
        const val EXTRA_LOOKUP = "zt_contact_lookup"
        const val EXTRA_CONTACT_ID = "zt_contact_id"
        const val ACTION_CALL = "call"
        const val ACTION_MESSAGE = "message"
        const val ACTION_OPEN = "open"

        /** The intent a widget tap starts for [action] on this contact. */
        fun intent(context: Context, action: String, phone: String?, contactId: Long, lookupUri: String?): Intent =
            Intent(context, ContactActionActivity::class.java)
                .putExtra(EXTRA_ACTION, action)
                .putExtra(EXTRA_PHONE, phone)
                .putExtra(EXTRA_CONTACT_ID, contactId)
                .putExtra(EXTRA_LOOKUP, lookupUri)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val phone = intent.getStringExtra(EXTRA_PHONE)?.trim().orEmpty()
        val action = intent.getStringExtra(EXTRA_ACTION) ?: ACTION_OPEN
        val target = when {
            action == ACTION_CALL && phone.isNotEmpty() -> {
                val canCall = ContextCompat.checkSelfPermission(this, Manifest.permission.CALL_PHONE) ==
                    PackageManager.PERMISSION_GRANTED
                Intent(if (canCall) Intent.ACTION_CALL else Intent.ACTION_DIAL, Uri.parse("tel:" + Uri.encode(phone)))
            }
            action == ACTION_MESSAGE && phone.isNotEmpty() ->
                Intent(Intent.ACTION_SENDTO, Uri.parse("smsto:" + Uri.encode(phone)))
            else -> openContact()
        }
        try {
            startActivity(target)
        } catch (e: ActivityNotFoundException) {
            try {
                startActivity(openContact())
            } catch (ignored: ActivityNotFoundException) {
                // Nothing on the phone can open it.
            }
        } catch (e: SecurityException) {
            // Call permission taken away meanwhile: let the dialer ask.
            if (phone.isNotEmpty()) startActivity(Intent(Intent.ACTION_DIAL, Uri.parse("tel:" + Uri.encode(phone))))
        }
        finish()
    }

    private fun openContact(): Intent {
        val lookup = intent.getStringExtra(EXTRA_LOOKUP)?.let { Uri.parse(it) }
        val id = intent.getLongExtra(EXTRA_CONTACT_ID, -1L)
        val uri = lookup
            ?: if (id > 0) android.content.ContentUris.withAppendedId(ContactsContract.Contacts.CONTENT_URI, id) else null
        return Intent(Intent.ACTION_VIEW, uri ?: ContactsContract.Contacts.CONTENT_URI)
    }
}
