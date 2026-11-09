package dev.sagron.zerotrustcontacts

import android.accounts.Account
import android.app.Service
import android.content.AbstractThreadedSyncAdapter
import android.content.ContentProviderClient
import android.content.Context
import android.content.Intent
import android.content.SyncResult
import android.os.Bundle
import android.os.IBinder

/**
 * Declares the ZT Contacts account to the contacts system (with
 * res/xml/zt_contacts.xml), so contacts apps show its contacts read-only.
 * It never syncs anything itself: the app writes the contacts while it's
 * unlocked, because only then can it decrypt them.
 */
class ZtContactsSyncService : Service() {
    private lateinit var adapter: Adapter

    override fun onCreate() {
        adapter = Adapter(applicationContext)
    }

    override fun onBind(intent: Intent?): IBinder = adapter.syncAdapterBinder

    private class Adapter(context: Context) : AbstractThreadedSyncAdapter(context, true) {
        override fun onPerformSync(
            account: Account?,
            extras: Bundle?,
            authority: String?,
            provider: ContentProviderClient?,
            syncResult: SyncResult?,
        ) = Unit
    }
}
