import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:nowa_runtime/nowa_runtime.dart';
import 'package:zerotrust_contacts/globals/router.dart';
import 'package:zerotrust_contacts/integrations/device_contacts_service.dart';
import 'package:zerotrust_contacts/integrations/supabase_service.dart';

@NowaGenerated()
class HomePage extends StatefulWidget {
  @NowaGenerated({'loader': 'auto-constructor'})
  const HomePage({super.key});

  @override
  State<HomePage> createState() {
    return _HomePageState();
  }
}

@NowaGenerated()
class _HomePageState extends State<HomePage> {
  final DeviceContactsService _deviceContactsService = DeviceContactsService();

  int _selectedIndex = 0;

  late String _selectedAccount;

  List<DeviceContact> _contacts = [];

  ContactSourceStats _sourceStats = ContactSourceStats.empty();

  bool _isLoading = true;

  bool _permissionDenied = false;

  String _activeSourceFilter = 'all';

  String? _loadError;

  List<DeviceContact> get _filteredContacts {
    switch (_activeSourceFilter) {
      case 'google':
        return _contacts
            .where((contact) => contact.source == 'Google Contacts')
            .toList();
      case 'sim':
        return _contacts
            .where((contact) => contact.source == 'SIM card')
            .toList();
      case 'phone':
        return _contacts.where((contact) => contact.source == 'Phone').toList();
      default:
        return _contacts;
    }
  }

  String get _activeFilterLabel {
    switch (_activeSourceFilter) {
      case 'google':
        return 'Google contacts';
      case 'sim':
        return 'SIM contacts';
      case 'phone':
        return 'Phone contacts';
      default:
        return 'All contacts';
    }
  }

  @override
  void initState() {
    super.initState();
    _selectedAccount = SupabaseService().currentUser?.email ?? 'Google account';
    _loadContacts();
  }

