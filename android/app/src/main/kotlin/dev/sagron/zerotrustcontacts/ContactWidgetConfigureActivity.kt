package dev.sagron.zerotrustcontacts

import android.Manifest
import android.app.Activity
import android.appwidget.AppWidgetManager
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.provider.ContactsContract
import android.view.View
import android.widget.ArrayAdapter
import android.widget.AutoCompleteTextView
import android.widget.Button
import android.widget.ProgressBar
import android.widget.Spinner
import android.widget.TextView
import android.widget.Toast
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat

data class WidgetContactOption(
    val contactId: Long,
    val displayName: String,
    val lookupKey: String?,
    val phoneNumber: String?,
)

data class WidgetContactDropdownItem(
    val contact: WidgetContactOption,
    val label: String,
) {
    override fun toString(): String = label
}

class ContactWidgetConfigureActivity : Activity() {
    private val requestCodeReadContacts = 3001
    private val requestCodeCallPhone = 3002

    private var appWidgetId: Int = AppWidgetManager.INVALID_APPWIDGET_ID
    private val contacts = mutableListOf<WidgetContactOption>()
    private val contactItems = mutableListOf<WidgetContactDropdownItem>()

    private var pendingSelection: WidgetContactOption? = null
    private var pendingMode: String? = null
    private var selectedContact: WidgetContactOption? = null

    private lateinit var statusText: TextView
    private lateinit var progressBar: ProgressBar
    private lateinit var contactDropdown: AutoCompleteTextView
    private lateinit var actionSpinner: Spinner
    private lateinit var saveButton: Button
    private lateinit var cancelButton: Button

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setResult(RESULT_CANCELED)
        appWidgetId = intent?.extras?.getInt(
            AppWidgetManager.EXTRA_APPWIDGET_ID,
            AppWidgetManager.INVALID_APPWIDGET_ID,
        ) ?: AppWidgetManager.INVALID_APPWIDGET_ID
        if (appWidgetId == AppWidgetManager.INVALID_APPWIDGET_ID) {
            finish()
            return
        }

        setContentView(R.layout.contact_widget_configure)
        statusText = findViewById(R.id.configure_status)
        progressBar = findViewById(R.id.configure_progress)
        contactDropdown = findViewById(R.id.configure_contact_dropdown)
        actionSpinner = findViewById(R.id.configure_action_spinner)
        saveButton = findViewById(R.id.configure_save_button)
        cancelButton = findViewById(R.id.configure_cancel_button)
        contactDropdown.setOnClickListener { contactDropdown.showDropDown() }
        contactDropdown.setOnFocusChangeListener { _, hasFocus ->
            if (hasFocus) {
                contactDropdown.showDropDown()
            }
        }

        setupActionSpinner()
        saveButton.setOnClickListener { handleSave() }
        cancelButton.setOnClickListener { finish() }

