class Book {
  final String title;
  final String author;
  final int progress; // 0..100
  final String? thumbnail; // Image URL or asset path
  final String? contentUrl; // URL to load book content in webview
  // Encryption metadata (optional)
  final String? encBookId;
  final String? encKeyB64;
  final String? encNonceB64;

  const Book({
    required this.title,
    required this.author,
    required this.progress,
    this.thumbnail,
    this.contentUrl,
    this.encBookId,
    this.encKeyB64,
    this.encNonceB64,
  });
}
