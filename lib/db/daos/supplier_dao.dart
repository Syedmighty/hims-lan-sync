import 'package:drift/drift.dart';
import 'package:hotel_inventory_management/db/app_database.dart';
import 'package:hotel_inventory_management/services/error_service.dart';

part 'supplier_dao.g.dart';

@DriftAccessor(tables: [Suppliers])
class SupplierDao extends DatabaseAccessor<AppDatabase> with _$SupplierDaoMixin {
  SupplierDao(AppDatabase db) : super(db);

  // Get unsynced suppliers for sync service
  Future<List<Supplier>> getUnsyncedSuppliers() async {
    return await (select(suppliers)
          ..where((tbl) => tbl.isSynced.equals(false) & tbl.isActive.equals(true)))
        .get();
  }

  // Upsert supplier from server during sync
  Future<void> upsertSupplierFromServer(Supplier supplier) async {
    await into(suppliers).insertOnConflictUpdate(supplier);
  }

  // Mark suppliers as synced
  Future<void> markSuppliersAsSynced(List<String> uuids) async {
    await (update(suppliers)..where((tbl) => tbl.uuid.isIn(uuids)))
        .write(const SuppliersCompanion(isSynced: Value(true)));
  }

  // Add to supplier balance
  Future<void> addToBalance(String supplierUuid, double amount) async {
    final supplier = await getSupplierByUuid(supplierUuid);
    if (supplier != null) {
      final newBalance = supplier.balance + amount;
      await (update(suppliers)..where((tbl) => tbl.uuid.equals(supplierUuid)))
          .write(SuppliersCompanion(
        balance: Value(newBalance),
        lastModified: Value(DateTime.now()),
      ));
    }
  }

  // Subtract from supplier balance
  Future<void> subtractFromBalance(String supplierUuid, double amount) async {
    final supplier = await getSupplierByUuid(supplierUuid);
    if (supplier != null) {
      final newBalance = supplier.balance - amount;
      await (update(suppliers)..where((tbl) => tbl.uuid.equals(supplierUuid)))
          .write(SuppliersCompanion(
        balance: Value(newBalance),
        lastModified: Value(DateTime.now()),
      ));
    }
  }

  // Watch all active suppliers - This returns a reactive stream
  Stream<List<Supplier>> watchAllSuppliers() {
    ErrorService().logInfo('📺 watchAllSuppliers stream started');

    return (select(suppliers)
          ..where((tbl) => tbl.isActive.equals(true))
          ..orderBy([(t) => OrderingTerm(expression: t.name)]))
        .watch()
        .map((suppliers) {
      ErrorService().logInfo('📺 watchAllSuppliers emitted ${suppliers.length} suppliers', data: {
        'count': suppliers.length,
        'uuids': suppliers.map((s) => s.uuid).toList(),
        'names': suppliers.map((s) => s.name).toList(),
      });
      return suppliers;
    });
  }

  // Get all suppliers (non-reactive)
  Future<List<Supplier>> getAllSuppliers() async {
    final result = await (select(suppliers)
          ..where((tbl) => tbl.isActive.equals(true))
          ..orderBy([(t) => OrderingTerm(expression: t.name)]))
        .get();

    ErrorService().logInfo('📋 getAllSuppliers returned ${result.length} suppliers');
    return result;
  }

  // Get supplier by UUID
  Future<Supplier?> getSupplierByUuid(String uuid) async {
    ErrorService().logInfo('🔍 Getting supplier by UUID', data: {'uuid': uuid});

    return await (select(suppliers)..where((tbl) => tbl.uuid.equals(uuid)))
        .getSingleOrNull();
  }

  // Insert new supplier
  Future<int> insertSupplier(Supplier supplier) async {
    ErrorService().logInfo('➕ Inserting supplier into database', data: {
      'uuid': supplier.uuid,
      'name': supplier.name,
      'contact': supplier.contact,
      'isActive': supplier.isActive,
    });

    final result = await into(suppliers).insert(supplier);

    ErrorService().logInfo('✅ Supplier inserted successfully', data: {
      'uuid': supplier.uuid,
      'rowId': result,
    });

    // Verify it was inserted
    final verification = await getSupplierByUuid(supplier.uuid);
    if (verification != null) {
      ErrorService().logInfo('✅ Verification: Supplier found in database', data: {
        'uuid': verification.uuid,
        'name': verification.name,
      });
    } else {
      ErrorService().logError(Exception('Supplier not found after insertion - UUID: ${supplier.uuid}'));
    }

    return result;
  }

  // Update supplier
  Future<bool> updateSupplier(Supplier supplier) async {
    ErrorService().logInfo('📝 Updating supplier', data: {
      'uuid': supplier.uuid,
      'name': supplier.name,
    });

    return await update(suppliers).replace(supplier);
  }

  // Delete supplier (soft delete)
  Future<int> deleteSupplier(String uuid) async {
    ErrorService().logInfo('🗑️ Soft deleting supplier', data: {'uuid': uuid});

    return await (update(suppliers)..where((tbl) => tbl.uuid.equals(uuid)))
        .write(SuppliersCompanion(isActive: const Value(false)));
  }

  // Hard delete supplier
  Future<int> hardDeleteSupplier(String uuid) async {
    ErrorService().logInfo('💀 Hard deleting supplier', data: {'uuid': uuid});

    return await (delete(suppliers)..where((tbl) => tbl.uuid.equals(uuid))).go();
  }

  // Search suppliers
  Stream<List<Supplier>> searchSuppliers(String query) {
    final searchTerm = '%${query.toLowerCase()}%';

    return (select(suppliers)
          ..where((tbl) =>
              tbl.isActive.equals(true) &
              (tbl.name.lower().like(searchTerm) |
                  tbl.contact.lower().like(searchTerm) |
                  tbl.gstin.lower().like(searchTerm)))
          ..orderBy([(t) => OrderingTerm(expression: t.name)]))
        .watch();
  }

  // Get supplier balance
  Future<double> getSupplierBalance(String supplierUuid) async {
    final supplier = await getSupplierByUuid(supplierUuid);
    return supplier?.balance ?? 0.0;
  }

  // Update supplier balance
  Future<void> updateSupplierBalance(String supplierUuid, double newBalance) async {
    await (update(suppliers)..where((tbl) => tbl.uuid.equals(supplierUuid)))
        .write(SuppliersCompanion(
      balance: Value(newBalance),
      lastModified: Value(DateTime.now()),
    ));
  }

  // Get suppliers with outstanding balance
  Stream<List<Supplier>> watchSuppliersWithBalance() {
    return (select(suppliers)
          ..where((tbl) => tbl.isActive.equals(true) & tbl.balance.isBiggerThanValue(0))
          ..orderBy([(t) => OrderingTerm(expression: t.balance, mode: OrderingMode.desc)]))
        .watch();
  }
}
