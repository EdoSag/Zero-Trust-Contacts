import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zerotrust_contacts/auth_event.dart';
import 'package:zerotrust_contacts/auth_state.dart';
import 'package:zerotrust_contacts/security_service.dart';
import 'package:nowa_runtime/nowa_runtime.dart';
import 'package:zerotrust_contacts/check_auth_status_event.dart';
import 'package:zerotrust_contacts/auth_status.dart';
import 'package:zerotrust_contacts/setup_master_password_event.dart';
import 'package:zerotrust_contacts/login_event.dart';
import 'package:zerotrust_contacts/logout_event.dart';

@NowaGenerated()
class AuthBloc extends Bloc<AuthEvent, AuthState> {
  AuthBloc(this.securityService) : super(AuthState(status: AuthStatus.initial)) {
    on<CheckAuthStatusEvent>(_onCheckAuthStatus);
    on<SetupMasterPasswordEvent>(_onSetupMasterPassword);
    on<LoginEvent>(_onLogin);
    on<LogoutEvent>(_onLogout);
  }

  final SecurityService securityService;

  Future<void> _onCheckAuthStatus(
    CheckAuthStatusEvent event,
    Emitter<AuthState> emit,
  ) async {
    final isInitialized = await securityService.isInitialized();
    if (!isInitialized) {
      emit(state.copyWith(status: AuthStatus.notSetup));
    } else if (securityService.isKeyAvailable()) {
      emit(state.copyWith(status: AuthStatus.authenticated));
    } else {
      emit(state.copyWith(status: AuthStatus.locked));
    }
  }

  Future<void> _onSetupMasterPassword(
    SetupMasterPasswordEvent event,
    Emitter<AuthState> emit,
  ) async {
    if (event.masterPassword.length < 12) {
      emit(
        state.copyWith(
          status: AuthStatus.error,
          errorMessage: 'Password must be at least 12 characters',
        ),
      );
      return;
    }
    await securityService.initializeFirstTime();
    await securityService.deriveKeyFromPassword(event.masterPassword);
    emit(state.copyWith(status: AuthStatus.authenticated));
  }

  Future<void> _onLogin(LoginEvent event, Emitter<AuthState> emit) async {
    try {
      await securityService.deriveKeyFromPassword(event.masterPassword);
      emit(state.copyWith(status: AuthStatus.authenticated));
    } catch (e) {
      emit(
        state.copyWith(
          status: AuthStatus.error,
          errorMessage: 'Invalid password',
        ),
      );
    }
  }

  Future<void> _onLogout(LogoutEvent event, Emitter<AuthState> emit) async {
    securityService.clearKey();
    emit(state.copyWith(status: AuthStatus.locked));
  }
}
