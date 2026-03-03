import 'package:nowa_runtime/nowa_runtime.dart';
import 'package:zerotrust_contacts/security_service.dart';

@NowaGenerated()
class Contact {
  Contact({
    this.id,
    required this.encryptedName,
    required this.encryptedPhone,
    required this.encryptedEmail,
    required this.encryptedNotes,
    this.createdAt,
    this.updatedAt,
    this.source = 'Phone',
    this.isFavorite = false,
  });

  final String? id;

  final String encryptedName;

  final String encryptedPhone;

  final String encryptedEmail;

  final String encryptedNotes;

  final DateTime? createdAt;

  final DateTime? updatedAt;

  final String source;

  final bool isFavorite;

  Future<Map<String, String>> toPlainData(
    SecurityService securityService,
  ) async {
    return {
      'name': await securityService.decrypt(encryptedName),
      'phone': await securityService.decrypt(encryptedPhone),
      'email': await securityService.decrypt(encryptedEmail),
      'notes': await securityService.decrypt(encryptedNotes),
    };
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'encryptedName': encryptedName,
      'encryptedPhone': encryptedPhone,
      'encryptedEmail': encryptedEmail,
      'encryptedNotes': encryptedNotes,
      'createdAt': createdAt?.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
      'source': source,
      'isFavorite': isFavorite,
    };
  }

  Contact copyWith({
    String? id,
    String? encryptedName,
    String? encryptedPhone,
    String? encryptedEmail,
    String? encryptedNotes,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? source,
    bool? isFavorite,
  }) {
    return Contact(
      id: id ?? this.id,
      encryptedName: encryptedName ?? this.encryptedName,
      encryptedPhone: encryptedPhone ?? this.encryptedPhone,
      encryptedEmail: encryptedEmail ?? this.encryptedEmail,
      encryptedNotes: encryptedNotes ?? this.encryptedNotes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      source: source ?? this.source,
      isFavorite: isFavorite ?? this.isFavorite,
    );
  }

  static Future<Contact> fromPlainData({
    String? id,
    required String name,
    required String phone,
    required String email,
    required String notes,
    required SecurityService securityService,
    String source = 'Phone',
    bool isFavorite = false,
  }) async {
    return Contact(
      id: id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      encryptedName: await securityService.encrypt(name),
      encryptedPhone: await securityService.encrypt(phone),
      encryptedEmail: await securityService.encrypt(email),
      encryptedNotes: await securityService.encrypt(notes),
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      source: source,
      isFavorite: isFavorite,
    );
  }

  static Contact fromJson(Map<String, dynamic> json) {
    return Contact(
      id: json['id'] as String?,
      encryptedName: json['encryptedName'] as String,
      encryptedPhone: json['encryptedPhone'] as String,
      encryptedEmail: json['encryptedEmail'] as String,
      encryptedNotes: json['encryptedNotes'] as String,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : null,
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'] as String)
          : null,
      source: json['source'] as String? ?? 'Phone',
      isFavorite: json['isFavorite'] as bool? ?? false,
    );
  }
}
