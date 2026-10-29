import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/database_service.dart';

class MindmapScreen extends StatefulWidget {
  const MindmapScreen({super.key});
  @override
  State<MindmapScreen> createState() => _MindmapScreenState();
}

class _MindmapScreenState extends State<MindmapScreen> {
  static const _canvasSize = Size(2400, 1600);
  static const _nodeWidth = 230.0;
  final _canvasKey = GlobalKey();
  final TransformationController _transform = TransformationController();
  List<Map<String, Object?>> _nodes = [];
  List<Map<String, Object?>> _connections = [];
  List<Map<String, Object?>> _maps = [];
  int? _mapId;
  bool _loading = true;
  bool _connectMode = false;
  bool _canvasPanMode = false;
  int? _movingNodeId;
  int? _linkFrom;
  Offset? _linkPoint;

  Future<void> _load({int? selectMapId}) async {
    final db = context.read<DatabaseService>().db;
    if (db == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      var maps = await db.query('mindmaps', orderBy: 'id');
      if (maps.isEmpty) {
        final id = await db.insert('mindmaps', {'name': 'Mind Map'});
        maps = await db.query('mindmaps', orderBy: 'id');
        selectMapId ??= id;
      }
      final wanted = selectMapId ?? _mapId;
      final selected =
          maps.where((m) => m['id'] == wanted).firstOrNull ?? maps.first;
      final mapId = selected['id'] as int;
      final nodes = await db.query('mindmap_nodes',
          where: 'map_id = ?', whereArgs: [mapId], orderBy: 'id');
      final nodeIds = nodes.map((n) => n['id'] as int).toList();
      final connections = nodeIds.isEmpty
          ? <Map<String, Object?>>[]
          : await db.query('mindmap_connections',
              where:
                  'from_node_id IN (${List.filled(nodeIds.length, '?').join(',')})',
              whereArgs: nodeIds,
              orderBy: 'id');
      if (mounted)
        setState(() {
          _maps = maps;
          _mapId = mapId;
          _nodes = nodes;
          _connections = connections;
          _loading = false;
        });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not load mind map: $e')));
    }
  }

  Future<void> _edit([Map<String, Object?>? node]) async {
    final title = TextEditingController(text: '${node?['title'] ?? ''}');
    final content = TextEditingController(text: '${node?['content'] ?? ''}');
    final color = TextEditingController(text: '${node?['color'] ?? '#00d4ff'}');
    int? parentId = node?['parent_id'] as int?;
    final candidates = _nodes
        .where((n) =>
            n['id'] != node?['id'] &&
            !_isDescendant(n['id'] as int, node?['id'] as int?))
        .toList();
    final result = await showDialog<_NodeEdit>(
        context: context,
        builder: (ctx) => StatefulBuilder(
            builder: (ctx, refresh) => AlertDialog(
                  title: Text(node == null ? 'Add mind map node' : 'Edit node'),
                  content: SizedBox(
                      width: 480,
                      child: SingleChildScrollView(
                          child:
                              Column(mainAxisSize: MainAxisSize.min, children: [
                        TextField(
                            controller: title,
                            autofocus: true,
                            decoration:
                                const InputDecoration(labelText: 'Title')),
                        TextField(
                            controller: content,
                            minLines: 3,
                            maxLines: 7,
                            decoration: const InputDecoration(
                                labelText: 'Details / notes')),
                        TextField(
                            controller: color,
                            decoration: InputDecoration(
                                labelText: 'Node color (hex)',
                                prefixIcon: Icon(Icons.circle,
                                    color: _parseColor(color.text)))),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<int?>(
                            value: parentId,
                            decoration: const InputDecoration(
                                labelText: 'Hierarchy / parent'),
                            items: [
                              const DropdownMenuItem<int?>(
                                  value: null, child: Text('Top-level node')),
                              for (final candidate in candidates)
                                DropdownMenuItem<int?>(
                                    value: candidate['id'] as int,
                                    child: Text('${candidate['title']}',
                                        overflow: TextOverflow.ellipsis)),
                            ],
                            onChanged: (value) =>
                                refresh(() => parentId = value)),
                      ]))),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Cancel')),
                    FilledButton(
                        onPressed: () => Navigator.pop(
                            ctx,
                            _NodeEdit(title.text.trim(), content.text.trim(),
                                color.text.trim(), parentId)),
                        child: const Text('Save'))
                  ],
                )));
    title.dispose();
    content.dispose();
    color.dispose();
    if (result == null || result.title.isEmpty) return;
    final db = context.read<DatabaseService>().db!;
    final colorValue = _validHex(result.color) ? result.color : '#00d4ff';
    if (node == null) {
      final i = _nodes.length;
      await db.insert('mindmap_nodes', {
        'map_id': _mapId,
        'title': result.title,
        'content': result.content,
        'color': colorValue,
        'parent_id': result.parentId,
        'x': 180.0 + (i % 4) * 300,
        'y': 140.0 + (i ~/ 4) * 190
      });
    } else {
      await db.update('mindmap_nodes', {
        'title': result.title,
        'content': result.content,
        'color': colorValue,
        'parent_id': result.parentId
      }, where: 'id = ?', whereArgs: [node['id']]);
    }
    await _load();
  }

