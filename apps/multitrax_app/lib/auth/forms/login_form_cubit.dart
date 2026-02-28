import 'package:bloc/bloc.dart';
import 'package:formz/formz.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum EmailValidationError { invalid }

class EmailInput extends FormzInput<String, EmailValidationError> {
  const EmailInput.pure() : super.pure('');
  const EmailInput.dirty([super.value = '']) : super.dirty();

  static final _emailRegex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  @override
  EmailValidationError? validator(String value) {
    if (_emailRegex.hasMatch(value.trim())) {
      return null;
    }
    return EmailValidationError.invalid;
  }
}

enum PasswordValidationError { tooShort }

class PasswordInput extends FormzInput<String, PasswordValidationError> {
  const PasswordInput.pure() : super.pure('');
  const PasswordInput.dirty([super.value = '']) : super.dirty();

  @override
  PasswordValidationError? validator(String value) {
    if (value.length >= 6) return null;
    return PasswordValidationError.tooShort;
  }
}

class LoginFormState {
  const LoginFormState({
    this.email = const EmailInput.pure(),
    this.password = const PasswordInput.pure(),
    this.isSignUp = false,
    this.status = FormzSubmissionStatus.initial,
    this.errorMessage,
  });

  final EmailInput email;
  final PasswordInput password;
  final bool isSignUp;
  final FormzSubmissionStatus status;
  final String? errorMessage;

  bool get isValid => Formz.validate([email, password]);

  LoginFormState copyWith({
    EmailInput? email,
    PasswordInput? password,
    bool? isSignUp,
    FormzSubmissionStatus? status,
    String? errorMessage,
  }) {
    return LoginFormState(
      email: email ?? this.email,
      password: password ?? this.password,
      isSignUp: isSignUp ?? this.isSignUp,
      status: status ?? this.status,
      errorMessage: errorMessage,
    );
  }
}

class LoginFormCubit extends Cubit<LoginFormState> {
  LoginFormCubit({
    required SupabaseClient supabaseClient,
  })  : _supabaseClient = supabaseClient,
        super(const LoginFormState());

  final SupabaseClient _supabaseClient;

  void emailChanged(String value) {
    emit(
      state.copyWith(
        email: EmailInput.dirty(value.trim()),
        errorMessage: null,
      ),
    );
  }

  void passwordChanged(String value) {
    emit(
      state.copyWith(
        password: PasswordInput.dirty(value),
        errorMessage: null,
      ),
    );
  }

  void toggleMode() {
    emit(
      state.copyWith(
        isSignUp: !state.isSignUp,
        errorMessage: null,
      ),
    );
  }

  Future<void> submit() async {
    final email = EmailInput.dirty(state.email.value);
    final password = PasswordInput.dirty(state.password.value);
    final isValid = Formz.validate([email, password]);
    if (!isValid) {
      emit(state.copyWith(email: email, password: password));
      return;
    }

    emit(state.copyWith(status: FormzSubmissionStatus.inProgress, errorMessage: null));
    try {
      if (state.isSignUp) {
        await _supabaseClient.auth.signUp(
          email: email.value,
          password: password.value,
        );
        await _supabaseClient.auth.signInWithPassword(
          email: email.value,
          password: password.value,
        );
      } else {
        await _supabaseClient.auth.signInWithPassword(
          email: email.value,
          password: password.value,
        );
      }

      emit(state.copyWith(status: FormzSubmissionStatus.success));
    } on AuthException catch (error) {
      emit(
        state.copyWith(
          status: FormzSubmissionStatus.failure,
          errorMessage: error.message,
        ),
      );
    } catch (_) {
      emit(
        state.copyWith(
          status: FormzSubmissionStatus.failure,
          errorMessage: 'Unexpected sign-in failure.',
        ),
      );
    }
  }
}
