# Supplier Management Fix - Instructions

## ✅ Completed
All supplier management files have been created and committed:
- `lib/db/daos/supplier_dao.dart` - Complete DAO with sync and balance methods
- `lib/providers/supplier_provider.dart` - All providers including `suppliersProvider`, `supplierByIdProvider`
- `lib/screens/suppliers/supplier_form_screen.dart` - Form with validation
- `lib/screens/suppliers/supplier_list_screen.dart` - Reactive list screen

## 🔧 Required Steps to Fix Compilation Errors

### Step 1: Generate .g.dart files (CRITICAL)
```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

This will generate:
- `supplier_dao.g.dart` - Fixes all `SuppliersCompanion` errors
- Other `.g.dart` files needed by Drift

### Step 2: Fix router.dart

In `lib/config/router.dart` (or wherever your router is), make these changes:

**Fix imports** - Use only one import:
```dart
import 'package:hotel_inventory_management/screens/suppliers/supplier_list_screen.dart';
import 'package:hotel_inventory_management/screens/suppliers/supplier_form_screen.dart';
// OR use the barrel export:
// import 'package:hotel_inventory_management/providers/suppliers_exports.dart';
```

**Fix supplier routes** - Update parameter name from `supplierId` to `supplierUuid`:
```dart
GoRoute(
  path: '/suppliers',
  builder: (context, state) => const SupplierListScreen(),
),
GoRoute(
  path: '/suppliers/add',
  builder: (context, state) => const SupplierFormScreen(),
),
GoRoute(
  path: '/suppliers/edit/:id',
  builder: (context, state) {
    final id = state.pathParameters['id']!;
    return SupplierFormScreen(supplierUuid: id);  // Changed from supplierId
  },
),
```

### Step 3: Add imports to screens using suppliers

**In these files:**
- `lib/screens/purchase/purchase_list_screen.dart`
- `lib/screens/purchase/purchase_form_screen.dart`
- `lib/screens/wastage/wastage_form_screen.dart`
- `lib/screens/reports/views/purchase_report.dart`
- `lib/screens/reports/views/supplier_ledger_report.dart`

**Add this import at the top:**
```dart
import 'package:hotel_inventory_management/providers/supplier_provider.dart';
```

### Step 4: Fix purchase_dao.dart (if applicable)

If you have a `lib/db/daos/purchase_dao.dart` file with supplier queries, fix the async/await:

**Find this pattern:**
```dart
final supplierIds = suppliers.map((s) => s.uuid).toList();
if (supplierIds.isEmpty) {
```

**Replace with:**
```dart
final supplierList = await suppliers; // Add await
final supplierIds = supplierList.map((s) => s.uuid).toList();
if (supplierIds.isEmpty) {
```

## 📋 Available Providers

After fixing, these providers will be available:

```dart
// Import this:
import 'package:hotel_inventory_management/providers/supplier_provider.dart';

// Available providers:
suppliersProvider              // StreamProvider<List<Supplier>> - All suppliers
allSuppliersProvider          // Same as above (alias)
filteredSuppliersProvider     // StreamProvider<List<Supplier>> - With search filter
supplierByIdProvider(uuid)    // StreamProvider.family<Supplier?, String> - Single supplier
supplierSearchQueryProvider   // StateProvider<String> - Search query state
supplierNotifierProvider      // For CRUD operations
supplierDaoProvider           // Direct DAO access
```

## 🎯 After Running build_runner

All these methods will be available on `SupplierDao`:
- ✅ `getUnsyncedSuppliers()` - For sync service
- ✅ `upsertSupplierFromServer()` - For sync service
- ✅ `markSuppliersAsSynced()` - For sync service
- ✅ `addToBalance()` - For purchase/payment transactions
- ✅ `subtractFromBalance()` - For returns/adjustments
- ✅ `watchAllSuppliers()` - Reactive stream
- ✅ All standard CRUD methods

## 🚀 Test After Fixes

1. Run build_runner
2. Fix router.dart
3. Add imports to screens
4. Hot restart the app
5. Navigate to Suppliers screen
6. Add a new supplier
7. **The supplier should appear immediately in the list!**

## 📊 Expected Logs

You should see this flow in the console:
```
💡 Attempting to save supplier
💡 Creating supplier with UUID: xxx-xxx-xxx
💡 Supplier object created, calling insertSupplier
➕ Inserting supplier into database
✅ Supplier inserted successfully
✅ Verification: Supplier found in database
🔙 Navigating back to supplier list
✅ Navigation completed
🏠 SupplierListScreen initialized
📺 watchAllSuppliers stream started
📺 watchAllSuppliers emitted 1 suppliers
🎨 SupplierListScreen building
📋 Rendering 1 suppliers in UI
```

## ❓ If Still Having Issues

1. **Clean and rebuild:**
   ```bash
   flutter clean
   flutter pub get
   flutter pub run build_runner build --delete-conflicting-outputs
   ```

2. **Check imports** - Make sure all files import `supplier_provider.dart`

3. **Restart IDE** - Sometimes the IDE needs to reindex after generating files

4. **Check for duplicate classes** - Ensure only one `SupplierListScreen` exists