  bool _isDescendant(int candidate, int? ancestor) {
    if (ancestor == null) return false;
    var parent = _nodes
        .where((n) => n['id'] == candidate)
        .firstOrNull?['parent_id'] as int?;
    final seen = <int>{};
    while (parent != null && seen.add(parent)) {
      if (parent == ancestor) return true;
      parent = _nodes.where((n) => n['id'] == parent).firstOrNull?['parent_id']
          as int?;
    }
    return false;
  }

  Future<void> _connectDialog(Map<String, Object?> node) async {
    final others = _nodes.where((n) => n['id'] != node['id']).toList();
    if (others.isEmpty) return;
    int? target = others.first['id'] as int;
    final label = TextEditingController();
    final saved = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
            builder: (ctx, refresh) => AlertDialog(
                  title: const Text('Connect nodes'),
                  content: Column(mainAxisSize: MainAxisSize.min, children: [
                    DropdownButtonFormField<int>(
                        value: target,
                        items: [
                          for (final n in others)
                            DropdownMenuItem(
                                value: n['id'] as int,
                                child: Text('${n['title']}'))
                        ],
                        onChanged: (v) => refresh(() => target = v)),
                    TextField(
                        controller: label,
                        decoration: const InputDecoration(
                            labelText: 'Relationship label (optional)')),
                  ]),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel')),
                    FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Connect'))
                  ],
                )));
    final text = label.text.trim();
    label.dispose();
    if (saved != true || target == null) return;
    await _insertConnection(node['id'] as int, target!, text);
  }

  Future<void> _insertConnection(int from, int to, [String label = '']) async {
    if (from == to) return;
    final exists = _connections
        .any((c) => c['from_node_id'] == from && c['to_node_id'] == to);
    if (!exists)
      await context.read<DatabaseService>().db!.insert('mindmap_connections',
          {'from_node_id': from, 'to_node_id': to, 'label': label});
    await _load();
  }

  Future<void> _switchMap() async {
    final db = context.read<DatabaseService>().db!;
    final maps = List<Map<String, Object?>>.from(_maps);
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Mind maps'),
        children: [
          for (final m in maps)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, 'map:${m['id']}'),
              child: Text('${m['name']}'),
            ),
          const Divider(),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'new'),
            child: const Text('+ Add new mind map'),
          ),
        ],
      ),
    );
    if (choice == null) return;
    if (choice == 'new') {
      final controller = TextEditingController(text: 'New Mind Map');
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('New mind map'),
          content: TextField(controller: controller, decoration: const InputDecoration(labelText: 'Name')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Create')),
          ],
        ),
      );
      final name = controller.text.trim();
      controller.dispose();
      if (ok != true) return;
      final id = await db.insert('mindmaps',
          {'name': name.isEmpty ? 'New Mind Map' : name});
      await _load(selectMapId: id);
      return;
    }
    if (choice.startsWith('map:')) {
      final id = int.tryParse(choice.substring(5));
      if (id != null) await _load(selectMapId: id);
    }
  }

  Future<void> _deleteNode(Map<String, Object?> node) async {
    final yes = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: const Text('Delete node?'),
                content: Text(
                    '"${node['title']}" and its connections will be removed. Its children will become top-level nodes.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Delete'))
                ]));
    if (yes != true) return;
    final db = context.read<DatabaseService>().db!;
    await db.transaction((txn) async {
      await txn.update('mindmap_nodes', {'parent_id': node['parent_id']},
          where: 'map_id = ? AND parent_id = ?',
          whereArgs: [_mapId, node['id']]);
      await txn.delete('mindmap_connections',
          where: 'from_node_id = ? OR to_node_id = ?',
          whereArgs: [node['id'], node['id']]);
      await txn
          .delete('mindmap_nodes', where: 'id = ?', whereArgs: [node['id']]);
    });
    await _load();
  }

  Offset _canvasLocal(Offset global) {
    final box = _canvasKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return global;
    return _transform.toScene(box.globalToLocal(global));
  }

  void _move(Map<String, Object?> node, Offset delta) {
    final i = _nodes.indexWhere((n) => n['id'] == node['id']);
    if (i < 0) return;
    final scale = _transform.value.getMaxScaleOnAxis().clamp(.1, 10.0);
    final x = ((_nodes[i]['x'] as num?)?.toDouble() ?? 0) + delta.dx / scale;
    final y = ((_nodes[i]['y'] as num?)?.toDouble() ?? 0) + delta.dy / scale;
    setState(() {
      final updated = Map<String, Object?>.from(_nodes[i]);
      updated['x'] = x;
      updated['y'] = y;
      _nodes = [..._nodes]..[i] = updated;
    });
  }

  void _startNodeDrag(Map<String, Object?> node, DragStartDetails details) {
    if (_canvasPanMode) return;
    setState(() {
      if (_connectMode) {
        _linkFrom = node['id'] as int;
        _linkPoint = _canvasLocal(details.globalPosition);
      } else {
        _movingNodeId = node['id'] as int;
      }
    });
  }

  void _updateNodeDrag(DragUpdateDetails details) {
    if (_connectMode && _linkFrom != null)
      setState(() => _linkPoint = _canvasLocal(details.globalPosition));
    else if (!_connectMode && !_canvasPanMode && _movingNodeId != null) {
      final node = _nodes.where((n) => n['id'] == _movingNodeId).firstOrNull;
      if (node != null) _move(node, details.delta);
    }
  }

  Future<void> _finishNodeDrag(DragEndDetails details) async {
    if (!_connectMode || _linkFrom == null) {
      final id = _movingNodeId;
      _movingNodeId = null;
      if (id != null) {
        final node = _nodes.where((n) => n['id'] == id).firstOrNull;
        if (node != null) {
          await context.read<DatabaseService>().db!.update(
              'mindmap_nodes', {'x': node['x'], 'y': node['y']},
              where: 'id = ?', whereArgs: [id]);
        }
      }
      return;
    }
    final point = _linkPoint;
    if (point == null) return;
    final from = _linkFrom!;
    final target = _nodes.where((n) {
      final x = (n['x'] as num?)?.toDouble() ?? 0;
      final y = (n['y'] as num?)?.toDouble() ?? 0;
      return n['id'] != from &&
          point.dx >= x &&
          point.dx <= x + _nodeWidth &&
          point.dy >= y &&
          point.dy <= y + 180;
    }).firstOrNull;
    setState(() {
      _linkFrom = null;
      _linkPoint = null;
    });
    if (target != null) await _insertConnection(from, target['id'] as int);
  }

  Future<void> _autoLayout() async {
    if (_nodes.isEmpty) return;
    final db = context.read<DatabaseService>().db!;
    final root = Offset(
        _canvasSize.width / 2 - _nodeWidth / 2, _canvasSize.height / 2 - 80);
    final roots = _nodes.where((n) => n['parent_id'] == null).toList();
    final placed = <int, Offset>{};
    void place(Map<String, Object?> n, Offset at, int depth) {
      final id = n['id'] as int;
      if (placed.containsKey(id)) return;
      placed[id] = at;
      final children = _nodes.where((c) => c['parent_id'] == id).toList();
      for (var i = 0; i < children.length; i++) {
        final offset = (i - (children.length - 1) / 2) * 260.0;
        place(children[i], Offset(at.dx + offset, at.dy + 210), depth + 1);
      }
    }

    if (roots.length <= 1) {
      if (roots.isNotEmpty) place(roots.first, root, 0);
    } else {
      for (var i = 0; i < roots.length; i++) {
        final a = (i / roots.length) * math.pi * 2 - math.pi / 2;
        place(roots[i], root + Offset(math.cos(a) * 440, math.sin(a) * 360), 0);
      }
    }
    for (final n in _nodes) {
      final id = n['id'] as int;
      if (!placed.containsKey(id))
        place(
            n,
            Offset(root.dx + (placed.length % 4) * 300,
                root.dy + (placed.length ~/ 4) * 220),
            0);
    }
    await db.transaction((txn) async {
      for (final entry in placed.entries) {
        await txn.update(
            'mindmap_nodes', {'x': entry.value.dx, 'y': entry.value.dy},
            where: 'id = ?', whereArgs: [entry.key]);
      }
    });
    await _load();
  }

  Future<void> _clear() async {
    if (_nodes.isEmpty) return;
    final yes = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: const Text('Clear mind map?'),
                content: Text(
                    'Delete all ${_nodes.length} nodes and ${_connections.length} connections?'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Clear all'))
                ]));
    if (yes != true) return;
    final db = context.read<DatabaseService>().db!;
    final ids = _nodes.map((n) => n['id'] as int).toList();
    await db.transaction((txn) async {
      if (ids.isNotEmpty) {
        final slots = List.filled(ids.length, '?').join(',');
        await txn.delete('mindmap_connections',
            where: 'from_node_id IN ($slots) OR to_node_id IN ($slots)',
            whereArgs: [...ids, ...ids]);
      }
      await txn
          .delete('mindmap_nodes', where: 'map_id = ?', whereArgs: [_mapId]);
    });
    await _load();
  }

  Future<void> _manageConnections() async {
    await showDialog<void>(
        context: context,
        builder: (ctx) => StatefulBuilder(
            builder: (ctx, refresh) => AlertDialog(
                  title: const Text('Connections'),
                  content: SizedBox(
                      width: 440,
                      child: _connections.isEmpty
                          ? const Text('No connections yet.')
                          : ListView(shrinkWrap: true, children: [
                              for (final c in _connections)
                                ListTile(
                                  title: Text(
                                      '${_nodeTitle(c['from_node_id'])} → ${_nodeTitle(c['to_node_id'])}'),
                                  subtitle: Text('${c['label'] ?? ''}'.isEmpty
                                      ? 'No label'
                                      : '${c['label']}'),
                                  trailing: IconButton(
                                      icon: const Icon(Icons.delete_outline),
                                      onPressed: () async {
                                        await context
                                            .read<DatabaseService>()
                                            .db!
                                            .delete('mindmap_connections',
                                                where: 'id = ?',
                                                whereArgs: [c['id']]);
                                        await _load();
                                        refresh(() {});
                                      }),
                                )
                            ])),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Done'))
                  ],
                )));
  }

  Future<void> _createMap() async {
    final name = await _mapNameDialog(title: 'Create mind map');
    if (name == null || name.trim().isEmpty) return;
    final id = await context
        .read<DatabaseService>()
        .db!
        .insert('mindmaps', {'name': name.trim()});
    await _load(selectMapId: id);
  }

  Future<void> _renameMap() async {
    final current = _maps.where((m) => m['id'] == _mapId).firstOrNull;
    if (current == null) return;
    final name = await _mapNameDialog(
        title: 'Rename mind map', initial: '${current['name']}');
    if (name == null || name.trim().isEmpty) return;
    await context.read<DatabaseService>().db!.update(
        'mindmaps', {'name': name.trim()},
        where: 'id = ?', whereArgs: [_mapId]);
    await _load();
  }

  Future<String?> _mapNameDialog(
      {required String title, String initial = ''}) async {
    final controller = TextEditingController(text: initial);
    final result = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
              title: Text(title),
              content: TextField(
                  controller: controller,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Name'),
                  onSubmitted: (value) => Navigator.pop(ctx, value)),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () => Navigator.pop(ctx, controller.text),
                    child: const Text('Save'))
              ]));
    controller.dispose();
    return result;
  }

  Future<void> _deleteMap() async {
    if (_maps.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Keep at least one mind map.')));
      return;
    }
    final selected = _maps.where((m) => m['id'] == _mapId).firstOrNull;
    if (selected == null) return;
    final yes = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
              title: const Text('Delete mind map?'),
              content: Text(
                  'Delete "${selected['name']}" and its ${_nodes.length} nodes?'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Delete'))
              ],
            ));
    if (yes != true) return;
    final id = _mapId!;
    final db = context.read<DatabaseService>().db!;
    await db.transaction((txn) async {
      await txn.delete('mindmap_connections',
          where:
              'from_node_id IN (SELECT id FROM mindmap_nodes WHERE map_id = ?) OR to_node_id IN (SELECT id FROM mindmap_nodes WHERE map_id = ?)',
          whereArgs: [id, id]);
      await txn.delete('mindmap_nodes', where: 'map_id = ?', whereArgs: [id]);
      await txn.delete('mindmaps', where: 'id = ?', whereArgs: [id]);
    });
    final fallback = _maps.firstWhere((m) => m['id'] != id)['id'] as int;
    await _load(selectMapId: fallback);
  }

  void _selectMap(int? value) {
    if (value == null || value == _mapId) return;
    setState(() {
      _loading = true;
      _connectMode = false;
      _linkFrom = null;
      _linkPoint = null;
    });
    _transform.value = Matrix4.identity();
    _load(selectMapId: value);
  }

  String _nodeTitle(Object? id) =>
      '${_nodes.where((n) => n['id'] == id).firstOrNull?['title'] ?? 'Missing node'}';
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            title: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.account_tree_outlined, size: 21),
              const SizedBox(width: 8),
              DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                      value: _mapId,
                      isDense: true,
                      items: [
                        for (final map in _maps)
                          DropdownMenuItem(
                              value: map['id'] as int,
                              child: ConstrainedBox(
                                  constraints:
                                      const BoxConstraints(maxWidth: 190),
                                  child: Text('${map['name']}',
                                      overflow: TextOverflow.ellipsis)))
                      ],
                      onChanged: _selectMap)),
              PopupMenuButton<String>(
                  tooltip: 'Mind map actions',
                  onSelected: (v) {
                    if (v == 'new')
                      _createMap();
                    else if (v == 'rename')
                      _renameMap();
                    else if (v == 'delete') _deleteMap();
                  },
                  itemBuilder: (_) => const [
                        PopupMenuItem(
                            value: 'new', child: Text('New mind map')),
                        PopupMenuItem(
                            value: 'rename', child: Text('Rename this map')),
                        PopupMenuItem(
                            value: 'delete', child: Text('Delete this map'))
                      ]),
            ]),
            actions: [
              IconButton(
                  tooltip: 'Auto layout',
                  onPressed: _autoLayout,
                  icon: const Icon(Icons.auto_awesome_mosaic_outlined)),
              IconButton(
                  tooltip: 'Manage connections',
                  onPressed: _manageConnections,
                  icon: const Icon(Icons.share_outlined)),
              IconButton(
                  tooltip: 'Fit map',
                  onPressed: () => _transform.value = Matrix4.identity(),
                  icon: const Icon(Icons.fit_screen)),
              IconButton(
                  tooltip: 'Refresh',
                  onPressed: _load,
                  icon: const Icon(Icons.refresh)),
              IconButton(
                  tooltip: 'Clear map',
                  onPressed: _clear,
                  icon: const Icon(Icons.delete_sweep_outlined)),
            ],
        ),
        floatingActionButton: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            FloatingActionButton.small(
                heroTag: 'map',
                tooltip: 'Switch/add mind map',
                onPressed: _switchMap,
                child: const Icon(Icons.layers)),
            const SizedBox(height: 8),
            FloatingActionButton.small(
                heroTag: 'pan',
                tooltip: _canvasPanMode ? 'Drag nodes' : 'Pan canvas',
                onPressed: () =>
                    setState(() => _canvasPanMode = !_canvasPanMode),
                child: Icon(_canvasPanMode ? Icons.touch_app : Icons.pan_tool)),
            const SizedBox(height: 8),
            FloatingActionButton.small(
                heroTag: 'connect',
                tooltip: _connectMode
                    ? 'Exit connect mode'
                    : 'Connect nodes (drag from node)',
                onPressed: () => setState(() => _connectMode = !_connectMode),
                child: Icon(_connectMode ? Icons.close : Icons.timeline)),
            const SizedBox(height: 8),
            FloatingActionButton.extended(
                heroTag: 'add',
                onPressed: () => _edit(),
                icon: const Icon(Icons.add),
                label: const Text('Add node')),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(children: [
                Material(
                  color: Theme.of(context).colorScheme.surfaceVariant,
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    child: Row(children: [
                      FilterChip(
                          selected: !_connectMode && !_canvasPanMode,
                          avatar: const Icon(Icons.open_with, size: 18),
                          label: const Text('Move nodes'),
                          onSelected: (_) => setState(() {
                                _connectMode = false;
                                _canvasPanMode = false;
                                _linkFrom = null;
                                _linkPoint = null;
                              })),
                      const SizedBox(width: 6),
                      FilterChip(
                          selected: _canvasPanMode,
                          avatar: const Icon(Icons.pan_tool_alt_outlined,
                              size: 18),
                          label: const Text('Move canvas'),
                          onSelected: (_) => setState(() {
                                _canvasPanMode = true;
                                _connectMode = false;
                                _linkFrom = null;
                                _linkPoint = null;
                              })),
                      const SizedBox(width: 6),
                      FilterChip(
                          selected: _connectMode,
                          avatar: const Icon(Icons.link, size: 18),
                          label: const Text('Connect nodes'),
                          onSelected: (_) => setState(() {
                                _connectMode = true;
                                _canvasPanMode = false;
                                _linkFrom = null;
                                _linkPoint = null;
                              })),
                      const SizedBox(width: 12),
                      Expanded(
                          child: Text(
                              'Drag nodes in Move nodes mode · use the map menu to create more maps',
                              style: Theme.of(context).textTheme.bodySmall)),
                    ]),
                  ),
                ),
                Expanded(
                  child: _nodes.isEmpty
                      ? Center(
                          child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                              const Icon(Icons.account_tree_outlined,
                                  size: 52),
                              const SizedBox(height: 12),
                              Text('Start with a central idea',
                                  style:
                                      Theme.of(context).textTheme.titleLarge),
                              const Text(
                                  'Add nodes, set hierarchy, move them, and connect related ideas.')
                            ]))
                      : InteractiveViewer(
                          key: _canvasKey,
                          transformationController: _transform,
                          constrained: false,
                          panEnabled: _canvasPanMode,
                          scaleEnabled: true,
                          minScale: .2,
                          maxScale: 3,
                          boundaryMargin: const EdgeInsets.all(400),
                          child: SizedBox(
                            width: _canvasSize.width,
                            height: _canvasSize.height,
                            child: Stack(children: [
                              Positioned.fill(
                                  child: CustomPaint(
                                      painter: _ConnectionsPainter(
                                          nodes: _nodes,
                                          connections: _connections,
                                          previewFrom: _linkFrom == null
                                              ? null
                                              : _nodes
                                                  .where((n) =>
                                                      n['id'] == _linkFrom)
                                                  .firstOrNull,
                                          previewPoint: _linkPoint,
                                          theme: Theme.of(context)))),
                              for (final node in _nodes) _nodeWidget(node),
                            ]),
                          ),
                        ),
                ),
              ]),
      );

  Widget _nodeWidget(Map<String, Object?> node) {
    final x = (node['x'] as num?)?.toDouble() ?? 0;
    final y = (node['y'] as num?)?.toDouble() ?? 0;
    final color = _parseColor('${node['color'] ?? '#00d4ff'}');
    final hasParent = node['parent_id'] != null;
    final card = Card(
      color: Theme.of(context).colorScheme.surface,
      elevation: 4,
      shape: RoundedRectangleBorder(
          side: BorderSide(color: color, width: 2),
          borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _connectMode ? null : () => _edit(node),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                if (hasParent)
                  const Padding(
                    padding: EdgeInsets.only(right: 5),
                    child:
                        Icon(Icons.subdirectory_arrow_right, size: 16),
                  ),
                Expanded(
                  child: Text('${node['title']}',
                      style: Theme.of(context).textTheme.titleSmall),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Node actions',
                  onSelected: (v) {
                    if (v == 'connect') {
                      _connectDialog(node);
                    } else if (v == 'edit') {
                      _edit(node);
                    } else {
                      _deleteNode(node);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'connect', child: Text('Connect to…')),
                    PopupMenuItem(value: 'edit', child: Text('Edit')),
                    PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
              ]),
              if ('${node['content'] ?? ''}'.isNotEmpty)
                Text('${node['content']}',
                    maxLines: 5,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
    return Positioned(
      left: x,
      top: y,
      child: GestureDetector(
        onPanStart: (d) => _startNodeDrag(node, d),
        onPanUpdate: (d) {
          if (_connectMode) {
            _updateNodeDrag(d);
          } else if (!_canvasPanMode) {
            _move(node, d.delta);
          }
        },
        onPanEnd: _finishNodeDrag,
        child: SizedBox(width: _nodeWidth, child: card),
      ),
    );
  }
}

class _NodeEdit {
  final String title, content, color;
  final int? parentId;
  const _NodeEdit(this.title, this.content, this.color, this.parentId);
}

bool _validHex(String value) =>
    RegExp(r'^#?[0-9a-fA-F]{6}$').hasMatch(value);
Color _parseColor(String value) {
  final clean = value.replaceFirst('#', '');
  if (clean.length != 6 || int.tryParse(clean, radix: 16) == null)
    return const Color(0xff00d4ff);
  return Color(0xff000000 | int.parse(clean, radix: 16));
}

class _ConnectionsPainter extends CustomPainter {
  final List<Map<String, Object?>> nodes, connections;
  final Map<String, Object?>? previewFrom;
  final Offset? previewPoint;
  final ThemeData theme;
  _ConnectionsPainter(
      {required this.nodes,
      required this.connections,
      required this.previewFrom,
      required this.previewPoint,
      required this.theme});
  Offset _center(Map<String, Object?> node) => Offset(
      ((node['x'] as num?)?.toDouble() ?? 0) + 115,
      ((node['y'] as num?)?.toDouble() ?? 0) + 45);
  @override
  void paint(Canvas canvas, Size size) {
    for (final node in nodes) {
      final parentId = node['parent_id'];
      if (parentId == null) continue;
      final parent = nodes.where((n) => n['id'] == parentId).firstOrNull;
      if (parent == null) continue;
      final p = Paint()
        ..color = theme.colorScheme.tertiary.withOpacity(.7)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      canvas.drawLine(_center(parent), _center(node), p);
    }
    final paint = Paint()
      ..color = theme.colorScheme.primary.withOpacity(.72)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    final textStyle = TextStyle(
        color: theme.colorScheme.onSurfaceVariant,
        fontSize: 12,
        backgroundColor: theme.colorScheme.surface);
    for (final c in connections) {
      final from = nodes.where((n) => n['id'] == c['from_node_id']).firstOrNull;
      final to = nodes.where((n) => n['id'] == c['to_node_id']).firstOrNull;
      if (from == null || to == null) continue;
      final start = _center(from), end = _center(to);
      canvas.drawLine(start, end, paint);
      final label = '${c['label'] ?? ''}';
      if (label.isNotEmpty) {
        final tp = TextPainter(
            text: TextSpan(text: label, style: textStyle),
            textDirection: TextDirection.ltr)
          ..layout(maxWidth: 180);
        tp.paint(
            canvas, Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2));
      }
    }
    if (previewFrom != null && previewPoint != null) {
      final p = Paint()
        ..color = theme.colorScheme.secondary
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke;
      canvas.drawLine(_center(previewFrom!), previewPoint!, p);
    }
  }

  @override
  bool shouldRepaint(covariant _ConnectionsPainter old) =>
      old.nodes != nodes ||
      old.connections != connections ||
      old.previewFrom != previewFrom ||
      old.previewPoint != previewPoint ||
      old.theme != theme;
}