import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hotel_inventory_management/db/app_database.dart';
import 'package:hotel_inventory_management/db/daos/supplier_dao.dart';
import 'package:hotel_inventory_management/providers/database_provider.dart';
import 'package:uuid/uuid.dart';

// DAO Provider
final supplierDaoProvider = Provider<SupplierDao>((ref) {
  final database = ref.watch(databaseProvider);
  return SupplierDao(database);
});

// Search Query Provider
final supplierSearchQueryProvider = StateProvider<String>((ref) => '');

// All Suppliers Provider (for dropdowns and other places)
final allSuppliersProvider = StreamProvider<List<Supplier>>((ref) {
  final supplierDao = ref.watch(supplierDaoProvider);
  return supplierDao.watchAllSuppliers();
});

// Legacy alias for compatibility
final suppliersProvider = allSuppliersProvider;

// Supplier by ID Provider (for looking up individual suppliers)
final supplierByIdProvider = StreamProvider.family<Supplier?, String>((ref, uuid) {
  final supplierDao = ref.watch(supplierDaoProvider);
  return (supplierDao.db.select(supplierDao.db.suppliers)
        ..where((tbl) => tbl.uuid.equals(uuid)))
      .watchSingleOrNull();
});

// Filtered Suppliers Stream Provider - This should automatically update when DB changes
final filteredSuppliersProvider = StreamProvider<List<Supplier>>((ref) {
  final searchQuery = ref.watch(supplierSearchQueryProvider);
  final supplierDao = ref.watch(supplierDaoProvider);

  // Get the reactive stream from DAO
  final allSuppliersStream = supplierDao.watchAllSuppliers();

  // If no search query, return all suppliers
  if (searchQuery.isEmpty) {
    return allSuppliersStream;
  }

  // Otherwise, filter the stream
  return allSuppliersStream.map((suppliers) {
    final query = searchQuery.toLowerCase();
    return suppliers.where((supplier) {
      return supplier.name.toLowerCase().contains(query) ||
             supplier.contact.toLowerCase().contains(query) ||
             (supplier.gstin?.toLowerCase().contains(query) ?? false);
    }).toList();
  });
});

// Supplier Notifier for CRUD operations
class SupplierNotifier extends StateNotifier<AsyncValue<void>> {
  final SupplierDao _supplierDao;

  SupplierNotifier(this._supplierDao) : super(const AsyncValue.data(null));

  Future<void> createSupplier(Supplier supplier) async {
    state = const AsyncValue.loading();
    try {
      await _supplierDao.insertSupplier(supplier);
      state = const AsyncValue.data(null);
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
      rethrow;
    }
  }

  Future<void> updateSupplier(Supplier supplier) async {
    state = const AsyncValue.loading();
    try {
      await _supplierDao.updateSupplier(supplier);
      state = const AsyncValue.data(null);
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
      rethrow;
    }
  }

  Future<void> deleteSupplier(String uuid) async {
    state = const AsyncValue.loading();
    try {
      await _supplierDao.deleteSupplier(uuid);
      state = const AsyncValue.data(null);
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
      rethrow;
    }
  }
}

// Supplier Notifier Provider
final supplierNotifierProvider =
    StateNotifierProvider<SupplierNotifier, AsyncValue<void>>((ref) {
  final supplierDao = ref.watch(supplierDaoProvider);
  return SupplierNotifier(supplierDao);
});
