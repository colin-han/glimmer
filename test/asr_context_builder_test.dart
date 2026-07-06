import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_diary/services/asr_context_builder.dart';

void main() {
  group('buildAsrCorpusContext', () {
    test('hotwords + prompt 合并：同时包含 hotwords 与 dialog_ctx', () {
      final result = buildAsrCorpusContext(
        hotwords: 'glimmer,肖伟红',
        prompt: '我使用标准普通话。',
      );
      expect(result, isNotNull);
      final map = jsonDecode(result!) as Map<String, dynamic>;
      expect(map['hotwords'], [
        {'word': 'glimmer'},
        {'word': '肖伟红'},
      ]);
      expect(map['context_type'], 'dialog_ctx');
      expect(map['context_data'], [
        {'text': '我使用标准普通话。'},
      ]);
    });

    test('仅 hotwords：不含 context_type / context_data', () {
      final result = buildAsrCorpusContext(hotwords: 'glimmer,ears');
      final map = jsonDecode(result!) as Map<String, dynamic>;
      expect(map['hotwords'], [
        {'word': 'glimmer'},
        {'word': 'ears'},
      ]);
      expect(map.containsKey('context_type'), isFalse);
      expect(map.containsKey('context_data'), isFalse);
    });

    test('仅 prompt：不含 hotwords', () {
      final result = buildAsrCorpusContext(prompt: '我常驻西安市。');
      final map = jsonDecode(result!) as Map<String, dynamic>;
      expect(map.containsKey('hotwords'), isFalse);
      expect(map['context_type'], 'dialog_ctx');
      expect(map['context_data'], [
        {'text': '我常驻西安市。'},
      ]);
    });

    test('两者皆空：返回 null（不注入 corpus）', () {
      expect(buildAsrCorpusContext(), isNull);
      expect(buildAsrCorpusContext(hotwords: '', prompt: ''), isNull);
      expect(buildAsrCorpusContext(hotwords: '   ', prompt: '  '), isNull);
    });

    test('hotwords 去空白、去空项、trim', () {
      final result = buildAsrCorpusContext(hotwords: ' a , b , , c ');
      final map = jsonDecode(result!) as Map<String, dynamic>;
      expect(map['hotwords'], [
        {'word': 'a'},
        {'word': 'b'},
        {'word': 'c'},
      ]);
    });

    test('prompt 仅空白时按"无 prompt"处理，但仍可只注入 hotwords', () {
      final result = buildAsrCorpusContext(hotwords: 'glimmer', prompt: '   ');
      final map = jsonDecode(result!) as Map<String, dynamic>;
      expect(map['hotwords'], [
        {'word': 'glimmer'},
      ]);
      expect(map.containsKey('context_type'), isFalse);
    });
  });
}
