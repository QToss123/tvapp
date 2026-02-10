import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/book.dart';
import '../routes.dart';

class BookCard extends StatefulWidget {
  final Book book;
  final bool isFocused;

  const BookCard({super.key, required this.book, this.isFocused = false});

  @override
  State<BookCard> createState() => _BookCardState();
}

class _BookCardState extends State<BookCard> {
  bool _isHovered = false;

  static bool _isTv(BuildContext context) => MediaQuery.sizeOf(context).width >= 600;
  static double _fs(BuildContext context, double base) =>
      _isTv(context) ? base * 1.1 : base;
  static double _px(BuildContext context, double base) =>
      _isTv(context) ? base * 1.1 : base;

  @override
  Widget build(BuildContext context) {
    return Focus(
      child: Builder(
        builder: (context) {
          final hasFocus = Focus.of(context).hasFocus;
          final isHighlighted = hasFocus || widget.isFocused || _isHovered;
          return MouseRegion(
            onEnter: (_) => setState(() => _isHovered = true),
            onExit: (_) => setState(() => _isHovered = false),
            cursor: SystemMouseCursors.click,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: isHighlighted
                    ? Border.all(color: Colors.blueAccent, width: 2)
                    : null,
                boxShadow: isHighlighted
                    ? [
                        BoxShadow(
                          color: Colors.blueAccent.withOpacity(0.3),
                          blurRadius: 6,
                          spreadRadius: 0,
                        )
                      ]
                    : null,
              ),
              child: Card(
                clipBehavior: Clip.antiAlias,
                elevation: isHighlighted ? 8 : 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                color: Colors.grey.shade50,
                child: InkWell(
                  onTap: () {
                    Navigator.pushNamed(
                      context,
                      AppRoutes.reading,
                      arguments: widget.book,
                    );
                  },
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Thumbnail (same as sync screen)
                      Expanded(
                        flex: 3,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            ClipRect(
                              child: _buildThumbnail(),
                            ),
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: Container(
                                height: _px(context, 20),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Colors.transparent,
                                      Colors.black.withOpacity(0.6),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Title and progress section (same layout as sync screen)
                      Expanded(
                        flex: 2,
                        child: Container(
                          width: double.infinity,
                          padding: EdgeInsets.symmetric(
                            horizontal: _px(context, 4),
                            vertical: _px(context, 3),
                          ),
                          color: Colors.white,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Expanded(
                                child: Text(
                                  widget.book.title,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: _fs(context, 11),
                                    color: Colors.grey.shade900,
                                    height: 1.2,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                ),
                              ),
                              Text(
                                widget.book.author,
                                style: TextStyle(
                                  fontSize: _fs(context, 10),
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey.shade700,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildThumbnail() {
    final localPath = widget.book.thumbnailLocalPath;
    if (localPath != null && localPath.isNotEmpty) {
      final file = File(localPath);
      return Image.file(
        file,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildPlaceholderThumbnail(),
      );
    }
    final thumbUrl = widget.book.thumbnail;
    if (thumbUrl != null && thumbUrl.isNotEmpty && thumbUrl.startsWith('http')) {
      return CachedNetworkImage(
        imageUrl: thumbUrl,
        fit: BoxFit.cover,
        placeholder: (_, __) => _buildPlaceholderThumbnail(),
        errorWidget: (_, __, ___) => _buildPlaceholderThumbnail(),
      );
    }
    return _buildPlaceholderThumbnail();
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
