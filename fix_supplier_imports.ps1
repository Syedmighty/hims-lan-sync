# PowerShell script to add supplier_provider imports

$importLine = "import 'package:hotel_inventory_management/providers/supplier_provider.dart';"

$files = @(
    "lib\screens\purchase\purchase_list_screen.dart",
    "lib\screens\purchase\purchase_form_screen.dart",
    "lib\screens\wastage\wastage_form_screen.dart",
    "lib\screens\reports\views\purchase_report.dart",
    "lib\screens\reports\views\supplier_ledger_report.dart"
)

Write-Host "🔧 Adding supplier_provider imports..." -ForegroundColor Cyan

foreach ($file in $files) {
    if (Test-Path $file) {
        $content = Get-Content $file -Raw

        if ($content -match "supplier_provider.dart") {
            Write-Host "✅ $file already has the import" -ForegroundColor Green
        }
        else {
            # Find the last import line
            $lines = Get-Content $file
            $lastImportIndex = -1

            for ($i = 0; $i -lt $lines.Count; $i++) {
                if ($lines[$i] -match "^import ") {
                    $lastImportIndex = $i
                }
            }

            if ($lastImportIndex -ge 0) {
                # Insert after the last import
                $lines = @($lines[0..$lastImportIndex]) + $importLine + @($lines[($lastImportIndex + 1)..($lines.Count - 1)])
                $lines | Set-Content $file
                Write-Host "✅ Added import to $file" -ForegroundColor Green
            }
            else {
                Write-Host "⚠️  Could not find imports in $file" -ForegroundColor Yellow
            }
        }
    }
    else {
        Write-Host "⚠️  File not found: $file" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "✨ Done! Now fix the router.dart file manually." -ForegroundColor Cyan
Write-Host "See ROUTER_FIX.md for instructions." -ForegroundColor Cyan
