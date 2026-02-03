class Book {
  final String title;
  final String author;
  final int progress; // 0..100
  final String? thumbnail; // Image URL (for network load)
  final String? thumbnailLocalPath; // Local file path (for offline)
  final String? contentUrl; // URL to load book content in webview
  // Encryption metadata (optional)
  final String? encBookId;
  final String? encBookPath; // e.g. media/encrypted_media/book_xxx_encrypted.zip
  final String? encKeyB64;
  final String? encNonceB64;

  const Book({
    required this.title,
    required this.author,
    required this.progress,
    this.thumbnail,
    this.thumbnailLocalPath,
    this.contentUrl,
    this.encBookId,
    this.encBookPath,
    this.encKeyB64,
    this.encNonceB64,
  });
}
