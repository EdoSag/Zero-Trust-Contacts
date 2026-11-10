import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:convert';
import 'dart:typed_data';

import 'package:share_plus/share_plus.dart';
import 'package:zerotrust_contacts/app/contact_sorting.dart';
import 'package:zerotrust_contacts/app/providers.dart';
import 'package:zerotrust_contacts/app/text_direction.dart';
import 'package:zerotrust_contacts/widgets/alphabet_index.dart';
import 'package:zerotrust_contacts/integrations/device_contacts_service.dart';
import 'package:zerotrust_contacts/legacy/legacy_import_banner.dart';
import 'package:zerotrust_contacts/pages/contact_detail_page.dart';
import 'package:zerotrust_contacts/pages/create_contact_page.dart';
import 'package:zerotrust_contacts/import/contact_import_planner.dart';
import 'package:zerotrust_contacts/pages/google_import_page.dart';
import 'package:zerotrust_contacts/pages/qr_scan_page.dart';
import 'package:zerotrust_contacts/pages/settings_page.dart';
import 'package:zerotrust_contacts/pages/trash_page.dart';
import 'package:zerotrust_contacts/models/vault_contact.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_contacts/services/vault_repository.dart';
import 'package:zerotrust_contacts/widgets/contact_avatar.dart';
import 'package:zerotrust_contacts/widgets/compact_button_style.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  final DeviceContactsService _deviceContactsService = DeviceContactsService();
  late final VaultRepository _vaultRepository = requireRepository(ref);
  StreamSubscription<Set<String>>? _storeChanges;
  Timer? _reloadDebounce;
  final TextEditingController _searchController = TextEditingController();

  int _tabIndex = 0;
  bool _loading = true;
  bool _permissionDenied = false;
  String? _error;

  String _query = '';
  String _sourceFilter = 'all';
  String _activeLabelFilter = '';
  ContactSortMode _sortMode = ContactSortMode.alphabetical;
  static const String _sortKey = 'contacts_list_sort';

  /// Saved contacts ticked in the list (long-press to start).
  final Set<String> _selected = <String>{};
  bool _bulkBusy = false;

  static const double _rowExtent = 72;
  final ScrollController _listScroll = ScrollController();
  final GlobalKey _listHeaderKey = GlobalKey();
  double _listHeaderHeight = 0;
  StreamSubscription<VaultContact>? _openedContactSubscription;
  StreamSubscription<void>? _incomingSubscription;
  bool _handlingIncoming = false;

  List<VaultContact> _savedContacts = <VaultContact>[];
  List<VaultContact> _deviceContacts = <VaultContact>[];
  List<ContactDuplicateGroup> _duplicateGroups = <ContactDuplicateGroup>[];
  ContactHealthSummary _healthSummary = ContactHealthSummary(
    upcomingBirthdays: <VaultContact>[],
    staleContacts: <VaultContact>[],
    missingPhoneContacts: <VaultContact>[],
  );
  Map<String, int> _labelCounts = <String, int>{};

  List<VaultContact> get _allContacts => <VaultContact>[
        ..._savedContacts,
        ..._deviceContacts,
      ];

  List<VaultContact> get _filteredContacts {
    return _vaultRepository.filterAndSortContacts(
      contacts: _allContacts,
      query: _query,
      sourceFilter: _sourceFilter,
      sortMode: _sortMode,
      labelFilter: _activeLabelFilter.isEmpty ? null : _activeLabelFilter,
    );
  }

  List<VaultContact> get _highlightPinned {
    final List<VaultContact> items = _savedContacts
        .where((VaultContact contact) => contact.isPinned)
        .toList();
    _vaultRepository.sortContactsInPlace(items, ContactSortMode.recent);
    return items;
  }

  List<VaultContact> get _highlightFavorites {
    final List<VaultContact> items = _savedContacts
        .where((VaultContact contact) => contact.isFavorite)
        .toList();
    _vaultRepository.sortContactsInPlace(items, ContactSortMode.alphabetical);
    return items;
  }

  List<VaultContact> get _highlightFrequent {
    final List<VaultContact> items = _savedContacts
        .where((VaultContact contact) => contact.interactionCount > 0)
        .toList()
      ..sort((VaultContact a, VaultContact b) =>
          b.interactionCount.compareTo(a.interactionCount));
    return items.take(20).toList();
  }

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _query = _searchController.text.trim().toLowerCase();
      });
    });
    _openedContactSubscription =
        _deviceContactsService.openedContacts.listen(_handleOpenedContact);
    _incomingSubscription =
        _deviceContactsService.incoming.listen((_) => _consumeIncoming());
    // Edits here and on other devices (synced live) refresh the list.
    _storeChanges = _vaultRepository.changes.listen((_) {
      _reloadDebounce?.cancel();
      _reloadDebounce = Timer(const Duration(milliseconds: 300), () {
        if (mounted) _loadContacts(quiet: true);
      });
    });
    _loadContacts();
    _loadSortMode();
  }

  Future<void> _loadSortMode() async {
    try {
      final String? saved =
          await ref.read(ztPreferencesStoreProvider).read(_sortKey);
      final ContactSortMode? mode = ContactSortMode.values
          .where((ContactSortMode m) => m.name == saved)
          .firstOrNull;
      if (mode != null && mounted) {
        setState(() => _sortMode = mode);
      }
    } on Object {
      // No saved choice: A to Z.
    }
  }

  void _setSortMode(ContactSortMode mode) {
    setState(() => _sortMode = mode);
    ref
        .read(ztPreferencesStoreProvider)
        .write(_sortKey, mode.name)
        .catchError((Object _) {});
  }

  bool _askedPermission = false;

  Future<void> _loadContacts({bool quiet = false}) async {
    if (!quiet) {
      setState(() {
        _loading = true;
        _error = null;
        _permissionDenied = false;
      });
    }

    try {
      final List<VaultContact> saved =
          await _vaultRepository.loadSavedContacts();
      // The permission prompt covers the app: don't auto-lock under it.
      final bool permissionGranted = _askedPermission && quiet
          ? !_permissionDenied
          : await ref
              .read(vaultControllerProvider.notifier)
              .whileShowingSystemUi(_deviceContactsService.requestPermission);
      _askedPermission = true;
      List<VaultContact> deviceContacts = <VaultContact>[];

      if (permissionGranted) {
        final List<DeviceContact> loaded =
            await _deviceContactsService.loadContacts();
        deviceContacts = loaded.map((DeviceContact item) {
          return VaultContact.fromLegacyPayload(<String, dynamic>{
            'id': 'device_${item.id}',
            'displayName': item.name,
            'firstName': item.name,
            'phones': <String>[item.phone],
            'source': item.source,
            'createdAt': DateTime.now().toUtc().toIso8601String(),
            'updatedAt': DateTime.now().toUtc().toIso8601String(),
          });
        }).toList();
      } else {
        _permissionDenied = true;
      }

      final List<ContactDuplicateGroup> duplicates =
          await _vaultRepository.findDuplicateGroups(saved);
      final ContactHealthSummary health =
          _vaultRepository.buildHealthSummary(saved);
      final Map<String, int> labelCounts = _vaultRepository.labelCounts(saved);

      if (!mounted) {
        return;
      }
      setState(() {
        _savedContacts = saved;
        _selected.retainAll(saved.map((VaultContact c) => c.id));
        _deviceContacts = deviceContacts;
        _duplicateGroups = duplicates;
        _healthSummary = health;
        _labelCounts = labelCounts;
        _loading = false;
      });
      await _consumePendingOpenedContact();
      await _consumeIncoming();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _consumePendingOpenedContact() async {
    final VaultContact? contact =
        await _deviceContactsService.consumePendingOpenedContact();
    if (contact == null || !mounted) {
      return;
    }
    await _handleOpenedContact(contact);
  }

  /// Handles what another app handed over: a .vcf file to import, or a
  /// contact to save. Only reached once the vault is unlocked.
  Future<void> _consumeIncoming() async {
    if (_handlingIncoming || !mounted) {
      return;
    }
    _handlingIncoming = true;
    try {
      final IncomingRequest? request =
          await _deviceContactsService.consumePendingIncoming();
      if (request == null || !mounted) {
        return;
      }
      final NavigatorState navigator = Navigator.of(context);
      switch (request) {
        case IncomingVCard(:final String text, :final String name):
          await navigator.push<bool>(MaterialPageRoute<bool>(
            builder: (_) => GoogleImportPage(vCardText: text, vCardName: name),
          ));
        case IncomingNewContact(:final VaultContact contact):
          VaultContact? target;
          if (request.allowExisting && _savedContacts.isNotEmpty) {
            final bool? addToExisting = await showDialog<bool>(
              context: context,
              builder: (BuildContext ctx) => SimpleDialog(
                title: Text('Save ${contact.displayName}'),
                children: [
                  SimpleDialogOption(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    child: const ListTile(
                      leading: Icon(Icons.person_add_alt),
                      title: Text('Create a new contact'),
                    ),
                  ),
                  SimpleDialogOption(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    child: const ListTile(
                      leading: Icon(Icons.group_add_outlined),
                      title: Text('Add to a contact I already have'),
                    ),
                  ),
                ],
              ),
            );
            if (addToExisting == null || !mounted) {
              return;
            }
            if (addToExisting) {
              target = await _pickSavedContact();
              if (target == null || !mounted) {
                return;
              }
            }
          }
          await navigator.push<VaultContact>(MaterialPageRoute<VaultContact>(
            builder: (_) => target == null
                ? CreateContactPage(
                    prefill: contact,
                    createActivity: 'contact_saved_from_another_app',
                  )
                : CreateContactPage(
                    existing:
                        const ContactImportPlanner().merge(target, contact),
                  ),
          ));
      }
      if (mounted) {
        await _loadContacts(quiet: true);
      }
    } on Object {
      // Nothing usable was handed over.
    } finally {
      _handlingIncoming = false;
    }
  }

  /// Lets the user pick one of their saved contacts.
  Future<VaultContact?> _pickSavedContact() {
    String query = '';
    return showModalBottomSheet<VaultContact>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext ctx) => StatefulBuilder(
        builder: (BuildContext ctx, StateSetter setSheetState) {
          final List<VaultContact> matches =
              _vaultRepository.filterAndSortContacts(
            contacts: _savedContacts,
            query: query,
            sourceFilter: 'all',
            sortMode: ContactSortMode.alphabetical,
          );
          return Padding(
            padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: SizedBox(
              height: MediaQuery.of(ctx).size.height * 0.7,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      decoration: const InputDecoration(
                        hintText: 'Search your contacts',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (String value) =>
                          setSheetState(() => query = value),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: matches.length,
                      itemBuilder: (BuildContext ctx, int i) => ListTile(
                        leading:
                            ContactAvatar(contact: matches[i], radius: 20),
                        title: Text(matches[i].displayName),
                        subtitle: matches[i].phones.isEmpty
                            ? null
                            : Text(matches[i].phones.first),
                        onTap: () => Navigator.of(ctx).pop(matches[i]),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _handleOpenedContact(VaultContact contact) async {
    if (!mounted) {
      return;
    }

    VaultContact resolved = contact;
    for (final VaultContact item in _allContacts) {
      if (item.id == contact.id) {
        resolved = item;
        break;
      }
    }
    await _openContact(resolved);
  }

  Future<void> _openContact(VaultContact contact) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
          builder: (_) => ContactDetailPage(contact: contact)),
    );
    if (mounted) {
      await _loadContacts();
    }
  }

  Future<void> _mergeDuplicateGroup(ContactDuplicateGroup group) async {
    final VaultContact? merged =
        await _vaultRepository.mergeDuplicateContacts(group.contacts);
    if (merged != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Merged duplicates into ${merged.displayName}')),
      );
      await _loadContacts();
    }
  }

  Widget _buildSearchHeader() {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search name, phone, email, notes',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            onPressed: () {
                              _searchController.clear();
                            },
                            icon: const Icon(Icons.close),
                          ),
                    filled: true,
                    fillColor: colorScheme.surfaceContainerHigh,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(26),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                onPressed: () async {
                  await Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => const ContactsSettingsPage()));
                  if (mounted) {
                    await _loadContacts();
                  }
                },
                tooltip: 'Settings',
                icon: const Icon(Icons.settings_outlined),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _sourceChip('all', 'All'),
                _sourceChip('saved', 'Saved'),
                _sourceChip('account', 'Account'),
                _sourceChip('sim card', 'SIM'),
                _sourceChip('phone', 'Phone'),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: PopupMenuButton<ContactSortMode>(
              tooltip: 'Sort',
              onSelected: _setSortMode,
              itemBuilder: (BuildContext context) {
                return const [
                  PopupMenuItem(
                    value: ContactSortMode.alphabetical,
                    child: Text('First name, A to Z'),
                  ),
                  PopupMenuItem(
                    value: ContactSortMode.lastName,
                    child: Text('Last name, A to Z'),
                  ),
                  PopupMenuItem(
                    value: ContactSortMode.recent,
                    child: Text('Recently changed'),
                  ),
                  PopupMenuItem(
                    value: ContactSortMode.source,
                    child: Text('By source'),
                  ),
                ];
              },
              child: Chip(
                label: Text(_sortLabel(_sortMode)),
                avatar: const Icon(Icons.sort, size: 16),
              ),
            ),
          ),
          if (_activeLabelFilter.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Chip(
                    label: Text('Label: $_activeLabelFilter'),
                    onDeleted: () {
                      setState(() {
                        _activeLabelFilter = '';
                      });
                    },
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _sourceChip(String value, String label) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 8),
      child: FilterChip(
        selected: _sourceFilter == value,
        label: Text(label),
        onSelected: (_) {
          setState(() {
            _sourceFilter = value;
          });
        },
      ),
    );
  }

  String _sortLabel(ContactSortMode mode) {
    switch (mode) {
      case ContactSortMode.alphabetical:
        return 'First name';
      case ContactSortMode.lastName:
        return 'Last name';
      case ContactSortMode.recent:
        return 'Recent';
      case ContactSortMode.source:
        return 'Source';
    }
  }

  Widget _buildContactTile(
    VaultContact contact, {
    EdgeInsetsGeometry? contentPadding,
  }) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final bool saved =
        _savedContacts.any((VaultContact item) => item.id == contact.id);
    final bool selected = _selected.contains(contact.id);
    final String name = _sortMode == ContactSortMode.lastName
        ? ContactSorting.sortName(contact, byLastName: true)
        : contact.displayName;
    final bool hasPhone = contact.phones.isNotEmpty;
    return ListTile(
      contentPadding: contentPadding,
      selected: selected,
      selectedTileColor: colorScheme.secondaryContainer.withValues(alpha: 0.5),
      onTap: () {
        if (_selected.isEmpty) {
          _openContact(contact);
        } else if (saved) {
          _toggleSelected(contact.id);
        }
      },
      onLongPress: saved ? () => _toggleSelected(contact.id) : null,
      leading: selected
          ? CircleAvatar(
              radius: 20,
              backgroundColor: colorScheme.primary,
              child: Icon(Icons.check, color: colorScheme.onPrimary),
            )
          : ContactAvatar(contact: contact, radius: 20),
      title: Row(
        children: [
          // The name reads in its own direction (Hebrew right-to-left,
          // English left-to-right) but starts where the screen starts.
          Expanded(
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              // Only as tall as the text: without this it fills the row and
              // the name and number are drawn over each other.
              heightFactor: 1,
              child: Text(
                name,
                textDirection: directionOf(name),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          if (contact.isPinned) const Icon(Icons.push_pin, size: 16),
          if (contact.isFavorite) const Icon(Icons.star, size: 16),
        ],
      ),
      subtitle: Align(
        alignment: AlignmentDirectional.centerStart,
              // Only as tall as the text: without this it fills the row and
              // the name and number are drawn over each other.
              heightFactor: 1,
        child: Text(
          hasPhone ? contact.phones.first : contact.source,
          // A phone number always reads left-to-right.
          textDirection: hasPhone ? TextDirection.ltr : null,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      trailing: saved
          ? null
          : Text(
              contact.source,
              style:
                  TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12),
            ),
    );
  }

  void _toggleSelected(String id) {
    setState(() {
      if (!_selected.remove(id)) {
        _selected.add(id);
      }
    });
  }

  List<VaultContact> get _selectedContacts => _savedContacts
      .where((VaultContact c) => _selected.contains(c.id))
      .toList();

  void _snack(String text, {SnackBarAction? action}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), action: action));
  }

  /// Runs one action on the ticked contacts, then clears the ticks.
  Future<void> _bulk(Future<void> Function(List<VaultContact>) action) async {
    final List<VaultContact> contacts = _selectedContacts;
    if (contacts.isEmpty || _bulkBusy) {
      return;
    }
    setState(() => _bulkBusy = true);
    try {
      await action(contacts);
    } on Object catch (error) {
      _snack('That didn\'t work: $error');
    } finally {
      if (mounted) {
        setState(() => _bulkBusy = false);
        await _loadContacts(quiet: true);
      }
    }
  }

  Future<void> _deleteSelected() => _bulk((List<VaultContact> contacts) async {
        final VaultRepository repo = _vaultRepository;
        final List<String> ids =
            contacts.map((VaultContact c) => c.id).toList();
        final int moved = await repo.deleteSavedContacts(ids);
        if (mounted) setState(_selected.clear);
        _snack(
          moved == 1
              ? '1 contact moved to the trash'
              : '$moved contacts moved to the trash',
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () async {
              for (final String id in ids) {
                await repo.restoreFromTrash(id);
              }
            },
          ),
        );
      });

  Future<void> _labelSelected() async {
    final TextEditingController controller = TextEditingController();
    final String? label = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Add a label'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DirectionalTextField(
                controller: controller,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Label'),
              ),
              if (_labelCounts.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final String existing in _labelCounts.keys.take(12))
                      ActionChip(
                        label: Text(existing),
                        onPressed: () => Navigator.of(ctx).pop(existing),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (label == null || label.isEmpty) {
      return;
    }
    await _bulk((List<VaultContact> contacts) async {
      final int changed = await _vaultRepository.addLabel(
          contacts.map((VaultContact c) => c.id), label);
      if (mounted) setState(_selected.clear);
      _snack(changed == 1
          ? 'Added "$label" to 1 contact'
          : 'Added "$label" to $changed contacts');
    });
  }

  /// Shares the ticked contacts as one .vcf file.
  Future<void> _shareSelected() => _bulk((List<VaultContact> contacts) async {
        final String cards = _vaultRepository.exportVCard(contacts);
        const String name = 'contacts.vcf';
        await ref.read(vaultControllerProvider.notifier).whileShowingSystemUi(
              () => SharePlus.instance.share(ShareParams(
                files: <XFile>[
                  XFile.fromData(Uint8List.fromList(utf8.encode(cards)),
                      mimeType: 'text/x-vcard', name: name),
                ],
                fileNameOverrides: const <String>[name],
              )),
            );
        await _vaultRepository.logActivity('contact_share_vcard',
            details: 'Shared ${contacts.length} contacts as a vCard file');
        if (mounted) setState(_selected.clear);
      });

  Future<void> _mergeSelected() async {
    final List<VaultContact> contacts = _selectedContacts;
    if (contacts.length < 2) {
      return;
    }
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text('Merge ${contacts.length} contacts into one?'),
        content: Text(
          '${contacts.map((VaultContact c) => c.displayName).join(', ')}\n\n'
          'Their phones, emails and other details are combined. A restore '
          'point is saved first, so you can undo this from Settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Merge'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    await _bulk((List<VaultContact> contacts) async {
      final VaultContact? merged =
          await _vaultRepository.mergeDuplicateContacts(contacts);
      if (mounted) setState(_selected.clear);
      if (merged != null) {
        _snack('Merged into ${merged.displayName}');
      }
    });
  }

  PreferredSizeWidget _buildSelectionBar() {
    final List<String> selectable =
        _filteredContacts.where((VaultContact c) => c.isSavedContact)
            .map((VaultContact c) => c.id)
            .toList();
    final bool all = selectable.every(_selected.contains);
    return AppBar(
      leading: IconButton(
        tooltip: 'Cancel selection',
        icon: const Icon(Icons.close),
        onPressed: () => setState(_selected.clear),
      ),
      title: Text('${_selected.length} selected'),
      actions: [
        IconButton(
          tooltip: all ? 'Select none' : 'Select all',
          icon: Icon(all ? Icons.deselect : Icons.select_all),
          onPressed: () => setState(() {
            if (all) {
              _selected.clear();
            } else {
              _selected.addAll(selectable);
            }
          }),
        ),
        IconButton(
          tooltip: 'Add a label',
          icon: const Icon(Icons.label_outline),
          onPressed: _bulkBusy ? null : _labelSelected,
        ),
        IconButton(
          tooltip: 'Share',
          icon: const Icon(Icons.share_outlined),
          onPressed: _bulkBusy ? null : _shareSelected,
        ),
        if (_selected.length > 1)
          IconButton(
            tooltip: 'Merge',
            icon: const Icon(Icons.merge_type_outlined),
            onPressed: _bulkBusy ? null : _mergeSelected,
          ),
        IconButton(
          tooltip: 'Move to trash',
          icon: const Icon(Icons.delete_outline),
          onPressed: _bulkBusy ? null : _deleteSelected,
        ),
      ],
    );
  }

  /// Scrolls the list so the row at [index] is at the top.
  void _jumpToRow(int index) {
    if (!_listScroll.hasClients) {
      return;
    }
    final RenderObject? header =
        _listHeaderKey.currentContext?.findRenderObject();
    if (header is RenderBox && header.hasSize) {
      _listHeaderHeight = header.size.height;
    }
    final ScrollPosition position = _listScroll.position;
    _listScroll.jumpTo(
      (_listHeaderHeight + index * _rowExtent)
          .clamp(position.minScrollExtent, position.maxScrollExtent),
    );
  }

  Future<void> _openGoogleImport() async {
    final bool? imported = await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(builder: (_) => const GoogleImportPage()));
    if (imported == true && mounted) {
      await _loadContacts();
    }
  }

  Widget _buildGoogleImportBanner() {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Card(
        color: colorScheme.primaryContainer,
        child: ListTile(
          leading: Icon(Icons.download_outlined,
              color: colorScheme.onPrimaryContainer),
          title: Text(
            'Bring your Google contacts',
            style: TextStyle(color: colorScheme.onPrimaryContainer),
          ),
          subtitle: Text(
            'Import them into your encrypted vault in a few taps.',
            style: TextStyle(color: colorScheme.onPrimaryContainer),
          ),
          trailing: FilledButton(
            style: compactButtonStyle,
            onPressed: _openGoogleImport,
            child: const Text('Import'),
          ),
        ),
      ),
    );
  }

  Widget _buildContactsTab() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Text(_error!));
    }

    final List<VaultContact> contacts = _filteredContacts;
    final bool byLastName = _sortMode == ContactSortMode.lastName;
    final bool sectioned =
        byLastName || _sortMode == ContactSortMode.alphabetical;
    // For A to Z sorting: the letter each row is under, and the first row
    // of each letter.
    final List<String> sections = sectioned
        ? <String>[
            for (final VaultContact c in contacts)
              ContactSorting.sectionOf(
                  ContactSorting.sortName(c, byLastName: byLastName)),
          ]
        : const <String>[];
    final Map<String, int> firstRow = <String, int>{};
    for (int i = 0; i < sections.length; i += 1) {
      firstRow.putIfAbsent(sections[i], () => i);
    }
    final bool showIndex = sectioned &&
        _query.isEmpty &&
        firstRow.length > 1 &&
        contacts.length >= 15;

    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: _loadContacts,
          child: CustomScrollView(
            controller: _listScroll,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                // Room for the letter strip, so it doesn't sit on the
                // settings and sort buttons.
                child: Padding(
                  padding:
                      EdgeInsetsDirectional.only(end: showIndex ? 14 : 0),
                  child: Column(
                  key: _listHeaderKey,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildSearchHeader(),
                    const LegacyImportBanner(),
                    if (_savedContacts.isEmpty) _buildGoogleImportBanner(),
                    if (_permissionDenied)
                      const Padding(
                        padding:
                            EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        child: Text(
                          'Contacts permission denied. Showing vault-only contacts.',
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                      child: Text(
                        'Contacts (${contacts.length})',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    if (contacts.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(
                            child:
                                Text('No contacts match the current filters.')),
                      ),
                  ],
                ),
                ),
              ),
              SliverFixedExtentList(
                itemExtent: _rowExtent,
                delegate: SliverChildBuilderDelegate(
                  (BuildContext context, int i) {
                    if (!sectioned) {
                      return _buildContactTile(contacts[i]);
                    }
                    // The letter sits beside the first contact under it.
                    return Row(
                      children: [
                        SizedBox(
                          width: 40,
                          child: firstRow[sections[i]] == i
                              ? Center(
                                  child: Text(
                                    sections[i],
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary,
                                        ),
                                  ),
                                )
                              : null,
                        ),
                        Expanded(
                          child: _buildContactTile(
                            contacts[i],
                            contentPadding: EdgeInsetsDirectional.only(
                                start: 4, end: showIndex ? 32 : 16),
                          ),
                        ),
                      ],
                    );
                  },
                  childCount: contacts.length,
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 96)),
            ],
          ),
        ),
        if (showIndex)
          PositionedDirectional(
            end: 2,
            top: 8,
            bottom: 104,
            child: AlphabetIndex(
              letters: firstRow.keys.toList(),
              onLetter: (String letter) => _jumpToRow(firstRow[letter]!),
            ),
          ),
      ],
    );
  }

  Widget _buildHighlightsSection(String title, List<VaultContact> contacts) {
    if (contacts.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              ...contacts.take(10).map(_buildContactTile),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHighlightsTab() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final List<VaultContact> pinned = _highlightPinned;
    final List<VaultContact> favorites = _highlightFavorites;
    final List<VaultContact> frequent = _highlightFrequent;

    return RefreshIndicator(
      onRefresh: _loadContacts,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildHighlightsSection('Pinned', pinned),
          _buildHighlightsSection('Favorites', favorites),
          _buildHighlightsSection('Frequent', frequent),
          if (pinned.isEmpty && favorites.isEmpty && frequent.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.only(top: 40),
                child: Text(
                    'No highlights yet. Star/pin contacts to see them here.'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildOrganizeTab() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return RefreshIndicator(
      onRefresh: _loadContacts,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Trash'),
              subtitle: const Text('Deleted contacts, kept for 30 days'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const TrashPage())),
            ),
          ),
          if (QrScanPage.isSupported) ...[
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: const Icon(Icons.qr_code_scanner),
                title: const Text('Scan a contact QR code'),
                subtitle: const Text('Add a contact someone shows you'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  if (await QrScanPage.scanAndImport(context) && mounted) {
                    await _loadContacts(quiet: true);
                  }
                },
              ),
            ),
          ],
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Labels',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  if (_labelCounts.isEmpty)
                    const Text('No labels yet')
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _labelCounts.entries
                          .map((MapEntry<String, int> entry) {
                        return ActionChip(
                          label: Text('${entry.key} (${entry.value})'),
                          onPressed: () {
                            setState(() {
                              _tabIndex = 0;
                              _activeLabelFilter = entry.key;
                            });
                          },
                        );
                      }).toList(),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Smart groups',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.cake_outlined),
                    title: Text(
                        'Birthdays soon (${_healthSummary.upcomingBirthdays.length})'),
                  ),
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.access_time_outlined),
                    title: Text(
                        'Stale contacts (${_healthSummary.staleContacts.length})'),
                  ),
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.phone_disabled_outlined),
                    title: Text(
                        'Missing phone (${_healthSummary.missingPhoneContacts.length})'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Duplicate cleanup',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  if (_duplicateGroups.isEmpty)
                    const Text('No duplicates detected')
                  else
                    ..._duplicateGroups.map((ContactDuplicateGroup group) {
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.merge_type_outlined),
                        title: Text(
                          '${group.reason} (${group.contacts.length})',
                        ),
                        subtitle: Text(
                          group.contacts
                              .map((VaultContact c) => c.displayName)
                              .join(', '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: TextButton(
                          onPressed: () => _mergeDuplicateGroup(group),
                          child: const Text('Merge'),
                        ),
                      );
                    }),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool selecting = _selected.isNotEmpty && _tabIndex == 0;
    return PopScope(
      // Back clears the ticks before it leaves the app.
      canPop: !selecting,
      onPopInvokedWithResult: (bool didPop, Object? _) {
        if (!didPop) setState(_selected.clear);
      },
      child: _buildScaffold(selecting),
    );
  }

  Widget _buildScaffold(bool selecting) {
    return Scaffold(
      appBar: selecting ? _buildSelectionBar() : null,
      body: SafeArea(
        child: IndexedStack(
          index: _tabIndex,
          children: [
            _buildContactsTab(),
            _buildHighlightsTab(),
            _buildOrganizeTab(),
          ],
        ),
      ),
      floatingActionButton: selecting ? null : FloatingActionButton.large(
        onPressed: () async {
          final VaultContact? created = await Navigator.of(context)
              .push<VaultContact>(MaterialPageRoute<VaultContact>(
                  builder: (_) => const CreateContactPage()));
          if (created != null && mounted) {
            await _loadContacts();
          }
        },
        child: const Icon(Icons.add),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (int value) {
          setState(() {
            _tabIndex = value;
            _selected.clear();
          });
        },
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.people_alt_outlined), label: 'Contacts'),
          NavigationDestination(
              icon: Icon(Icons.star_outline), label: 'Highlights'),
          NavigationDestination(
              icon: Icon(Icons.folder_open_outlined), label: 'Organize'),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _openedContactSubscription?.cancel();
    _incomingSubscription?.cancel();
    _storeChanges?.cancel();
    _reloadDebounce?.cancel();
    _searchController.dispose();
    _listScroll.dispose();
    super.dispose();
  }
}
