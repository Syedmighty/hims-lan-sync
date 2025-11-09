#!/bin/bash

# Supplier Import Fix Script
# This script adds the necessary import to all files that need it

echo "🔧 Fixing supplier provider imports..."

# Files that need the supplier_provider import
FILES=(
  "lib/screens/purchase/purchase_list_screen.dart"
  "lib/screens/purchase/purchase_form_screen.dart"
  "lib/screens/wastage/wastage_form_screen.dart"
  "lib/screens/reports/views/purchase_report.dart"
  "lib/screens/reports/views/supplier_ledger_report.dart"
)

IMPORT_LINE="import 'package:hotel_inventory_management/providers/supplier_provider.dart';"

for file in "${FILES[@]}"; do
  if [ -f "$file" ]; then
    # Check if import already exists
    if grep -q "supplier_provider.dart" "$file"; then
      echo "✅ $file already has the import"
    else
      # Add import after the last import statement
      # Find the line number of the last import
      last_import=$(grep -n "^import " "$file" | tail -1 | cut -d: -f1)

      if [ -n "$last_import" ]; then
        # Insert after the last import
        sed -i "${last_import}a\\${IMPORT_LINE}" "$file"
        echo "✅ Added import to $file"
      else
        echo "⚠️  Could not find imports in $file"
      fi
    fi
  else
    echo "⚠️  File not found: $file"
  fi
done

echo ""
echo "📝 Next steps:"
echo "1. Check lib/config/router.dart and change 'supplierId' to 'supplierUuid'"
echo "2. Run: flutter pub run build_runner build --delete-conflicting-outputs"
echo "3. Run: flutter clean && flutter pub get"
echo "4. Restart your app"
