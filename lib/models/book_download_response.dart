/// API response for course/book download.
/// Supports both plain download_url and encrypted (book_encryption_keys) responses.
class BookDownloadResponse {
  final int courseId;
  final String downloadUrl;
  final int expiresInSeconds;
  final BookEncryptionKeys? bookEncryptionKeys;

  BookDownloadResponse({
    required this.courseId,
    required this.downloadUrl,
    required this.expiresInSeconds,
    this.bookEncryptionKeys,
  });

  factory BookDownloadResponse.fromJson(Map<String, dynamic> json) {
    return BookDownloadResponse(
      courseId: json['course_id'] as int,
      downloadUrl: json['download_url'] as String,
      expiresInSeconds: (json['expires_in_seconds'] as num?)?.toInt() ?? 3600,
      bookEncryptionKeys: json['book_encryption_keys'] != null
          ? BookEncryptionKeys.fromJson(
              json['book_encryption_keys'] as Map<String, dynamic>,
            )
          : null,
    );
  }
}

class BookEncryptionKeys {
  final String bookId;
  final String encBookPath;
  final String keyEncB64;
  final String keyNonceB64;

  BookEncryptionKeys({
    required this.bookId,
    required this.encBookPath,
    required this.keyEncB64,
    required this.keyNonceB64,
  });

  factory BookEncryptionKeys.fromJson(Map<String, dynamic> json) {
    return BookEncryptionKeys(
      bookId: json['book_id'] as String,
      encBookPath: json['enc_book_path'] as String,
      keyEncB64: json['key_enc_b64'] as String,
      keyNonceB64: json['key_nonce_b64'] as String,
    );
  }
}
