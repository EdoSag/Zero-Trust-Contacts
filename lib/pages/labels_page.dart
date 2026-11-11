import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:zerotrust_contacts/app/contact_sorting.dart';
import 'package:zerotrust_contacts/app/providers.dart';
import 'package:zerotrust_contacts/app/text_direction.dart';
import 'package:zerotrust_contacts/models/vault_contact.dart';
import 'package:zerotrust_contacts/pages/contact_detail_page.dart';
import 'package:zerotrust_contacts/services/contact_actions.dart';
import 'package:zerotrust_contacts/services/vault_repository.dart';
import 'package:zerotrust_contacts/widgets/contact_avatar.dart';
import 'package:zerotrust_contacts/l10n/l10n.dart';

bool _hasLabel(VaultContact contact, String label) => contact.labels.any(
  (String l) => l.trim().toLowerCase() == label.trim().toLowerCase(),
);

List<VaultContact> _sorted(Iterable<VaultContact> contacts) =>
    contacts.toList()..sort(
      (VaultContact a, VaultContact b) => ContactSorting.compareNames(
        ContactSorting.sortName(a),
        ContactSorting.sortName(b),
      ),
    );

Future<String?> _askLabelName(
  BuildContext context, {
  required String title,
  required String action,
  String initial = '',
}) async {
  final TextEditingController controller = TextEditingController(text: initial);
  final String? name = await showDialog<String>(
    context: context,
    builder: (BuildContext context) => AlertDialog(
      title: Text(title),
      content: DirectionalTextField(
        controller: controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(labelText: context.l10n.labelName),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(controller.text),
          child: Text(action),
        ),
      ],
    ),
  );
  final String clean = name?.trim() ?? '';
  return clean.isEmpty ? null : clean;
}

/// All labels (groups) with how many contacts each has. Labels live on the
/// contacts themselves, so they sync and stay encrypted like everything
/// else; a label exists as long as one contact has it.
class LabelsPage extends ConsumerStatefulWidget {
  const LabelsPage({super.key});

  @override
  ConsumerState<LabelsPage> createState() => _LabelsPageState();
}

class _LabelsPageState extends ConsumerState<LabelsPage> {
  late final VaultRepository _repo = requireRepository(ref);
  StreamSubscription<Set<String>>? _changes;
  List<VaultContact>? _contacts;

  @override
  void initState() {
    super.initState();
    _changes = _repo.changes.listen((_) => _load());
    _load();
  }

  @override
  void dispose() {
    _changes?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final List<VaultContact> contacts = await _repo.loadSavedContacts();
    if (mounted) setState(() => _contacts = contacts);
  }

