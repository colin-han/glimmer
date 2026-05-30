import 'package:flutter/material.dart';

class StepProgressIndicator extends StatelessWidget {
  final int currentStep;
  final bool hasError;

  const StepProgressIndicator({
    super.key,
    required this.currentStep,
    this.hasError = false,
  });

  static const _steps = ['语音识别', '保存原文', 'AI 总结', '自动归类', '完成'];

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(_steps.length * 2 - 1, (i) {
        if (i.isOdd) {
          final stepIndex = i ~/ 2;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text('→',
                style: TextStyle(
                  color: stepIndex < currentStep ? Colors.green : Colors.grey,
                )),
          );
        }
        return _buildStep(context, i ~/ 2);
      }),
    );
  }

  Widget _buildStep(BuildContext context, int index) {
    final isCompleted = index < currentStep;
    final isCurrent = index == currentStep;
    final color = isCompleted
        ? Colors.green
        : isCurrent
            ? (hasError ? Colors.red : Theme.of(context).colorScheme.primary)
            : Colors.grey;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(
          radius: 14,
          backgroundColor: color.withValues(alpha: 0.2),
          child: isCompleted
              ? const Icon(Icons.check, size: 18, color: Colors.green)
              : Text('${index + 1}',
                  style: TextStyle(color: color, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 4),
        Text(_steps[index], style: TextStyle(fontSize: 12, color: color)),
      ],
    );
  }
}
