import 'package:flutter_test/flutter_test.dart';
import 'package:formz/formz.dart';
import 'package:multitrax_app/songs/forms/song_forms.dart';

void main() {
  group('SongTitleInput', () {
    test('is invalid when empty', () {
      const input = SongTitleInput.dirty('');
      expect(input.displayError, SongTitleValidationError.empty);
    });

    test('is valid when non-empty', () {
      const input = SongTitleInput.dirty('My Song');
      expect(input.displayError, isNull);
    });
  });

  group('MemberEmailInput', () {
    test('is invalid for malformed email', () {
      const input = MemberEmailInput.dirty('not-an-email');
      expect(input.displayError, MemberEmailValidationError.invalid);
    });

    test('is valid for normal email', () {
      const input = MemberEmailInput.dirty('user@example.com');
      expect(Formz.validate([input]), isTrue);
    });
  });
}
