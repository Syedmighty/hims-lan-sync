import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'sync_service.dart';
import 'sync_provider.dart';

/// Conflict Resolver Screen
/// UI for viewing and resolving sync conflicts between server and client data
class ConflictResolverScreen extends ConsumerWidget {
  const ConflictResolverScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conflicts = ref.watch(conflictsProvider);
    final syncActions = ref.watch(syncActionsProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sync Conflicts'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => syncActions.fetchConflicts(),
            tooltip: 'Refresh conflicts',
          ),
        ],
      ),
      body: conflicts.isEmpty
          ? _buildEmptyState()
          : _buildConflictList(context, ref, conflicts),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Icon(Icons.check_circle, size: 64, color: Colors.green),
          SizedBox(height: 16),
          Text(
            'No conflicts found',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
          ),
          SizedBox(height: 8),
          Text(
            'All data is synchronized',
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildConflictList(
    BuildContext context,
    WidgetRef ref,
    List<SyncConflict> conflicts,
  ) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: conflicts.length,
      itemBuilder: (context, index) {
        final conflict = conflicts[index];
        return ConflictCard(
          conflict: conflict,
          onResolve: (resolution, customData) async {
            final syncActions = ref.read(syncActionsProvider.notifier);
            await syncActions.resolveConflict(
              conflict.conflictId,
              resolution,
              customData,
            );

            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Conflict resolved')),
              );
            }
          },
        );
      },
    );
  }
}

/// Conflict Card Widget
class ConflictCard extends StatefulWidget {
  final SyncConflict conflict;
  final Future<void> Function(ConflictResolution, Map<String, dynamic>?) onResolve;

  const ConflictCard({
    Key? key,
    required this.conflict,
    required this.onResolve,
  }) : super(key: key);

  @override
  State<ConflictCard> createState() => _ConflictCardState();
}

class _ConflictCardState extends State<ConflictCard> {
  bool _isExpanded = false;
  bool _isResolving = false;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.warning, color: Colors.orange),
            title: Text(
              '${widget.conflict.entityType} - Conflict',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              widget.conflict.reason ?? 'Data mismatch detected',
              style: const TextStyle(fontSize: 12),
            ),
            trailing: IconButton(
              icon: Icon(_isExpanded ? Icons.expand_less : Icons.expand_more),
              onPressed: () => setState(() => _isExpanded = !_isExpanded),
            ),
          ),
          if (_isExpanded) ...[
            const Divider(height: 1),
            _buildConflictDetails(),
            const Divider(height: 1),
            _buildResolutionButtons(),
          ],
        ],
      ),
    );
  }

  Widget _buildConflictDetails() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Conflict Details',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildDataColumn(
                  'Server Version',
                  widget.conflict.serverData,
                  widget.conflict.serverTimestamp,
                  Colors.blue,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildDataColumn(
                  'Client Version',
                  widget.conflict.clientData,
                  widget.conflict.clientTimestamp,
                  Colors.green,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDataColumn(
    String title,
    Map<String, dynamic> data,
    String timestamp,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: color.withOpacity(0.3)),
        borderRadius: BorderRadius.circular(8),
        color: color.withOpacity(0.05),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: color,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Modified: ${_formatTimestamp(timestamp)}',
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          ...data.entries.map((entry) {
            if (entry.key.startsWith('_') || entry.key == 'uuid') {
              return const SizedBox.shrink();
            }
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    child: Text(
                      '${entry.key}:',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      '${entry.value}',
                      style: const TextStyle(fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildResolutionButtons() {
    if (_isResolving) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Choose Resolution',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _resolveConflict(ConflictResolution.server),
                  icon: const Icon(Icons.cloud),
                  label: const Text('Keep Server'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _resolveConflict(ConflictResolution.client),
                  icon: const Icon(Icons.phone_android),
                  label: const Text('Keep Client'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _showCustomResolutionDialog,
            icon: const Icon(Icons.merge_type),
            label: const Text('Custom Merge'),
          ),
        ],
      ),
    );
  }

  Future<void> _resolveConflict(ConflictResolution resolution) async {
    setState(() => _isResolving = true);

    try {
      await widget.onResolve(resolution, null);
    } finally {
      if (mounted) {
        setState(() => _isResolving = false);
      }
    }
  }

  void _showCustomResolutionDialog() {
    showDialog(
      context: context,
      builder: (context) => CustomResolutionDialog(
        conflict: widget.conflict,
        onResolve: (customData) async {
          Navigator.of(context).pop();
          setState(() => _isResolving = true);

          try {
            await widget.onResolve(ConflictResolution.custom, customData);
          } finally {
            if (mounted) {
              setState(() => _isResolving = false);
            }
          }
        },
      ),
    );
  }

  String _formatTimestamp(String timestamp) {
    try {
      final dt = DateTime.parse(timestamp);
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return timestamp;
    }
  }
}

/// Custom Resolution Dialog
class CustomResolutionDialog extends StatefulWidget {
  final SyncConflict conflict;
  final Future<void> Function(Map<String, dynamic>) onResolve;

  const CustomResolutionDialog({
    Key? key,
    required this.conflict,
    required this.onResolve,
  }) : super(key: key);

  @override
  State<CustomResolutionDialog> createState() => _CustomResolutionDialogState();
}

class _CustomResolutionDialogState extends State<CustomResolutionDialog> {
  late Map<String, dynamic> _mergedData;
  final Map<String, TextEditingController> _controllers = {};

  @override
  void initState() {
    super.initState();
    _mergedData = Map<String, dynamic>.from(widget.conflict.serverData);

    // Initialize controllers for editable fields
    _mergedData.forEach((key, value) {
      if (!key.startsWith('_') && key != 'uuid') {
        _controllers[key] = TextEditingController(text: value.toString());
      }
    });
  }

  @override
  void dispose() {
    _controllers.values.forEach((controller) => controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Custom Merge'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: _buildFieldEditors(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _saveMergedData,
          child: const Text('Apply'),
        ),
      ],
    );
  }

  List<Widget> _buildFieldEditors() {
    return _controllers.entries.map((entry) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              entry.key,
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: entry.value,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.cloud, color: Colors.blue, size: 20),
                  tooltip: 'Use server value',
                  onPressed: () {
                    final serverValue = widget.conflict.serverData[entry.key];
                    entry.value.text = serverValue?.toString() ?? '';
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.phone_android, color: Colors.green, size: 20),
                  tooltip: 'Use client value',
                  onPressed: () {
                    final clientValue = widget.conflict.clientData[entry.key];
                    entry.value.text = clientValue?.toString() ?? '';
                  },
                ),
              ],
            ),
          ],
        ),
      );
    }).toList();
  }

  void _saveMergedData() {
    final customData = <String, dynamic>{};

    _controllers.forEach((key, controller) {
      // Try to preserve data types
      final originalValue = _mergedData[key];
      if (originalValue is int) {
        customData[key] = int.tryParse(controller.text) ?? controller.text;
      } else if (originalValue is double) {
        customData[key] = double.tryParse(controller.text) ?? controller.text;
      } else if (originalValue is bool) {
        customData[key] = controller.text.toLowerCase() == 'true';
      } else {
        customData[key] = controller.text;
      }
    });

    widget.onResolve(customData);
  }
}

