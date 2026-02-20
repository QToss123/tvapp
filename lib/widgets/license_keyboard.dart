import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Mouse-clickable keyboard for license entry on TV/emulator.
/// The system IME on Android TV often doesn't respond to mouse; this widget does.
class LicenseKeyboard extends StatelessWidget {
  final TextEditingController controller;
  final int maxLength;

  const LicenseKeyboard({
    super.key,
    required this.controller,
    this.maxLength = 24,
  });

  static const List<String> _row1 = [
    'Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'P',
  ];
  static const List<String> _row2 = [
    'A', 'S', 'D', 'F', 'G', 'H', 'J', 'K', 'L',
  ];
  static const List<String> _row3 = [
    'Z', 'X', 'C', 'V', 'B', 'N', 'M', '-',
  ];
  static const List<String> _row4 = [
    '0', '1', '2', '3', '4', '5', '6', '7', '8', '9',
  ];

  void _onKeyTap(String key) {
    if (key == '⌫') {
      if (controller.text.isNotEmpty) {
        controller.text = controller.text.substring(0, controller.text.length - 1);
      }
    } else if (controller.text.length < maxLength) {
      controller.text += key;
    }
  }

  Widget _buildKey(BuildContext context, String label) {
    final isBackspace = label == '⌫';
    return Material(
      color: Colors.grey.shade800,
      child: InkWell(
        onTap: () => _onKeyTap(label),
        onTapDown: (_) => HapticFeedback.lightImpact(),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRow(BuildContext context, List<String> keys) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [for (final k in keys) Expanded(child: _buildKey(context, k))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final row1WithBackspace = [..._row1, '⌫'];
    return Container(
      color: Colors.grey.shade900,
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildRow(context, row1WithBackspace),
          _buildRow(context, _row2),
          _buildRow(context, _row3),
          _buildRow(context, _row4),
        ],
      ),
    );
  }
}