  Future<void> _loadContacts() async {
    setState(() {
      _isLoading = true;
      _permissionDenied = false;
      _loadError = null;
    });

    try {
      final permissionGranted =
          await _deviceContactsService.requestPermission();
      if (!permissionGranted) {
        if (!mounted) {
          return;
        }
        setState(() {
          _contacts = [];
          _sourceStats = ContactSourceStats.empty();
          _permissionDenied = true;
          _isLoading = false;
        });
        return;
      }

      final results = await Future.wait<dynamic>([
        _deviceContactsService.loadContacts(selectedAccount: _selectedAccount),
        _deviceContactsService.loadSourceStats(
            selectedAccount: _selectedAccount),
      ]);
      final contacts = results[0] as List<DeviceContact>;
      final stats = results[1] as ContactSourceStats;

      if (!mounted) {
        return;
      }
      setState(() {
        _contacts = contacts;
        _sourceStats = stats;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _contacts = [];
        _sourceStats = ContactSourceStats.empty();
        _loadError = e.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  Widget _buildSearchBar() {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Container(
        height: 56.0,
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(28.0),
        ),
        child: Row(
          children: [
            Icon(Icons.search, color: colorScheme.onSurfaceVariant),
            const SizedBox(width: 12.0),
            Expanded(
              child: Text(
                'Search contacts',
                style: TextStyle(
                  color: colorScheme.onSurfaceVariant,
                  fontSize: 16.0,
                ),
              ),
            ),
            GestureDetector(
              onTap: () {
                context.push('/account');
              },
              child: Container(
                padding: const EdgeInsets.all(2.0),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      colorScheme.primary,
                      colorScheme.secondary,
                      colorScheme.tertiary,
                    ],
                  ),
                ),
                child: CircleAvatar(
                  radius: 14.0,
                  backgroundColor: colorScheme.primary,
                  child: Icon(
                    Icons.person,
                    size: 16.0,
                    color: colorScheme.onPrimary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAccountSelector() {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        children: [
          GestureDetector(
            onTap: _showAccountPicker,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12.0,
                vertical: 8.0,
              ),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(8.0),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.person_outline,
                    color: colorScheme.onSurface,
                    size: 18.0,
                  ),
                  const SizedBox(width: 8.0),
                  Text(
                    _selectedAccount,
                    style: TextStyle(color: colorScheme.onSurface),
                  ),
                  const SizedBox(width: 4.0),
                  Icon(
                    Icons.keyboard_arrow_down,
                    color: colorScheme.onSurface,
                    size: 18.0,
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          IconButton(
            icon:
                Icon(Icons.label_outline, color: colorScheme.onSurfaceVariant),
            onPressed: () {},
          ),
          IconButton(
            icon: Icon(Icons.sort, color: colorScheme.onSurfaceVariant),
            onPressed: () {},
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(IconData icon, String title) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 8.0),
      child: Row(
        children: [
          Icon(icon, size: 18.0, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 8.0),
          Text(
            title,
            style: TextStyle(
              color: colorScheme.onSurfaceVariant,
              fontSize: 12.0,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  void _showAccountPicker() {
    final colorScheme = Theme.of(context).colorScheme;
    final totalCount = _sourceStats.totalCount > 0
        ? _sourceStats.totalCount
        : _contacts.length;
    showModalBottomSheet(
      context: context,
      backgroundColor: colorScheme.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28.0)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 32.0,
              height: 4.0,
              decoration: BoxDecoration(
                color: colorScheme.outline,
                borderRadius: BorderRadius.circular(2.0),
              ),
            ),
            const SizedBox(height: 24.0),
            _buildAccountOption(
              icon: Icons.contacts_outlined,
              title: 'All contacts',
              count: totalCount,
              filterValue: 'all',
            ),
            _buildAccountOption(
              icon: Icons.person_outline,
              title: _selectedAccount,
              count: _sourceStats.googleCount,
              subtitle: 'Google Contacts',
              filterValue: 'google',
            ),
            _buildAccountOption(
              icon: Icons.sd_card_outlined,
              title: 'SIM card',
              count: _sourceStats.simCount,
              filterValue: 'sim',
            ),
            _buildAccountOption(
              icon: Icons.smartphone_outlined,
              title: 'Phone',
              count: _sourceStats.phoneCount,
              filterValue: 'phone',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAccountOption({
    required IconData icon,
    required String title,
    required int count,
    required String filterValue,
    String? subtitle,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(icon, color: colorScheme.onSurfaceVariant),
      title: Text(title, style: TextStyle(color: colorScheme.onSurface)),
      subtitle: subtitle == null
          ? null
          : Text(subtitle,
              style: TextStyle(color: colorScheme.onSurfaceVariant)),
      trailing: Text(
        '$count',
        style: TextStyle(color: colorScheme.onSurfaceVariant),
      ),
      onTap: () {
        setState(() {
          _activeSourceFilter = filterValue;
        });
        Navigator.of(context).pop();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            _buildSearchBar(),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : RefreshIndicator(
                      onRefresh: _loadContacts,
                      child: ListView(
                        children: [
                          _buildAccountSelector(),
                          _buildSectionHeader(
                            Icons.contacts_outlined,
                            '$_activeFilterLabel (${_filteredContacts.length})',
                          ),
                          if (_permissionDenied)
                            Padding(
                              padding: const EdgeInsets.all(32.0),
                              child: Center(
                                child: Text(
                                  'Contacts permission is required to read phone and SIM contacts.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ),
                          if (_loadError != null)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24.0,
                                vertical: 8.0,
                              ),
                              child: Text(
                                _loadError!,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: colorScheme.error,
                                  fontSize: 12.0,
                                ),
                              ),
                            ),
                          if (!_permissionDenied &&
                              _loadError == null &&
                              _filteredContacts.isEmpty)
                            Padding(
                              padding: const EdgeInsets.all(32.0),
                              child: Center(
                                child: Text(
                                  'No contacts found for this source.',
                                  style: TextStyle(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ),
                          ..._filteredContacts.map((contact) {
                            return _buildContactTile(contact);
                          }),
                          const SizedBox(height: 80.0),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.large(
        onPressed: () {
          appRouter.push('/create-contact');
        },
        backgroundColor: colorScheme.primaryContainer,
        foregroundColor: colorScheme.onPrimaryContainer,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24.0),
        ),
        child: const Icon(Icons.add),
      ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: colorScheme.surface,
        indicatorColor: colorScheme.secondaryContainer,
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.person), label: 'Contacts'),
          NavigationDestination(
            icon: Icon(Icons.star_outline),
            label: 'Highlights',
          ),
          NavigationDestination(
            icon: Icon(Icons.folder_open),
            label: 'Organize',
          ),
        ],
      ),
    );
  }

  Widget _buildContactTile(DeviceContact contact) {
    final colorScheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: colorScheme.primaryContainer,
        child: Icon(Icons.person, color: colorScheme.onPrimaryContainer),
      ),
      title: Text(
        contact.name,
        style: TextStyle(color: colorScheme.onSurface, fontSize: 16.0),
      ),
      subtitle: Text(
        contact.phone.isEmpty ? contact.source : contact.phone,
        style: TextStyle(
          color: colorScheme.onSurfaceVariant,
          fontSize: 13.0,
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 16.0,
        vertical: 4.0,
      ),
      onTap: () {},
    );
  }
}
