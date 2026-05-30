import 'package:flutter/material.dart';

class AppTitle extends StatelessWidget {
  final String title;

  static const bool _isDev =
      bool.fromEnvironment('dev', defaultValue: false);

  const AppTitle({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    if (_isDev) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text(
              'dev',
              style: TextStyle(
                  fontSize: 10,
                  color: Colors.orange,
                  fontWeight: FontWeight.bold),
            ),
          ),
        ],
      );
    }
    return Text(title);
  }
}
