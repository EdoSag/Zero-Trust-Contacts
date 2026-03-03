import 'package:zerotrust_contacts/auth_status.dart';
import 'package:nowa_runtime/nowa_runtime.dart';

@NowaGenerated()
class AuthState {
  AuthState({required this.status, this.errorMessage});

  final AuthStatus status;

  final String? errorMessage;

  AuthState copyWith({AuthStatus? status, String? errorMessage}) {
    return AuthState(status: status ?? this.status, errorMessage: errorMessage);
  }
}
