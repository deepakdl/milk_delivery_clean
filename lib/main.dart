import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'http://192.168.0.159:8000',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyAgCiAgICAicm9sZSI6ICJhbm9uIiwKICAgICJpc3MiOiAic3VwYWJhc2UtZGVtbyIsCiAgICAiaWF0IjogMTY0MTc2OTIwMCwKICAgICJleHAiOiAxNzk5NTM1NjAwCn0.dc_X5iR_VP_qT0zsiyj_I_OZ2T9FtRU2BBNWN8Bu4GE',
  );

  runApp(const MilkDeliveryApp());
}

class MilkDeliveryApp extends StatelessWidget {
  const MilkDeliveryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Milk Delivery',
      theme: ThemeData(primarySwatch: Colors.indigo),
      home: const DeliveryBoySelector(),
    );
  }
}

class DeliveryBoySelector extends StatefulWidget {
  const DeliveryBoySelector({super.key});

  @override
  State<DeliveryBoySelector> createState() => _DeliveryBoySelectorState();
}

class _DeliveryBoySelectorState extends State<DeliveryBoySelector> {
  final SupabaseClient supabase = Supabase.instance.client;
  List<Map<String, dynamic>> deliveryBoys = [];
  String? selectedDeliveryBoyId;
  String? selectedDeliveryBoyName;

  @override
  void initState() {
    super.initState();
    fetchDeliveryBoys();
  }

  Future<void> fetchDeliveryBoys() async {
    final result = await supabase
        .from('delivery_boys')
        .select('user_id, users(full_name)')
        .eq('is_active', true);

    setState(() {
      deliveryBoys = List<Map<String, dynamic>>.from(result);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Select Delivery Boy')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            DropdownButtonFormField<String>(
              hint: const Text('Select your name'),
              value: selectedDeliveryBoyId,
              items: deliveryBoys.map((boy) {
                return DropdownMenuItem<String>(
                  value: boy['user_id'],
                  child: Text(boy['users']['full_name'] ?? 'Unknown'),
                );
              }).toList(),
              onChanged: (value) {
                final boy = deliveryBoys.firstWhere((b) => b['user_id'] == value);
                setState(() {
                  selectedDeliveryBoyId = value;
                  selectedDeliveryBoyName = boy['users']['full_name'];
                });
              },
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: selectedDeliveryBoyId == null
                  ? null
                  : () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => DeliveryForm(
                              deliveryBoyId: selectedDeliveryBoyId!,
                              deliveryBoyName: selectedDeliveryBoyName ?? ''),
                        ),
                      );
                    },
              child: const Text('Proceed to Deliveries'),
            ),
          ],
        ),
      ),
    );
  }
}

class DeliveryForm extends StatefulWidget {
  final String deliveryBoyId;
  final String deliveryBoyName;
  const DeliveryForm({super.key, required this.deliveryBoyId, required this.deliveryBoyName});

  @override
  State<DeliveryForm> createState() => _DeliveryFormState();
}

class _DeliveryFormState extends State<DeliveryForm> {
  final SupabaseClient supabase = Supabase.instance.client;
  List<Map<String, dynamic>> customers = [];
  String? selectedCustomerId;
  Map<String, dynamic>? selectedCustomer;
  final TextEditingController _quantityController = TextEditingController();
  DateTime selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    fetchCustomersWithProducts();
    syncPendingDeliveries();
  }

  Future<void> fetchCustomersWithProducts() async {
    final areaResult = await supabase
        .from('delivery_boys')
        .select('assigned_area_id')
        .eq('user_id', widget.deliveryBoyId)
        .maybeSingle();

    final assignedAreaId = areaResult?['assigned_area_id'];

    final result = await supabase
        .from('customers')
        .select('id, name, area_id, product_id, products(name, step_size, unit_type)')
        .eq('is_active', true);

    setState(() {
      customers = List<Map<String, dynamic>>.from(result)
          .where((c) => c['area_id'] == assignedAreaId)
          .toList();
    });
  }

  Future<void> submitDelivery() async {
    if (selectedCustomerId == null || _quantityController.text.isEmpty) return;

    final quantity = double.tryParse(_quantityController.text);
    if (quantity == null) return;

    await supabase.from('delivery_logs').insert({
      'customer_id': selectedCustomerId,
      'delivery_date': DateTime.now().toIso8601String(),
      'quantity': quantity,
      'delivered_by': widget.deliveryBoyName,
      'synced': false,
      'created_at': DateTime.now().toIso8601String(),
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Delivery logged locally. Press Sync Now to upload')),
    );

    _quantityController.clear();
  }

  Future<void> syncPendingDeliveries() async {
    final unsynced = await supabase
        .from('delivery_logs')
        .select()
        .eq('delivered_by', widget.deliveryBoyName)
        .eq('synced', false);

    for (final entry in unsynced) {
      await supabase
          .from('delivery_logs')
          .update({'synced': true, 'created_at': DateTime.now().toIso8601String()})
          .eq('id', entry['id']);
    }
  }

  @override
  Widget build(BuildContext context) {
    final stepSize = selectedCustomer?['products']?['step_size']?.toString() ?? '';
    final productName = selectedCustomer?['products']?['name'] ?? '';

    return Scaffold(
      appBar: AppBar(title: const Text('Milk Delivery Entry')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            DropdownButtonFormField<String>(
              hint: const Text('Select customer'),
              value: selectedCustomerId,
              items: customers.map((c) {
                return DropdownMenuItem<String>(
                  value: c['id'],
                  child: Text(c['name']),
                );
              }).toList(),
              onChanged: (value) {
                final customer = customers.firstWhere((c) => c['id'] == value);
                setState(() {
                  selectedCustomerId = value;
                  selectedCustomer = customer;
                });
              },
            ),
            const SizedBox(height: 16),
            if (productName.isNotEmpty) Text('Product: $productName'),
            const SizedBox(height: 16),
            TextField(
              controller: _quantityController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Quantity (${stepSize.isNotEmpty ? stepSize : 'N/A'} step)'
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: submitDelivery,
              child: const Text('Submit Delivery'),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: syncPendingDeliveries,
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              child: const Text('Sync Now'),
            ),
          ],
        ),
      ),
    );
  }
}
