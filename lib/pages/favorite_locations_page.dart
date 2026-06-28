import 'package:flutter/material.dart';

import '../models/favorite_location.dart';
import '../services/favorite_location_store.dart';
import '../services/location_service.dart';
import '../widgets/app_title.dart';

class FavoriteLocationsPage extends StatefulWidget {
  const FavoriteLocationsPage({super.key});

  @override
  State<FavoriteLocationsPage> createState() => _FavoriteLocationsPageState();
}

class _FavoriteLocationsPageState extends State<FavoriteLocationsPage> {
  final _store = FavoriteLocationStore();
  final _locationService = LocationService();
  List<FavoriteLocation> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final items = await _store.load();
    if (mounted) {
      setState(() {
        _items = items;
        _loading = false;
      });
    }
  }

  Future<String?> _promptName({String initial = '', required String title}) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AnimatedBuilder(
        animation: controller,
        builder: (ctx, _) => AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: '如：家、公司',
              helperText: '请站在目标位置、静止片刻以获更准坐标',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: controller.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(ctx, controller.text),
              child: const Text('确定'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _add() async {
    final name = await _promptName(title: '命名常用位置');
    if (name == null || name.trim().isEmpty) return;
    if (!mounted) return;
    setState(() => _loading = true);
    final granted = await _locationService.ensurePermission();
    if (!granted) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('未授予定位权限，无法获取位置')));
      }
      return;
    }
    final loc = await _locationService.getCurrentLocation();
    if (loc == null) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('无法获取当前位置，请检查定位权限')));
      }
      return;
    }
    final items = await _store.add(name.trim(), loc.lat, loc.lon);
    if (mounted) {
      setState(() {
        _items = items;
        _loading = false;
      });
    }
  }

  Future<void> _rename(FavoriteLocation f) async {
    final name = await _promptName(initial: f.name, title: '重命名常用位置');
    if (name == null || name.trim().isEmpty) return;
    if (!mounted) return;
    final items = await _store.rename(f.id, name.trim());
    if (mounted) setState(() => _items = items);
  }

  Future<void> _delete(FavoriteLocation f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除常用位置'),
        content: Text('删除「${f.name}」？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true) {
      final items = await _store.remove(f.id);
      if (mounted) setState(() => _items = items);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const AppTitle(title: '常用位置')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  '还没有常用位置\n点右下角 +，在目标位置新增',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView.builder(
              itemCount: _items.length,
              itemBuilder: (_, i) {
                final f = _items[i];
                return ListTile(
                  leading: const Icon(Icons.place_outlined),
                  title: Text(f.name),
                  subtitle: Text(
                    '${f.lat.toStringAsFixed(4)}, ${f.lon.toStringAsFixed(4)}',
                  ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (v) {
                      if (v == 'rename') _rename(f);
                      if (v == 'delete') _delete(f);
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'rename', child: Text('重命名')),
                      PopupMenuItem(value: 'delete', child: Text('删除')),
                    ],
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _loading ? null : _add,
        tooltip: '新增常用位置',
        child: const Icon(Icons.add),
      ),
    );
  }
}