        loadContacts()
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == requestCodeReadContacts) {
            val granted = grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
            if (!granted) {
                Toast.makeText(
                    this,
                    "Contacts permission is required to configure widget.",
                    Toast.LENGTH_LONG,
                ).show()
                finish()
                return
            }
            loadContacts()
            return
        }

        if (requestCode == requestCodeCallPhone) {
            val selection = pendingSelection
            val mode = pendingMode
            pendingSelection = null
            pendingMode = null
            if (selection != null && mode != null) {
                if (!hasCallPermission()) {
                    Toast.makeText(
                        this,
                        "Call permission denied. Widget will open dialer instead.",
                        Toast.LENGTH_SHORT,
                    ).show()
                }
                completeSave(selection, mode)
            }
        }
    }

    private fun setupActionSpinner() {
        val actionLabels = listOf(
            "Call contact",
            "Open contact details",
        )
        val adapter = ArrayAdapter(
            this,
            android.R.layout.simple_spinner_item,
            actionLabels,
        )
        adapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)
        actionSpinner.adapter = adapter
    }

    private fun loadContacts() {
        if (!hasReadContactsPermission()) {
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.READ_CONTACTS),
                requestCodeReadContacts,
            )
            return
        }

        showLoadingUi(true)
        val projection = arrayOf(
            ContactsContract.Contacts._ID,
            ContactsContract.Contacts.LOOKUP_KEY,
            ContactsContract.Contacts.DISPLAY_NAME_PRIMARY,
            ContactsContract.Contacts.HAS_PHONE_NUMBER,
        )
        val loadedContacts = mutableListOf<WidgetContactOption>()

        contentResolver.query(
            ContactsContract.Contacts.CONTENT_URI,
            projection,
            null,
            null,
            "${ContactsContract.Contacts.DISPLAY_NAME_PRIMARY} COLLATE NOCASE ASC",
        )?.use { cursor ->
            val idIndex = cursor.getColumnIndexOrThrow(
                ContactsContract.Contacts._ID,
            )
            val lookupKeyIndex = cursor.getColumnIndexOrThrow(
                ContactsContract.Contacts.LOOKUP_KEY,
            )
            val displayNameIndex = cursor.getColumnIndexOrThrow(
                ContactsContract.Contacts.DISPLAY_NAME_PRIMARY,
            )
            val hasPhoneIndex = cursor.getColumnIndexOrThrow(
                ContactsContract.Contacts.HAS_PHONE_NUMBER,
            )

            while (cursor.moveToNext()) {
                val contactId = cursor.getLong(idIndex)
                if (contactId <= 0L) {
                    continue
                }

                val displayName = cursor.getString(displayNameIndex)?.trim().orEmpty()
                val lookupKey = cursor.getString(lookupKeyIndex)?.trim()
                val hasPhoneNumber = cursor.getInt(hasPhoneIndex) > 0
                val phone = if (hasPhoneNumber) {
                    readPrimaryPhoneNumber(contactId)
                } else {
                    null
                }
                loadedContacts.add(
                    WidgetContactOption(
                        contactId = contactId,
                        displayName = if (displayName.isNotEmpty()) {
                            displayName
                        } else {
                            "Unnamed Contact"
                        },
                        lookupKey = lookupKey,
                        phoneNumber = phone,
                    ),
                )
            }
        }

        contacts.clear()
        contacts.addAll(loadedContacts)
        selectedContact = null
        if (contacts.isEmpty()) {
            showLoadingUi(false)
            statusText.text = "No contacts were found."
            saveButton.isEnabled = false
            return
        }

        contactItems.clear()
        contactItems.addAll(contacts.map { contact ->
            WidgetContactDropdownItem(
                contact = contact,
                label = buildContactLabel(contact),
            )
        })
        val adapter = ArrayAdapter(
            this,
            android.R.layout.simple_dropdown_item_1line,
            contactItems,
        )
        contactDropdown.setAdapter(adapter)
        contactDropdown.setOnItemClickListener { parent, _, position, _ ->
            val item = parent.getItemAtPosition(position) as? WidgetContactDropdownItem
            selectedContact = item?.contact
        }
        val initialSelection = contactItems.firstOrNull()
        if (initialSelection != null) {
            selectedContact = initialSelection.contact
            contactDropdown.setText(initialSelection.label, false)
        }
        showLoadingUi(false)
        statusText.text = "Pick a contact and widget action."
    }

    private fun readPrimaryPhoneNumber(contactId: Long): String? {
        val projection = arrayOf(ContactsContract.CommonDataKinds.Phone.NUMBER)
        val selection = "${ContactsContract.CommonDataKinds.Phone.CONTACT_ID} = ?"
        val selectionArgs = arrayOf(contactId.toString())

        contentResolver.query(
            ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
            projection,
            selection,
            selectionArgs,
            null,
        )?.use { cursor ->
            val numberIndex = cursor.getColumnIndexOrThrow(
                ContactsContract.CommonDataKinds.Phone.NUMBER,
            )
            while (cursor.moveToNext()) {
                val number = cursor.getString(numberIndex)?.trim()
                if (!number.isNullOrBlank()) {
                    return number
                }
            }
        }
        return null
    }

    private fun handleSave() {
        val selection = resolveSelectedContact()
        if (selection == null) {
            Toast.makeText(this, "Please select a contact.", Toast.LENGTH_SHORT).show()
            return
        }
        val mode = if (actionSpinner.selectedItemPosition == 0) {
            ContactQuickWidgetProvider.ACTION_MODE_CALL
        } else {
            ContactQuickWidgetProvider.ACTION_MODE_DETAILS
        }
        if (mode == ContactQuickWidgetProvider.ACTION_MODE_CALL &&
            selection.phoneNumber.isNullOrBlank()
        ) {
            Toast.makeText(
                this,
                "This contact has no phone number to call.",
                Toast.LENGTH_SHORT,
            ).show()
            return
        }

        if (mode == ContactQuickWidgetProvider.ACTION_MODE_CALL && !hasCallPermission()) {
            pendingSelection = selection
            pendingMode = mode
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.CALL_PHONE),
                requestCodeCallPhone,
            )
            return
        }

        completeSave(selection, mode)
    }

    private fun completeSave(selection: WidgetContactOption, mode: String) {
        val lookupUri = if (!selection.lookupKey.isNullOrBlank()) {
            ContactsContract.Contacts.getLookupUri(
                selection.contactId,
                selection.lookupKey,
            )?.toString()
        } else {
            null
        }

        ContactQuickWidgetProvider.saveConfiguration(
            context = this,
            appWidgetId = appWidgetId,
            contactId = selection.contactId,
            contactName = selection.displayName,
            phoneNumber = selection.phoneNumber,
            lookupUri = lookupUri,
            actionMode = mode,
        )

        val appWidgetManager = AppWidgetManager.getInstance(this)
        ContactQuickWidgetProvider.updateAppWidget(this, appWidgetManager, appWidgetId)

        val resultValue = Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
        setResult(RESULT_OK, resultValue)
        finish()
    }

    private fun showLoadingUi(isLoading: Boolean) {
        progressBar.visibility = if (isLoading) View.VISIBLE else View.GONE
        contactDropdown.visibility = if (isLoading) View.GONE else View.VISIBLE
        actionSpinner.visibility = if (isLoading) View.GONE else View.VISIBLE
        contactDropdown.isEnabled = !isLoading
        saveButton.isEnabled = !isLoading
    }

    private fun buildContactLabel(contact: WidgetContactOption): String {
        return if (contact.phoneNumber.isNullOrBlank()) {
            contact.displayName
        } else {
            "${contact.displayName} (${contact.phoneNumber})"
        }
    }

    private fun resolveSelectedContact(): WidgetContactOption? {
        val typedText = contactDropdown.text?.toString()?.trim().orEmpty()
        if (typedText.isBlank()) {
            return selectedContact
        }
        val typedMatch = contactItems.firstOrNull { item ->
            item.label.equals(typedText, ignoreCase = true)
        }?.contact
        if (typedMatch != null) {
            return typedMatch
        }
        return selectedContact?.takeIf { contact ->
            buildContactLabel(contact).equals(typedText, ignoreCase = true)
        }
    }

    private fun hasReadContactsPermission(): Boolean {
        return ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.READ_CONTACTS,
        ) == PackageManager.PERMISSION_GRANTED
    }

    private fun hasCallPermission(): Boolean {
        return ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.CALL_PHONE,
        ) == PackageManager.PERMISSION_GRANTED
    }
}
