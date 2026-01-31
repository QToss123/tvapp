import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/book.dart';
import '../routes.dart';

class BookCard extends StatelessWidget {
  final Book book;
  final bool isFocused;

  const BookCard({super.key, required this.book, this.isFocused = false});

  @override
  Widget build(BuildContext context) {
    return Focus(
      child: Builder(
        builder: (context) {
          final hasFocus = Focus.of(context).hasFocus;
          return InkWell(
            onTap: () {
              Navigator.pushNamed(
                context,
                AppRoutes.reading,
                arguments: book,
              );
            },
            borderRadius: BorderRadius.circular(8),
            child: Card(
      elevation: hasFocus || isFocused ? 8 : 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: hasFocus || isFocused
            ? const BorderSide(color: Colors.blue, width: 3)
            : BorderSide.none,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Thumbnail with title overlay
          Stack(
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                  child: AspectRatio(
                  aspectRatio: 2 / 3,
                  child: book.thumbnail != null && book.thumbnail!.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: book.thumbnail!,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => _buildPlaceholderThumbnail(),
                          errorWidget: (_, __, ___) => _buildPlaceholderThumbnail(),
                        )
                      : _buildPlaceholderThumbnail(),
                ),
              ),
              // Gradient overlay at bottom for title readability
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  height: 50,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withOpacity(0.8),
                      ],
                    ),
                  ),
                ),
              ),
              // Title overlay on thumbnail
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                  child: Text(
                    book.title,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      height: 1.2,
                      shadows: [
                        Shadow(
                          offset: Offset(0, 1),
                          blurRadius: 2,
                          color: Colors.black87,
                        ),
                      ],
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ],
          ),
          // Author section with better contrast
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(8),
              ),
            ),
            child: Text(
              book.author,
              style: TextStyle(
                fontSize: 10,
                color: Colors.grey.shade800,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    ),
  );
        },
      ),
    );
  }

  Widget _buildPlaceholderThumbnail() {
    return Container(
      color: Colors.grey.shade300,
      child: Center(
        child: Icon(
          Icons.auto_stories_rounded,
          size: 32,
          color: Colors.grey.shade600,
        ),
      ),
    );
  }
}
