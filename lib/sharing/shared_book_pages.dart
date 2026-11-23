import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_contacts/app/providers.dart';
import 'package:zerotrust_contacts/app/text_direction.dart';
import 'package:zerotrust_contacts/l10n/l10n.dart';
import 'package:zerotrust_contacts/models/vault_contact.dart';
import 'package:zerotrust_contacts/pages/create_contact_page.dart';
import 'package:zerotrust_contacts/services/contact_actions.dart';
import 'package:zerotrust_contacts/sharing/shared_books.dart';
import 'package:zerotrust_contacts/widgets/contact_avatar.dart';
import 'package:zt_sharing_ui/zt_sharing_ui.dart';

// The people, invite, join and code-compare screens are Core's shared ones
// (zt_sharing_ui), so every Zero-Trust app shows the same. Only what is
// about address books lives here.

void _snack(BuildContext context, String text) {
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(
        SnackBar(content: Text(text), duration: const Duration(seconds: 4)));
}

String _bookName(WidgetRef ref, String spaceId) =>
    ref.read(sharedBooksProvider)[spaceId]?.name ?? '';

/// The people screen of the book in [spaceId]: members, invite, leave.
Future<void> openBookPeople(BuildContext context, WidgetRef ref, String spaceId,
        {bool inviteNow = false}) =>
    ZtSpacePage.open(
      context,
      spaceId: spaceId,
      title: _bookName(ref, spaceId),
      description: context.l10n.sharedBookE2e,
      inviteNow: inviteNow,
    );

/// Joins a shared address book from an invite link (pasted, scanned or
/// opened from a message).
Future<void> joinSharedBook(BuildContext context, {String? initialLink}) =>
    ZtJoinSpacePage.open(context, initialLink: initialLink);

/// A new shared address book, optionally with copies of [contacts].
Future<String?> newSharedBook(
  BuildContext context,
  WidgetRef ref, {
  List<VaultContact> contacts = const <VaultContact>[],
}) async {
  final AppL10n l = context.l10n;
  final String? bookName = await showDialog<String>(
    context: context,
    builder: (_) => _NameDialog(title: l.newSharedBook, label: l.bookName),
  );
  if (bookName == null || !context.mounted) return null;
  final String? myName =
      await ztAskSharingName(context, ref, title: l.newSharedBook);
  if (myName == null || !context.mounted) return null;
  try {
    final String spaceId = await ref
        .read(sharedBooksProvider.notifier)
        .create(bookName, myName: myName, contacts: contacts);
    if (context.mounted) {
      await openBookPeople(context, ref, spaceId, inviteNow: true);
    }
    return spaceId;
  } on Object {
    if (context.mounted) _snack(context, l.sharingNeedsInternet);
    return null;
  }
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.title, required this.label, this.initial = ''});
  final String title;
  final String label;
  final String initial;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _name =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    if (_name.text.trim().isEmpty) return;
    Navigator.pop(context, _name.text.trim());
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: TextField(
          key: const Key('shared_book_name'),
          controller: _name,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(labelText: widget.label),
          onSubmitted: (_) => _submit(),
        ),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.l10n.cancel)),
          TextButton(onPressed: _submit, child: Text(context.l10n.save)),
        ],
      );
}

/// Every shared address book of the account, people waiting to join one
/// it owns, and New / Join.
class SharedBooksPage extends ConsumerWidget {
  const SharedBooksPage({super.key, required this.myContacts});

  /// The account's own contacts, to copy into a book.
  final List<VaultContact> myContacts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppL10n l = context.l10n;
    final SharedBooksState state = ref.watch(sharedBooksProvider);
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.sharedBooks),
        actions: <Widget>[
          IconButton(
            key: const Key('join_shared_book'),
            tooltip: l.joinSharedBook,
            icon: const Icon(Icons.group_add_outlined),
            onPressed: () => joinSharedBook(context),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('new_shared_book'),
        onPressed: state.available ? () => newSharedBook(context, ref) : null,
        icon: const Icon(Icons.add),
        label: Text(l.newSharedBook),
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 96),
        children: <Widget>[
          ZtJoinRequestCards(titleOf: (String id) => _bookName(ref, id)),
          if (state.books.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                state.ready && !state.available
                    ? l.sharingNeedsInternet
                    : l.sharedBooksEmpty,
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.onSurfaceVariant),
              ),
            ),
          for (final SharedBook book in state.books)
            ListTile(
              key: Key('shared_book_${book.spaceId}'),
              leading: const CircleAvatar(child: Icon(Icons.contacts_outlined)),
              title: Text(book.waiting ? l.waitingToJoin : book.name),
              subtitle: Text(book.waiting
                  ? (book.joinCode == null
                      ? l.waitingToJoinHint
                      : l.waitingToJoinCode(book.joinCode!))
                  : l.sharedBookSummary(
                      book.contacts.length, book.members.length)),
              trailing: const Icon(Icons.chevron_right),
              onTap: book.waiting
                  ? null
                  : () => Navigator.of(context).push(MaterialPageRoute<void>(
                        builder: (_) => SharedBookPage(
                            spaceId: book.spaceId, myContacts: myContacts),
                      )),
            ),
        ],
      ),
    );
  }
}

