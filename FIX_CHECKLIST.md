# Complete Fix Checklist

Follow these steps in order to fix all compilation errors:

## ✅ Step 1: Run Build Runner (MOST IMPORTANT)

```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

**This will:**
- Generate `supplier_dao.g.dart` (fixes SuppliersCompanion errors)
- Generate all other `.g.dart` files needed by Drift
- Fix errors about missing methods (getUnsyncedSuppliers, etc.)

**Expected output:**
```
[INFO] Generating build script...
[INFO] Generating build script completed, took 2.1s
[INFO] Creating build script snapshot...
[INFO] Creating build script snapshot completed, took 5.3s
[INFO] Building new asset graph...
[INFO] Building new asset graph completed, took 1.2s
[INFO] Checking for unexpected pre-existing outputs...
...
[INFO] Succeeded after 15.2s with 42 outputs
```

## ✅ Step 2: Fix Router.dart

**File:** `lib/config/router.dart` (or wherever your routes are defined)

**Option A - Use the fix script:**
See [ROUTER_FIX.md](ROUTER_FIX.md) for detailed instructions.

**Option B - Quick manual fix:**
1. Find the line with `supplierId:` and change to `supplierUuid:`
2. Make sure imports don't have duplicates:
   ```dart
   import 'package:hotel_inventory_management/screens/suppliers/supplier_list_screen.dart';
   import 'package:hotel_inventory_management/screens/suppliers/supplier_form_screen.dart';
   ```

## ✅ Step 3: Add Imports to Other Screens

**Run this script** (already created):
```bash
chmod +x fix_supplier_imports.sh
./fix_supplier_imports.sh
```

**Or manually add this import to these files:**
```dart
import 'package:hotel_inventory_management/providers/supplier_provider.dart';
```

**Files that need it:**
- [ ] `lib/screens/purchase/purchase_list_screen.dart`
- [ ] `lib/screens/purchase/purchase_form_screen.dart`
- [ ] `lib/screens/wastage/wastage_form_screen.dart`
- [ ] `lib/screens/reports/views/purchase_report.dart`
- [ ] `lib/screens/reports/views/supplier_ledger_report.dart`

## ✅ Step 4: Fix purchase_dao.dart (if error persists)

**File:** `lib/db/daos/purchase_dao.dart`

**Find this code** (around line 54):
```dart
final supplierIds = suppliers.map((s) => s.uuid).toList();
if (supplierIds.isEmpty) {
```

**Replace with** (add `await`):
```dart
final supplierList = await suppliers;  // ← Add this await
final supplierIds = supplierList.map((s) => s.uuid).toList();
if (supplierIds.isEmpty) {
```

## ✅ Step 5: Clean and Rebuild

```bash
flutter clean
flutter pub get
flutter pub run build_runner build --delete-conflicting-outputs
```

## ✅ Step 6: Restart App

```bash
# If running in terminal, press 'R' for hot restart
# Or stop and run again:
flutter run
```

---

## 🎯 After All Fixes

You should see **0 errors** and these logs when creating a supplier:

```
💡 Attempting to save supplier
💡 Creating supplier with UUID: xxx-xxx-xxx
💡 Supplier object created, calling insertSupplier
➕ Inserting supplier into database
✅ Supplier inserted successfully
✅ Verification: Supplier found in database
🔙 Navigating back to supplier list
✅ Navigation completed
📺 watchAllSuppliers emitted 1 suppliers
📋 Rendering 1 suppliers in UI
```

---

## ❓ Troubleshooting

### Still getting "method not found" errors?
- Make sure you ran `build_runner` successfully
- Check that `.g.dart` files exist in `lib/db/daos/`
- Try: `flutter clean && flutter pub get && flutter pub run build_runner build --delete-conflicting-outputs`

### Still getting import errors?
- Make sure `supplier_provider.dart` is in `lib/providers/`
- Check that imports use the correct package name: `package:hotel_inventory_management/`
- Restart your IDE/editor

### Suppliers still not appearing in list?
- Check that `build_runner` generated `supplier_dao.g.dart`
- Verify the app restarted after code generation
- Check the console logs for any runtime errors
- Make sure you cleared the search query (should happen automatically)

---

## 📞 Quick Reference

**All available providers after fix:**
```dart
import 'package:hotel_inventory_management/providers/supplier_provider.dart';

// Use these in your screens:
suppliersProvider               // Stream of all suppliers
supplierByIdProvider(uuid)      // Get supplier by UUID
filteredSuppliersProvider       // Suppliers with search filter
supplierNotifierProvider        // For create/update/delete
```

**SupplierDao methods now available:**
- `watchAllSuppliers()` - Reactive stream
- `getAllSuppliers()` - One-time fetch
- `getSupplierByUuid(uuid)` - Get one supplier
- `insertSupplier(supplier)` - Create
- `updateSupplier(supplier)` - Update
- `deleteSupplier(uuid)` - Soft delete
- `getUnsyncedSuppliers()` - For sync service
- `upsertSupplierFromServer()` - For sync service
- `markSuppliersAsSynced()` - For sync service
- `addToBalance()` - For purchase transactions
- `subtractFromBalance()` - For returns/wastage
