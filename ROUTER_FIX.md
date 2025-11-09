# Router.dart Fix Instructions

## Problem
The router has import conflicts and wrong parameter names for supplier routes.

## Fix for lib/config/router.dart

### 1. Fix Imports (Top of file)

**Remove any duplicate imports and use only these:**
```dart
import 'package:hotel_inventory_management/screens/suppliers/supplier_list_screen.dart';
import 'package:hotel_inventory_management/screens/suppliers/supplier_form_screen.dart';
```

**OR use the barrel export:**
```dart
import 'package:hotel_inventory_management/providers/suppliers_exports.dart';
```

### 2. Fix Supplier Routes

**Find the supplier routes section and replace with this:**

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
    return SupplierFormScreen(supplierUuid: id);  // ⚠️ Changed from supplierId to supplierUuid
  },
),
GoRoute(
  path: '/suppliers/view/:id',
  builder: (context, state) {
    final id = state.pathParameters['id']!;
    // TODO: Create SupplierDetailScreen if needed
    return SupplierFormScreen(supplierUuid: id);
  },
),
```

### Key Changes:
1. ✅ Import only from individual files or use barrel export
2. ✅ Remove `const` from `SupplierFormScreen()` on line that was causing "Couldn't find constructor" error
3. ✅ Change parameter name from `supplierId` to `supplierUuid`

### Quick Find & Replace

In your router.dart file:
- Find: `supplierId:`
- Replace with: `supplierUuid:`

Save the file and the router errors should be fixed!