  void _snack(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  Future<void> _create() async {
    final List<VaultContact> contacts = _contacts ?? <VaultContact>[];
    if (contacts.isEmpty) {
      _snack(context.l10n.addAContactFirstThen);
      return;
    }
    final String? name = await _askLabelName(
      context,
      title: context.l10n.newLabelX,
      action: context.l10n.next,
    );
    if (name == null || !mounted) return;
    final Set<String>? picked = await Navigator.of(context).push<Set<String>>(
      MaterialPageRoute<Set<String>>(
        builder: (_) => LabelMembersPicker(
          title: context.l10n.addToLabel(name),
          contacts: contacts
              .where((VaultContact c) => !_hasLabel(c, name))
              .toList(),
        ),
      ),
    );
    if (picked == null || picked.isEmpty || !mounted) return;
    final int added = await _repo.addLabel(picked, name);
    await _load();
    if (mounted) {
      _snack(currentL10n.labelNowHas(name, _count(added)));
    }
  }

  String _count(int n) => currentL10n.nContacts(n);

  @override
  Widget build(BuildContext context) {
    final List<VaultContact>? contacts = _contacts;
    final Map<String, int> counts = contacts == null
        ? <String, int>{}
        : _repo.labelCounts(contacts);
    final List<String> names = counts.keys.toList()
      ..sort(ContactSorting.compareNames);
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.labels)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: contacts == null ? null : _create,
        icon: const Icon(Icons.new_label_outlined),
        label: Text(context.l10n.newLabelX),
      ),
      body: contacts == null
          ? const Center(child: CircularProgressIndicator())
          : names.isEmpty
          ? Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  context.l10n.noLabelsYetMakeOne,
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: 96),
              itemCount: names.length,
              itemBuilder: (BuildContext context, int index) {
                final String name = names[index];
                return ListTile(
                  leading: const Icon(Icons.label_outline),
                  title: Text(name, textDirection: directionOf(name)),
                  subtitle: Text(_count(counts[name]!)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => LabelDetailPage(label: name),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

/// One label: who is in it, and the things you can do with all of them.
class LabelDetailPage extends ConsumerStatefulWidget {
  const LabelDetailPage({super.key, required this.label});

  final String label;

  @override
  ConsumerState<LabelDetailPage> createState() => _LabelDetailPageState();
}

class _LabelDetailPageState extends ConsumerState<LabelDetailPage> {
  late final VaultRepository _repo = requireRepository(ref);
  late String _label = widget.label;
  StreamSubscription<Set<String>>? _changes;
  List<VaultContact>? _all;
  final Set<String> _selected = <String>{};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _changes = _repo.changes.listen((_) => _load());
    _load();
  }

  @override
  void dispose() {
    _changes?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final List<VaultContact> all = await _repo.loadSavedContacts();
    if (!mounted) return;
    setState(() {
      _all = all;
      final Set<String> ids = <String>{
        for (final VaultContact c in all)
          if (_hasLabel(c, _label)) c.id,
      };
      _selected.removeWhere((String id) => !ids.contains(id));
    });
  }

  List<VaultContact> get _members => _sorted(
    (_all ?? <VaultContact>[]).where((VaultContact c) => _hasLabel(c, _label)),
  );

  void _snack(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  String _count(int n) => currentL10n.nContacts(n);

  Future<void> _run(Future<String?> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final String? message = await action();
      await _load();
      if (mounted && message != null) _snack(message);
    } on Object catch (error) {
      if (mounted) _snack(currentL10n.thatDidntWork('$error'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _rename() async {
    final String? name = await _askLabelName(
      context,
      title: context.l10n.renameLabel,
      action: context.l10n.rename,
      initial: _label,
    );
    if (name == null || name == _label || !mounted) return;
    await _run(() async {
      await _repo.renameLabel(_label, name);
      _label = name;
      return currentL10n.renamedTo(name);
    });
  }

  Future<void> _delete() async {
    final bool ok =
        await showDialog<bool>(
          context: context,
          builder: (BuildContext context) => AlertDialog(
            title: Text(context.l10n.deleteTheLabel(_label)),
            content: Text(
              context.l10n.theContactsStayOnlyThe,
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(context.l10n.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(context.l10n.deleteLabel),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok || !mounted) return;
    final NavigatorState navigator = Navigator.of(context);
    setState(() => _busy = true);
    try {
      await _repo.removeLabel(_label);
      navigator.pop();
    } on Object catch (error) {
      if (mounted) {
        setState(() => _busy = false);
        _snack(currentL10n.thatDidntWork('$error'));
      }
    }
  }

  Future<void> _addMembers() async {
    final List<VaultContact> others = (_all ?? <VaultContact>[])
        .where((VaultContact c) => !_hasLabel(c, _label))
        .toList();
    if (others.isEmpty) {
      _snack(context.l10n.everyContactAlreadyHasThis);
      return;
    }
    final Set<String>? picked = await Navigator.of(context).push<Set<String>>(
      MaterialPageRoute<Set<String>>(
        builder: (_) =>
            LabelMembersPicker(title: context.l10n.addToLabel(_label), contacts: others),
      ),
    );
    if (picked == null || picked.isEmpty || !mounted) return;
    await _run(() async {
      final int added = await _repo.addLabel(picked, _label);
      return currentL10n.addedContacts(_count(added));
    });
  }

  Future<void> _removeSelected() => _run(() async {
    final int removed = await _repo.removeLabel(
      _label,
      ids: _selected.toList(),
    );
    _selected.clear();
    return currentL10n.tookOutOf(_count(removed), _label);
  });

  Future<void> _open(Uri? uri, String nothing, String failed) async {
    if (uri == null) {
      _snack(nothing);
      return;
    }
    bool opened = false;
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on Object {
      opened = false;
    }
    if (mounted && !opened) _snack(failed);
  }

  /// The selected people, or everyone in the label when none are selected.
  List<VaultContact> get _audience => _selected.isEmpty
      ? _members
      : _members.where((VaultContact c) => _selected.contains(c.id)).toList();

  Future<void> _emailAll() => _open(
    ContactActions.emailGroup(<String>[
      for (final VaultContact c in _audience)
        if (c.emails.isNotEmpty) c.emails.first,
    ]),
    context.l10n.nobodyHereHasAnEmail,
    context.l10n.noMailAppCouldBe,
  );

  Future<void> _textAll() => _open(
    ContactActions.textGroup(<String>[
      for (final VaultContact c in _audience)
        if (c.phones.isNotEmpty) c.phones.first,
    ], isIOS: Platform.isIOS),
    context.l10n.nobodyHereHasAPhone,
    context.l10n.noMessagesAppCouldBe,
  );

  @override
  Widget build(BuildContext context) {
    final List<VaultContact> members = _members;
    final bool selecting = _selected.isNotEmpty;
    final int withEmail = _audience
        .where((VaultContact c) => c.emails.isNotEmpty)
        .length;
    final int withPhone = _audience
        .where((VaultContact c) => c.phones.isNotEmpty)
        .length;
    return PopScope(
      canPop: !selecting,
      onPopInvokedWithResult: (bool didPop, _) {
        if (!didPop) setState(_selected.clear);
      },
      child: Scaffold(
        appBar: selecting
            ? AppBar(
                leading: IconButton(
                  tooltip: context.l10n.clearSelection,
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(_selected.clear),
                ),
                title: Text(context.l10n.nSelected(_selected.length)),
                actions: <Widget>[
                  IconButton(
                    tooltip: context.l10n.selectAll,
                    icon: const Icon(Icons.select_all),
                    onPressed: () => setState(
                      () => _selected.addAll(
                        members.map((VaultContact c) => c.id),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: context.l10n.removeFromLabel,
                    icon: const Icon(Icons.label_off_outlined),
                    onPressed: _busy ? null : _removeSelected,
                  ),
                ],
              )
            : AppBar(
                title: Text(_label, textDirection: directionOf(_label)),
                actions: <Widget>[
                  IconButton(
                    tooltip: context.l10n.addContacts,
                    icon: Icon(Icons.person_add_alt_outlined),
                    onPressed: _busy || _all == null ? null : _addMembers,
                  ),
                  PopupMenuButton<String>(
                    onSelected: (String value) =>
                        value == 'rename' ? _rename() : _delete(),
                    itemBuilder: (_) => <PopupMenuEntry<String>>[
                      PopupMenuItem<String>(
                        value: 'rename',
                        child: Text(context.l10n.renameLabel),
                      ),
                      PopupMenuItem<String>(
                        value: 'delete',
                        child: Text(context.l10n.deleteLabel),
                      ),
                    ],
                  ),
                ],
              ),
        body: _all == null
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: FilledButton.tonalIcon(
                            onPressed: withEmail == 0 ? null : _emailAll,
                            icon: const Icon(Icons.mail_outline),
                            label: Text(
                              selecting ? context.l10n.emailN(withEmail) : context.l10n.emailAll,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.tonalIcon(
                            onPressed: withPhone == 0 ? null : _textAll,
                            icon: const Icon(Icons.sms_outlined),
                            label: Text(
                              selecting ? context.l10n.textN(withPhone) : context.l10n.textAll,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        members.isEmpty
                            ? context.l10n.nobodyHasThisLabelAny
                            : context.l10n.holdRowToSelect(_count(members.length)),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: members.length,
                      itemBuilder: (BuildContext context, int index) {
                        final VaultContact c = members[index];
                        final bool picked = _selected.contains(c.id);
                        final String detail = c.phones.isNotEmpty
                            ? c.phones.first
                            : c.emails.isNotEmpty
                            ? c.emails.first
                            : '';
                        void toggle() => setState(
                          () => picked
                              ? _selected.remove(c.id)
                              : _selected.add(c.id),
                        );
                        return ListTile(
                          selected: picked,
                          leading: picked
                              ? const CircleAvatar(child: Icon(Icons.check))
                              : ContactAvatar(contact: c),
                          title: Text(
                            c.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textDirection: directionOf(c.displayName),
                          ),
                          subtitle: detail.isEmpty
                              ? null
                              : Text(
                                  detail,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                          onLongPress: toggle,
                          onTap: selecting
                              ? toggle
                              : () => Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) =>
                                        ContactDetailPage(contact: c),
                                  ),
                                ),
                        );
                      },
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// Tick several contacts; pops the chosen ids.
class LabelMembersPicker extends StatefulWidget {
  const LabelMembersPicker({
    super.key,
    required this.title,
    required this.contacts,
  });

  final String title;
  final List<VaultContact> contacts;

  @override
  State<LabelMembersPicker> createState() => _LabelMembersPickerState();
}

class _LabelMembersPickerState extends State<LabelMembersPicker> {
  late final List<VaultContact> _contacts = _sorted(widget.contacts);
  final Set<String> _picked = <String>{};
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final String q = _query.trim().toLowerCase();
    final List<VaultContact> shown = q.isEmpty
        ? _contacts
        : _contacts
              .where(
                (VaultContact c) =>
                    c.displayName.toLowerCase().contains(q) ||
                    c.company.toLowerCase().contains(q) ||
                    c.phones.any((String p) => p.contains(q)) ||
                    c.emails.any((String e) => e.toLowerCase().contains(q)),
              )
              .toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: <Widget>[
          Center(
            child: Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(72, 40)),
                onPressed: _picked.isEmpty
                    ? null
                    : () => Navigator.of(context).pop(_picked),
                child: Text(_picked.isEmpty ? context.l10n.add : context.l10n.addN(_picked.length)),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              decoration: InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: context.l10n.searchContacts,
              ),
              onChanged: (String value) => setState(() => _query = value),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: shown.length,
              itemBuilder: (BuildContext context, int index) {
                final VaultContact c = shown[index];
                return CheckboxListTile(
                  value: _picked.contains(c.id),
                  onChanged: (bool? on) => setState(
                    () => on == true ? _picked.add(c.id) : _picked.remove(c.id),
                  ),
                  title: Text(
                    c.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textDirection: directionOf(c.displayName),
                  ),
                  subtitle: c.phones.isEmpty
                      ? null
                      : Text(
                          c.phones.first,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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