/// Conflict Badge Widget - Shows number of unresolved conflicts
class ConflictBadge extends ConsumerWidget {
  final Widget child;

  const ConflictBadge({Key? key, required this.child}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conflicts = ref.watch(conflictsProvider);

    if (conflicts.isEmpty) {
      return child;
    }

    return Badge(
      label: Text('${conflicts.length}'),
      backgroundColor: Colors.red,
      child: child,
    );
  }
}

/// Sync Status Indicator Widget
class SyncStatusIndicator extends ConsumerWidget {
  const SyncStatusIndicator({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncStatus = ref.watch(syncStatusProvider);
    final serverAvailable = ref.watch(serverAvailableProvider);
    final lastSync = ref.watch(lastSyncTimeProvider);
    final hasConflicts = ref.watch(hasConflictsProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _buildStatusIcon(syncStatus, serverAvailable),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _getStatusText(syncStatus, serverAvailable),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      if (lastSync != null)
                        Text(
                          'Last sync: ${_formatLastSync(lastSync)}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                    ],
                  ),
                ),
                if (hasConflicts)
                  const Chip(
                    label: Text('Conflicts'),
                    backgroundColor: Colors.orange,
                    labelStyle: TextStyle(color: Colors.white, fontSize: 12),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusIcon(SyncStatus status, bool serverAvailable) {
    if (!serverAvailable) {
      return const Icon(Icons.cloud_off, color: Colors.grey, size: 32);
    }

    switch (status) {
      case SyncStatus.idle:
        return const Icon(Icons.cloud_done, color: Colors.green, size: 32);
      case SyncStatus.syncing:
        return const SizedBox(
          width: 32,
          height: 32,
          child: CircularProgressIndicator(),
        );
      case SyncStatus.completed:
        return const Icon(Icons.check_circle, color: Colors.green, size: 32);
      case SyncStatus.error:
        return const Icon(Icons.error, color: Colors.red, size: 32);
    }
  }

  String _getStatusText(SyncStatus status, bool serverAvailable) {
    if (!serverAvailable) {
      return 'Server Offline';
    }

    return status.displayName;
  }

  String _formatLastSync(DateTime lastSync) {
    final now = DateTime.now();
    final diff = now.difference(lastSync);

    if (diff.inMinutes < 1) {
      return 'just now';
    } else if (diff.inHours < 1) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inDays < 1) {
      return '${diff.inHours}h ago';
    } else {
      return '${diff.inDays}d ago';
    }
  }
}
