import 'package:flutter/material.dart';

class AppTitle extends StatelessWidget {
  final String title;

  static const bool _isDev =
      bool.fromEnvironment('dev', defaultValue: false);

  const AppTitle({super.key, required this.title});

  /// 在任意 Widget 后追加 dev 标记
  static Widget wrap(Widget child) {
    if (!_isDev) return child;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        child,
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

  @override
  Widget build(BuildContext context) {
    return wrap(Text(title));
  }
}
