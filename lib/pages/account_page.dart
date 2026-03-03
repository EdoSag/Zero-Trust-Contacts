import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:nowa_runtime/nowa_runtime.dart';
import 'package:zerotrust_contacts/auth_service.dart';
import 'package:zerotrust_contacts/integrations/supabase_service.dart';
import 'package:zerotrust_contacts/security_service.dart';

enum _DeleteDataScope {
  cloud,
  local,
  all,
}

@NowaGenerated()
class AccountPage extends StatefulWidget {
  @NowaGenerated({'loader': 'auto-constructor'})
  const AccountPage({super.key});

  @override
  State<AccountPage> createState() {
    return _AccountPageState();
  }
}

@NowaGenerated()
class _AccountPageState extends State<AccountPage> {
  final AuthService _authService = AuthService();

  bool _isSyncing = false;
  bool _isPulling = false;
  bool _isDeleting = false;
  bool _isSigningOut = false;

  String? _errorMessage;

  bool get _isBusy {
    return _isSyncing || _isPulling || _isDeleting || _isSigningOut;
  }

  String _readableError(Object error) {
    return error
        .toString()
        .replaceFirst('Exception: ', '')
        .replaceFirst('StateError: ', '');
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) {
      return;
    }
    final colorScheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? colorScheme.error : null,
        ),
      );
  }

  List<String> _parseCloudContacts(String dataBlob) {
    final dynamic decoded = jsonDecode(dataBlob);
    dynamic rawContacts;

    if (decoded is Map<String, dynamic>) {
      rawContacts = decoded['contacts'];
    } else if (decoded is List) {
      rawContacts = decoded;
    } else {
      throw const FormatException('Unexpected cloud payload format.');
    }

    if (rawContacts is! List) {
      throw const FormatException(
        'Cloud payload is missing the contacts list.',
      );
    }

    return rawContacts
        .map<String>((entry) {
          if (entry is String) {
            return entry;
          }
          if (entry is Map || entry is List) {
            return jsonEncode(entry);
          }
          return entry.toString();
        })
        .where((payload) => payload.trim().isNotEmpty)
        .toList();
  }

  Future<void> _handleSyncToCloud() async {
    if (_isBusy) {
      return;
    }

    setState(() {
      _isSyncing = true;
      _errorMessage = null;
    });

    try {
      final contacts =
          await LocalEncryptedDatabaseService().readAllContactPayloads();
      final payload = jsonEncode({
        'version': 1,
        'exportedAt': DateTime.now().toUtc().toIso8601String(),
        'contacts': contacts,
      });
      await _authService.pushVaultBlobToCloud(payload);
      _showMessage('Synced ${contacts.length} contact(s) to cloud.');
    } catch (error) {
      final message = 'Failed syncing to cloud: ${_readableError(error)}';
      if (mounted) {
        setState(() {
          _errorMessage = message;
        });
      }
      _showMessage(message, isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isSyncing = false;
        });
      }
    }
  }

  Future<void> _handlePullFromCloud() async {
    if (_isBusy) {
      return;
    }

    setState(() {
      _isPulling = true;
      _errorMessage = null;
    });

    try {
      final cloudBlob = await _authService.pullVaultBlobFromCloud();
      if (cloudBlob == null || cloudBlob.trim().isEmpty) {
        _showMessage('No cloud data found for this account.');
        return;
      }
      final cloudContacts = _parseCloudContacts(cloudBlob);
      await LocalEncryptedDatabaseService()
          .replaceAllContactPayloads(cloudContacts);
      _showMessage('Pulled ${cloudContacts.length} contact(s) from cloud.');
    } catch (error) {
      final message = 'Failed pulling from cloud: ${_readableError(error)}';
      if (mounted) {
        setState(() {
          _errorMessage = message;
        });
      }
      _showMessage(message, isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isPulling = false;
        });
      }
    }
  }

  Future<_DeleteDataScope?> _showDeleteDialog() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return showDialog<_DeleteDataScope>(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(36.0),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24.0, 24.0, 24.0, 20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Delete data',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 14.0),
                Text(
                  'Choose what to delete: cloud data, local data, or all data.',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24.0),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () {
                      Navigator.of(context).pop(_DeleteDataScope.cloud);
                    },
                    child: const Text('Cloud data'),
                  ),
                ),
                const SizedBox(height: 4.0),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () {
                      Navigator.of(context).pop(_DeleteDataScope.local);
                    },
                    child: const Text('Local data'),
                  ),
                ),
                const SizedBox(height: 8.0),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: () {
                      Navigator.of(context).pop(_DeleteDataScope.all);
                    },
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24.0),
                      ),
                    ),
                    child: const Text('All data'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _handleDeleteData() async {
    if (_isBusy) {
      return;
    }

    final selectedScope = await _showDeleteDialog();
    if (selectedScope == null) {
      return;
    }

    setState(() {
      _isDeleting = true;
      _errorMessage = null;
    });

    try {
      String successMessage;
      switch (selectedScope) {
        case _DeleteDataScope.cloud:
          await _authService.deleteCloudVaultBlob();
          successMessage = 'Cloud data deleted.';
        case _DeleteDataScope.local:
          await LocalEncryptedDatabaseService().clearAllContactPayloads();
          await LocalSecurityRepository().clearCachedCloudBlob();
          successMessage = 'Local data deleted.';
        case _DeleteDataScope.all:
          await _authService.deleteCloudVaultBlob();
          await LocalEncryptedDatabaseService().clearAllContactPayloads();
          await LocalSecurityRepository().clearCachedCloudBlob();
          successMessage = 'Cloud and local data deleted.';
      }
      _showMessage(successMessage);
    } catch (error) {
      final message = 'Failed deleting data: ${_readableError(error)}';
      if (mounted) {
        setState(() {
          _errorMessage = message;
        });
      }
      _showMessage(message, isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isDeleting = false;
        });
      }
    }
  }

  Future<void> _handleSignOut() async {
    if (_isBusy) {
      return;
    }

    setState(() {
      _isSigningOut = true;
      _errorMessage = null;
    });

    try {
      if (SupabaseService().currentUser != null) {
        await _authService.signOut();
      }
      if (mounted) {
        context.go('/onboarding');
      }
    } catch (error) {
      final message = 'Failed signing out: ${_readableError(error)}';
      if (mounted) {
        setState(() {
          _errorMessage = message;
        });
      }
      _showMessage(message, isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isSigningOut = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final currentUser = SupabaseService().currentUser;

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8.0),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 18.0, vertical: 16.0),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(20.0),
                border: Border.all(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.65),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 10.0,
                    offset: const Offset(0.0, 2.0),
                  ),
                ],
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 24.0,
                    backgroundColor:
                        colorScheme.primaryContainer.withValues(alpha: 0.65),
                    child: Icon(
                      Icons.person_outline,
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 14.0),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Account',
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2.0),
                        Text(
                          currentUser?.email ?? 'No active session',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28.0),
            ElevatedButton.icon(
              onPressed: _isBusy ? null : _handleSyncToCloud,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(64.0),
                backgroundColor: colorScheme.primary,
                foregroundColor: colorScheme.onPrimary,
                elevation: 0.0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(32.0),
                ),
              ),
              icon: _isSyncing
                  ? SizedBox(
                      height: 18.0,
                      width: 18.0,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.0,
                        color: colorScheme.onPrimary,
                      ),
                    )
                  : const Icon(Icons.cloud_upload_outlined),
              label: Text(_isSyncing ? 'Syncing...' : 'Sync to Cloud'),
            ),
            const SizedBox(height: 16.0),
            ElevatedButton.icon(
              onPressed: _isBusy ? null : _handlePullFromCloud,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(64.0),
                backgroundColor: colorScheme.primaryContainer,
                foregroundColor: colorScheme.onPrimaryContainer,
                elevation: 0.0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(32.0),
                ),
              ),
              icon: _isPulling
                  ? SizedBox(
                      height: 18.0,
                      width: 18.0,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.0,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    )
                  : const Icon(Icons.cloud_download_outlined),
              label: Text(_isPulling ? 'Pulling...' : 'Pull from Cloud'),
            ),
            const SizedBox(height: 16.0),
            OutlinedButton.icon(
              onPressed: _isBusy ? null : _handleDeleteData,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(64.0),
                foregroundColor: colorScheme.primary,
                side: BorderSide(color: colorScheme.outline),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(32.0),
                ),
              ),
              icon: _isDeleting
                  ? SizedBox(
                      height: 18.0,
                      width: 18.0,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.0,
                        color: colorScheme.primary,
                      ),
                    )
                  : const Icon(Icons.delete_outline),
              label: Text(_isDeleting ? 'Deleting...' : 'Delete Data'),
            ),
            const SizedBox(height: 24.0),
            ElevatedButton.icon(
              onPressed: _isBusy ? null : _handleSignOut,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(64.0),
                backgroundColor: colorScheme.error,
                foregroundColor: colorScheme.onError,
                elevation: 0.0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(32.0),
                ),
              ),
              icon: _isSigningOut
                  ? SizedBox(
                      height: 18.0,
                      width: 18.0,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.0,
                        color: colorScheme.onError,
                      ),
                    )
                  : const Icon(Icons.logout),
              label: Text(_isSigningOut ? 'Signing Out...' : 'Sign Out'),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 14.0),
              Text(
                _errorMessage!,
                style: TextStyle(
                  color: colorScheme.error,
                  fontSize: 13.0,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
