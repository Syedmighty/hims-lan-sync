import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hotel_inventory_management/db/app_database.dart';
import 'package:hotel_inventory_management/providers/supplier_provider.dart';
import 'package:hotel_inventory_management/services/error_service.dart';

class SupplierListScreen extends ConsumerStatefulWidget {
  const SupplierListScreen({super.key});

  @override
  ConsumerState<SupplierListScreen> createState() => _SupplierListScreenState();
}

class _SupplierListScreenState extends ConsumerState<SupplierListScreen> {
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    ErrorService().logInfo('🏠 SupplierListScreen initialized');
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    ErrorService().logInfo('🔍 Search query changed', data: {'query': query});
    ref.read(supplierSearchQueryProvider.notifier).state = query;
  }

  void _clearSearch() {
    _searchController.clear();
    ref.read(supplierSearchQueryProvider.notifier).state = '';
    ErrorService().logInfo('🧹 Search cleared');
  }

  Future<void> _deleteSupplier(String uuid, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Supplier'),
        content: Text('Are you sure you want to delete "$name"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await ref.read(supplierNotifierProvider.notifier).deleteSupplier(uuid);

        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Supplier deleted successfully'),
            backgroundColor: Colors.green,
          ),
        );
      } catch (e) {
        ErrorService().logError(Exception('Delete supplier failed: $e'));

        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting supplier: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ErrorService().logInfo('🎨 SupplierListScreen building');

    // Watch the filtered suppliers stream
    final suppliersAsync = ref.watch(filteredSuppliersProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Suppliers'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () {
              ErrorService().logInfo('➕ Add supplier button pressed');
              context.push('/suppliers/add');
            },
            tooltip: 'Add Supplier',
          ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search suppliers...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: _clearSearch,
                      )
                    : null,
                border: const OutlineInputBorder(),
              ),
              onChanged: _onSearchChanged,
            ),
          ),

          // Supplier list
          Expanded(
            child: suppliersAsync.when(
              data: (suppliers) {
                ErrorService().logInfo('📋 Rendering ${suppliers.length} suppliers in UI');

                if (suppliers.isEmpty) {
                  final searchQuery = ref.watch(supplierSearchQueryProvider);

                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          searchQuery.isEmpty ? Icons.inventory_2_outlined : Icons.search_off,
                          size: 64,
                          color: Colors.grey,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          searchQuery.isEmpty
                              ? 'No suppliers yet'
                              : 'No suppliers found matching "$searchQuery"',
                          style: const TextStyle(
                            fontSize: 18,
                            color: Colors.grey,
                          ),
                        ),
                        if (searchQuery.isEmpty) ...[
                          const SizedBox(height: 8),
                          const Text(
                            'Tap + to add your first supplier',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ],
                      ],
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: () async {
                    ErrorService().logInfo('🔄 Manual refresh triggered');
                    // Invalidate the provider to force refresh
                    ref.invalidate(filteredSuppliersProvider);
                  },
                  child: ListView.separated(
                    itemCount: suppliers.length,
                    separatorBuilder: (context, index) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final supplier = suppliers[index];

                      return ListTile(
                        title: Text(
                          supplier.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w500,
                            fontSize: 16,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Text('Contact: ${supplier.contact}'),
                            if (supplier.gstin != null && supplier.gstin!.isNotEmpty)
                              Text('GSTIN: ${supplier.gstin}'),
                            if (supplier.balance != 0)
                              Text(
                                'Balance: ₹${supplier.balance.toStringAsFixed(2)}',
                                style: TextStyle(
                                  color: supplier.balance > 0 ? Colors.red : Colors.green,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit, color: Colors.blue),
                              onPressed: () {
                                ErrorService().logInfo('✏️ Edit supplier', data: {
                                  'uuid': supplier.uuid,
                                  'name': supplier.name,
                                });
                                context.push('/suppliers/edit/${supplier.uuid}');
                              },
                              tooltip: 'Edit',
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () => _deleteSupplier(supplier.uuid, supplier.name),
                              tooltip: 'Delete',
                            ),
                          ],
                        ),
                        onTap: () {
                          ErrorService().logInfo('👆 Supplier tapped', data: {
                            'uuid': supplier.uuid,
                            'name': supplier.name,
                          });
                          context.push('/suppliers/view/${supplier.uuid}');
                        },
                      );
                    },
                  ),
                );
              },
              loading: () {
                ErrorService().logInfo('⏳ Loading suppliers...');
                return const Center(child: CircularProgressIndicator());
              },
              error: (error, stack) {
                ErrorService().logError(Exception('Load suppliers failed: $error'));
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, size: 64, color: Colors.red),
                      const SizedBox(height: 16),
                      Text(
                        'Error loading suppliers',
                        style: const TextStyle(fontSize: 18),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        error.toString(),
                        style: const TextStyle(color: Colors.grey),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () {
                          ErrorService().logInfo('🔄 Retry button pressed');
                          ref.invalidate(filteredSuppliersProvider);
                        },
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          ErrorService().logInfo('➕ FAB pressed - navigating to add supplier');
          context.push('/suppliers/add');
        },
        tooltip: 'Add Supplier',
        child: const Icon(Icons.add),
      ),
    );
  }
}