/// One shared address book: its contacts, add one, copy some in, people.
class SharedBookPage extends ConsumerStatefulWidget {
  const SharedBookPage(
      {super.key, required this.spaceId, required this.myContacts});

  final String spaceId;
  final List<VaultContact> myContacts;

  @override
  ConsumerState<SharedBookPage> createState() => _SharedBookPageState();
}

class _SharedBookPageState extends ConsumerState<SharedBookPage> {
  String _query = '';

  SharedBooksController get _books => ref.read(sharedBooksProvider.notifier);

  Future<void> _add() async {
    await Navigator.of(context).push<VaultContact>(MaterialPageRoute<VaultContact>(
      builder: (_) => CreateContactPage(
        saveTo: (VaultContact c) => _books.saveContact(widget.spaceId, c),
      ),
    ));
  }

  Future<void> _copyIn(SharedBook book) async {
    final List<VaultContact>? picked = await Navigator.of(context)
        .push<List<VaultContact>>(MaterialPageRoute<List<VaultContact>>(
      builder: (_) => _PickContactsPage(
        contacts: <VaultContact>[
          for (final VaultContact c in widget.myContacts)
            if (!c.isBlocked) c,
        ],
      ),
    ));
    if (picked == null || picked.isEmpty || !mounted) return;
    try {
      for (final VaultContact c in picked) {
        // A copy: changing it here doesn't change the account's own one.
        await _books.saveContact(widget.spaceId, _copyOf(c));
      }
      if (mounted) _snack(context, context.l10n.copiedToBook(picked.length));
    } on Object {
      if (mounted) _snack(context, context.l10n.sharingNeedsInternet);
    }
  }

