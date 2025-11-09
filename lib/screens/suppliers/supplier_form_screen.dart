import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hotel_inventory_management/db/app_database.dart';
import 'package:hotel_inventory_management/providers/supplier_provider.dart';
import 'package:hotel_inventory_management/services/error_service.dart';
import 'package:uuid/uuid.dart';

class SupplierFormScreen extends ConsumerStatefulWidget {
  final String? supplierUuid;

  const SupplierFormScreen({super.key, this.supplierUuid});

  @override
  ConsumerState<SupplierFormScreen> createState() => _SupplierFormScreenState();
}

class _SupplierFormScreenState extends ConsumerState<SupplierFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _contactController = TextEditingController();
  final _gstinController = TextEditingController();
  final _addressController = TextEditingController();
  final _balanceController = TextEditingController();

  bool _isLoading = true;
  Supplier? _existingSupplier;

  @override
  void initState() {
    super.initState();
    _loadSupplier();
  }

  Future<void> _loadSupplier() async {
    if (widget.supplierUuid != null) {
      try {
        final supplierDao = ref.read(supplierDaoProvider);
        final supplier = await supplierDao.getSupplierByUuid(widget.supplierUuid!);

        if (supplier != null) {
          setState(() {
            _existingSupplier = supplier;
            _nameController.text = supplier.name;
            _contactController.text = supplier.contact;
            _gstinController.text = supplier.gstin ?? '';
            _addressController.text = supplier.address;
            _balanceController.text = supplier.balance.toString();
            _isLoading = false;
          });
        } else {
          setState(() => _isLoading = false);
        }
      } catch (e) {
        ErrorService().logError(Exception('Load supplier failed: $e'));
        setState(() => _isLoading = false);
      }
    } else {
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _contactController.dispose();
    _gstinController.dispose();
    _addressController.dispose();
    _balanceController.dispose();
    super.dispose();
  }

  Future<void> _saveSupplier() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    ErrorService().logInfo('💡 Attempting to save supplier', data: {
      'name': _nameController.text.trim(),
      'contact': _contactController.text.trim(),
      'isEdit': _existingSupplier != null,
    });

    try {
      final supplierNotifier = ref.read(supplierNotifierProvider.notifier);
      final now = DateTime.now();

      if (_existingSupplier != null) {
        // Update existing supplier
        final updatedSupplier = _existingSupplier!.copyWith(
          name: _nameController.text.trim(),
          contact: _contactController.text.trim(),
          gstin: _gstinController.text.trim().isEmpty
              ? null
              : _gstinController.text.trim(),
          address: _addressController.text.trim(),
          balance: double.tryParse(_balanceController.text) ?? 0.0,
          lastModified: now,
        );

        await supplierNotifier.updateSupplier(updatedSupplier);

        ErrorService().logInfo('✅ Supplier updated successfully', data: {
          'uuid': updatedSupplier.uuid,
        });
      } else {
        // Create new supplier
        final uuid = const Uuid().v4();

        ErrorService().logInfo('💡 Creating supplier with UUID: $uuid');

        final newSupplier = Supplier(
          uuid: uuid,
          name: _nameController.text.trim(),
          contact: _contactController.text.trim(),
          gstin: _gstinController.text.trim().isEmpty
              ? null
              : _gstinController.text.trim(),
          address: _addressController.text.trim(),
          balance: double.tryParse(_balanceController.text) ?? 0.0,
          lastModified: now,
          isSynced: false,
          sourceDevice: 'local', // TODO: Get actual device ID
          isActive: true,
        );

        ErrorService().logInfo('💡 Supplier object created, calling insertSupplier', data: {
          'uuid': uuid,
          'supplier': newSupplier.toString(),
        });

        await supplierNotifier.createSupplier(newSupplier);

        ErrorService().logInfo('💡 Supplier created successfully', data: {
          'uuid': uuid,
        });
      }

      if (!mounted) return;

      // Clear search query before navigating back
      ref.read(supplierSearchQueryProvider.notifier).state = '';

      ErrorService().logInfo('🔙 Navigating back to supplier list');

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_existingSupplier != null
              ? 'Supplier updated successfully'
              : 'Supplier created successfully'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );

      // Navigate back to supplier list
      context.pop();

      ErrorService().logInfo('✅ Navigation completed');
    } catch (e) {
      ErrorService().logError(Exception('Save supplier failed: $e'));

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Loading...'),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_existingSupplier != null ? 'Edit Supplier' : 'Add Supplier'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Name *',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter supplier name';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _contactController,
              decoration: const InputDecoration(
                labelText: 'Contact (Phone/Email) *',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.phone,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter contact information';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _gstinController,
              decoration: const InputDecoration(
                labelText: 'GSTIN (Optional)',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.characters,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _addressController,
              decoration: const InputDecoration(
                labelText: 'Address *',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter address';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _balanceController,
              decoration: const InputDecoration(
                labelText: 'Opening Balance',
                border: OutlineInputBorder(),
                prefixText: '₹ ',
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              validator: (value) {
                if (value != null && value.isNotEmpty) {
                  final balance = double.tryParse(value);
                  if (balance == null) {
                    return 'Please enter a valid number';
                  }
                }
                return null;
              },
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _saveSupplier,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.all(16),
              ),
              child: Text(
                _existingSupplier != null ? 'Update Supplier' : 'Create Supplier',
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
