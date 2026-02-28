import 'package:formz/formz.dart';

enum SongTitleValidationError { empty }

class SongTitleInput extends FormzInput<String, SongTitleValidationError> {
  const SongTitleInput.pure() : super.pure('');
  const SongTitleInput.dirty([super.value = '']) : super.dirty();

  @override
  SongTitleValidationError? validator(String value) {
    if (value.trim().isNotEmpty) return null;
    return SongTitleValidationError.empty;
  }
}

enum MemberEmailValidationError { invalid }

class MemberEmailInput extends FormzInput<String, MemberEmailValidationError> {
  const MemberEmailInput.pure() : super.pure('');
  const MemberEmailInput.dirty([super.value = '']) : super.dirty();

  static final _emailRegex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  @override
  MemberEmailValidationError? validator(String value) {
    if (_emailRegex.hasMatch(value.trim())) {
      return null;
    }
    return MemberEmailValidationError.invalid;
  }
}