  Future<void> _rename(SharedBook book) async {
    final String? name = await showDialog<String>(
      context: context,
      builder: (_) => _NameDialog(
          title: context.l10n.renameBook,
          label: context.l10n.bookName,
          initial: book.name),
    );
    if (name == null || !mounted) return;
    try {
      await _books.rename(widget.spaceId, name);
    } on Object {
      if (mounted) _snack(context, context.l10n.sharingNeedsInternet);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppL10n l = context.l10n;
    final SharedBook? book = ref.watch(sharedBooksProvider)[widget.spaceId];
    if (book == null) {
      // Left, deleted, or this account was removed.
      return Scaffold(
        appBar: AppBar(),
        body: Center(child: Text(l.sharedBookGone)),
      );
    }
    final String q = _query.trim().toLowerCase();
    final String digits = q.replaceAll(RegExp(r'\D'), '');
    final List<VaultContact> shown = <VaultContact>[
      for (final VaultContact c in book.contacts)
        if (q.isEmpty ||
            c.displayName.toLowerCase().contains(q) ||
            c.company.toLowerCase().contains(q) ||
            (digits.isNotEmpty &&
                c.phones.any((String p) =>
                    p.replaceAll(RegExp(r'\D'), '').contains(digits))))
          c,
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(book.name),
        actions: <Widget>[
          IconButton(
            key: const Key('shared_book_people'),
            tooltip: l.sharedBookPeople,
            icon: const Icon(Icons.group_outlined),
            onPressed: () => openBookPeople(context, ref, widget.spaceId),
          ),
          PopupMenuButton<String>(
            onSelected: (String v) => switch (v) {
              'copy' => _copyIn(book),
              'rename' => _rename(book),
              _ => null,
            },
            itemBuilder: (_) => <PopupMenuEntry<String>>[
              PopupMenuItem<String>(
                  value: 'copy', child: Text(l.copyMyContactsIn)),
              if (book.isAdmin)
                PopupMenuItem<String>(value: 'rename', child: Text(l.renameBook)),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        key: const Key('shared_book_add'),
        tooltip: l.addContact,
        onPressed: _add,
        child: const Icon(Icons.person_add_alt),
      ),
      body: Column(
        children: <Widget>[
          ListTile(
            dense: true,
            leading: const Icon(Icons.lock_outline),
            title: Text(l.sharedWith(
                book.members.map((SpaceMember m) => m.name).join(', '))),
            subtitle: Text(l.sharedBookE2e),
            onTap: () => openBookPeople(context, ref, widget.spaceId),
          ),
          if (book.contacts.length > 8)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: l.searchThisBook,
                ),
                onChanged: (String v) => setState(() => _query = v),
              ),
            ),
          Expanded(
            child: book.contacts.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(l.sharedBookEmpty, textAlign: TextAlign.center),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 96),
                    itemCount: shown.length,
                    itemBuilder: (_, int i) {
                      final VaultContact c = shown[i];
                      return ListTile(
                        leading: ContactAvatar(contact: c, radius: 20),
                        title: Text(c.displayName),
                        subtitle: c.phones.isEmpty && c.company.isEmpty
                            ? null
                            : Text(
                                c.phones.isNotEmpty ? c.phones.first : c.company,
                                textDirection: c.phones.isNotEmpty
                                    ? TextDirection.ltr
                                    : null,
                              ),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => SharedContactPage(
                                spaceId: widget.spaceId, contactId: c.id),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// A copy of one of the account's contacts with its own id, so the shared
/// one and the account's own one change separately.
VaultContact _copyOf(VaultContact c) => VaultContact.fromJson(
    <String, dynamic>{...c.toJson(), 'id': VaultContact.generateId()});

/// A contact in a shared book: details with call, text, email and
/// directions; edit, save to my contacts, remove from the book.
class SharedContactPage extends ConsumerWidget {
  const SharedContactPage(
      {super.key, required this.spaceId, required this.contactId});

  final String spaceId;
  final String contactId;

  Future<void> _open(BuildContext context, Uri? uri) async {
    if (uri == null) return;
    bool opened = false;
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on Object {
      opened = false;
    }
    if (!opened && context.mounted) {
      _snack(context, context.l10n.noAppOnThisPhone);
    }
  }

  Future<void> _copy(BuildContext context, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (context.mounted) _snack(context, context.l10n.copied);
  }

  Future<void> _saveToMine(
      BuildContext context, WidgetRef ref, VaultContact c) async {
    try {
      await requireRepository(ref)
          .upsertSavedContact(_copyOf(c), activity: 'contact_create');
      if (context.mounted) _snack(context, context.l10n.savedToMyContacts);
    } on Object catch (e) {
      if (context.mounted) _snack(context, context.l10n.failedToSaveContact('$e'));
    }
  }

  Future<void> _remove(
      BuildContext context, WidgetRef ref, VaultContact c, String book) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(ctx.l10n.removeFromBookQ(c.displayName)),
        content: Text(ctx.l10n.removeFromBookBody(book)),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(ctx.l10n.cancel)),
          TextButton(
              key: const Key('shared_contact_remove_ok'),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(ctx.l10n.remove)),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await ref.read(sharedBooksProvider.notifier).deleteContact(spaceId, c.id);
      if (context.mounted) Navigator.of(context).pop();
    } on Object {
      if (context.mounted) _snack(context, context.l10n.sharingNeedsInternet);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppL10n l = context.l10n;
    final SharedBook? book = ref.watch(sharedBooksProvider)[spaceId];
    VaultContact? c;
    for (final VaultContact x in book?.contacts ?? const <VaultContact>[]) {
      if (x.id == contactId) c = x;
    }
    if (book == null || c == null) {
      return Scaffold(
          appBar: AppBar(), body: Center(child: Text(l.sharedContactGone)));
    }
    final VaultContact contact = c;
    final bool isIOS = Theme.of(context).platform == TargetPlatform.iOS;
    return Scaffold(
      appBar: AppBar(
        title: Text(contact.displayName),
        actions: <Widget>[
          IconButton(
            key: const Key('shared_contact_edit'),
            tooltip: l.edit,
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<VaultContact>(
                builder: (_) => CreateContactPage(
                  existing: contact,
                  saveTo: (VaultContact edited) => ref
                      .read(sharedBooksProvider.notifier)
                      .saveContact(spaceId, edited),
                ),
              ),
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (String v) => switch (v) {
              'mine' => _saveToMine(context, ref, contact),
              'remove' => _remove(context, ref, contact, book.name),
              _ => null,
            },
            itemBuilder: (_) => <PopupMenuEntry<String>>[
              PopupMenuItem<String>(value: 'mine', child: Text(l.saveToMyContacts)),
              PopupMenuItem<String>(value: 'remove', child: Text(l.removeFromBook)),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Center(child: ContactAvatar(contact: contact, radius: 40)),
          const SizedBox(height: 8),
          Center(
            child: Text(l.inSharedBook(book.name),
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
          const SizedBox(height: 8),
          for (final String phone in contact.phones)
            ListTile(
              leading: const Icon(Icons.phone_outlined),
              title: Align(
                alignment: AlignmentDirectional.centerStart,
                heightFactor: 1,
                child: Text(phone, textDirection: TextDirection.ltr),
              ),
              subtitle: Text(contact.typeLabel('phone', phone, fallback: l.phoneLabel)),
              onTap: () => _open(context, ContactActions.call(phone)),
              onLongPress: () => _copy(context, phone),
              trailing: IconButton(
                tooltip: l.textNumber(phone),
                icon: const Icon(Icons.sms_outlined),
                onPressed: () => _open(context, ContactActions.text(phone)),
              ),
            ),
          for (final String email in contact.emails)
            ListTile(
              leading: const Icon(Icons.email_outlined),
              title: Align(
                alignment: AlignmentDirectional.centerStart,
                heightFactor: 1,
                child: Text(email, textDirection: TextDirection.ltr),
              ),
              subtitle: Text(contact.typeLabel('email', email, fallback: l.email)),
              onTap: () => _open(context, ContactActions.email(email)),
              onLongPress: () => _copy(context, email),
            ),
          for (final String address in contact.addresses)
            ListTile(
              leading: const Icon(Icons.place_outlined),
              title: Text(address),
              subtitle: Text(contact.typeLabel('address', address, fallback: l.address)),
              onTap: () => _open(
                  context, ContactActions.directions(address, isIOS: isIOS)),
              onLongPress: () => _copy(context, address),
              trailing: const Icon(Icons.directions_outlined),
            ),
          if (contact.company.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.apartment_outlined),
              title: Text(contact.company),
              subtitle: Text(l.company),
            ),
          for (final String birthday in contact.birthdays)
            ListTile(
              leading: const Icon(Icons.cake_outlined),
              title: Text(birthday),
              subtitle: Text(l.birthday),
            ),
          if (contact.notes.isNotEmpty) ...<Widget>[
            const SizedBox(height: 16),
            Text(l.notes, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            SelectableText(contact.notes,
                textDirection: directionOf(contact.notes)),
          ],
        ],
      ),
    );
  }
}

/// Picks some of the account's own contacts to copy into a book.
class _PickContactsPage extends StatefulWidget {
  const _PickContactsPage({required this.contacts});
  final List<VaultContact> contacts;

  @override
  State<_PickContactsPage> createState() => _PickContactsPageState();
}

class _PickContactsPageState extends State<_PickContactsPage> {
  final Set<String> _picked = <String>{};
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final AppL10n l = context.l10n;
    final String q = _query.trim().toLowerCase();
    final List<VaultContact> shown = <VaultContact>[
      for (final VaultContact c in widget.contacts)
        if (q.isEmpty || c.displayName.toLowerCase().contains(q)) c,
    ]..sort((VaultContact a, VaultContact b) =>
        a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
    return Scaffold(
      appBar: AppBar(
        title: Text(l.copyMyContactsIn),
        actions: <Widget>[
          TextButton(
            key: const Key('shared_book_copy_done'),
            onPressed: _picked.isEmpty
                ? null
                : () => Navigator.of(context).pop(<VaultContact>[
                      for (final VaultContact c in widget.contacts)
                        if (_picked.contains(c.id)) c,
                    ]),
            child: Text(l.copyN(_picked.length)),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search), hintText: l.search),
              onChanged: (String v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: shown.length,
              itemBuilder: (_, int i) {
                final VaultContact c = shown[i];
                return CheckboxListTile(
                  value: _picked.contains(c.id),
                  onChanged: (bool? on) => setState(() =>
                      on == true ? _picked.add(c.id) : _picked.remove(c.id)),
                  secondary: ContactAvatar(contact: c, radius: 18),
                  title: Text(c.displayName),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
