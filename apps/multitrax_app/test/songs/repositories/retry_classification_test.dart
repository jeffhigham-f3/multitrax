import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:multitrax_app/songs/repositories/supabase_song_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('treats network-style errors as retriable', () {
    expect(isRetriableSubmissionError(TimeoutException('timeout')), isTrue);
    expect(
      isRetriableSubmissionError(const SocketException('connection dropped')),
      isTrue,
    );
    expect(
      isRetriableSubmissionError(
        const StorageException('temporary failure', statusCode: '503'),
      ),
      isTrue,
    );
    expect(
      isRetriableSubmissionError(
        const PostgrestException(message: 'connection issue', code: '08006'),
      ),
      isTrue,
    );
  });

  test('treats auth/permission/validation errors as non-retriable', () {
    expect(
      isRetriableSubmissionError(
        const StorageException('forbidden', statusCode: '403'),
      ),
      isFalse,
    );
    expect(
      isRetriableSubmissionError(
        const PostgrestException(message: 'permission denied', code: '42501'),
      ),
      isFalse,
    );
    expect(
      isRetriableSubmissionError(
        const PostgrestException(message: 'invalid input', code: '22P02'),
      ),
      isFalse,
    );
  });
}
