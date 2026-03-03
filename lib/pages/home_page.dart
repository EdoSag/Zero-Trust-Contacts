import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:nowa_runtime/nowa_runtime.dart';
import 'package:zerotrust_contacts/integrations/device_contacts_service.dart';
import 'package:zerotrust_contacts/models/vault_contact.dart';
import 'package:zerotrust_contacts/services/vault_repository.dart';

@NowaGenerated()
class HomePage extends StatefulWidget {
  @NowaGenerated({'loader': 'auto-constructor'})
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final DeviceContactsService _deviceContactsService = DeviceContactsService();
  final VaultRepository _vaultRepository = VaultRepository();
  final TextEditingController _searchController = TextEditingController();

  int _tabIndex = 0;
  bool _loading = true;
  bool _permissionDenied = false;
  String? _error;

  String _query = '';
  String _sourceFilter = 'all';
  String _activeLabelFilter = '';
  ContactSortMode _sortMode = ContactSortMode.recent;

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
    _loadContacts();
  }

  Future<void> _loadContacts() async {
    setState(() {
      _loading = true;
      _error = null;
      _permissionDenied = false;
    });

    try {
      final List<VaultContact> saved =
          await _vaultRepository.loadSavedContacts();
      final bool permissionGranted =
          await _deviceContactsService.requestPermission();
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
        _deviceContacts = deviceContacts;
        _duplicateGroups = duplicates;
        _healthSummary = health;
        _labelCounts = labelCounts;
        _loading = false;
      });
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

  Future<void> _openContact(VaultContact contact) async {
    final bool? changed = await context.push<bool>(
      '/contact-detail',
      extra: contact.toJson(),
    );
    if (changed == true && mounted) {
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
                  await context.push('/account');
                  if (mounted) {
                    await _loadContacts();
                  }
                },
                icon: const Icon(Icons.manage_accounts_outlined),
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
            alignment: Alignment.centerRight,
            child: PopupMenuButton<ContactSortMode>(
              tooltip: 'Sort',
              onSelected: (ContactSortMode mode) {
                setState(() {
                  _sortMode = mode;
                });
              },
              itemBuilder: (BuildContext context) {
                return const [
                  PopupMenuItem(
                    value: ContactSortMode.alphabetical,
                    child: Text('Sort A-Z'),
                  ),
                  PopupMenuItem(
                    value: ContactSortMode.recent,
                    child: Text('Sort recent'),
                  ),
                  PopupMenuItem(
                    value: ContactSortMode.source,
                    child: Text('Sort by source'),
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
      padding: const EdgeInsets.only(right: 8),
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
        return 'A-Z';
      case ContactSortMode.recent:
        return 'Recent';
      case ContactSortMode.source:
        return 'Source';
    }
  }

  Widget _buildContactTile(VaultContact contact) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final bool saved =
        _savedContacts.any((VaultContact item) => item.id == contact.id);
    return ListTile(
      onTap: () => _openContact(contact),
      leading: CircleAvatar(
        backgroundColor: colorScheme.primaryContainer,
        child: Icon(Icons.person, color: colorScheme.onPrimaryContainer),
      ),
      title: Row(
        children: [
          Expanded(child: Text(contact.displayName)),
          if (contact.isPinned) const Icon(Icons.push_pin, size: 16),
          if (contact.isFavorite) const Icon(Icons.star, size: 16),
        ],
      ),
      subtitle: Text(
        contact.phones.isNotEmpty ? contact.phones.first : contact.source,
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

  Widget _buildContactsTab() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Text(_error!));
    }

    return RefreshIndicator(
      onRefresh: _loadContacts,
      child: ListView(
        children: [
          _buildSearchHeader(),
          if (_permissionDenied)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Text(
                'Contacts permission denied. Showing vault-only contacts.',
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              'Contacts (${_filteredContacts.length})',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          if (_filteredContacts.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child:
                  Center(child: Text('No contacts match the current filters.')),
            ),
          ..._filteredContacts.map(_buildContactTile),
          const SizedBox(height: 80),
        ],
      ),
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
    return Scaffold(
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
      floatingActionButton: FloatingActionButton.large(
        onPressed: () async {
          final bool? created = await context.push<bool>('/create-contact');
          if (created == true && mounted) {
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
    _searchController.dispose();
    super.dispose();
  }
}
