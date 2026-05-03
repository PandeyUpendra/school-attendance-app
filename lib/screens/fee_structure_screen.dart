import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme.dart';
import '../models/fee.dart';
import '../services/fee_service.dart';
import '../services/timetable_service.dart';

/// Coordinator screen: configure annual fee structure per class.
/// Accessible only to coordinator role.
class FeeStructureScreen extends StatefulWidget {
  const FeeStructureScreen({super.key});

  @override
  State<FeeStructureScreen> createState() => _FeeStructureScreenState();
}

class _FeeStructureScreenState extends State<FeeStructureScreen> {
  final _feeService = FeeService();

  bool _loading = true;
  List<String> _classes = [];
  String? _selectedClass;
  FeeStructure? _structure;

  @override
  void initState() {
    super.initState();
    _loadClasses();
  }

  Future<void> _loadClasses() async {
    final settings = await TimetableService().getSettings();
    final classes = List<String>.from(settings['classes'] as List? ?? []);
    if (!mounted) return;
    setState(() {
      _classes = classes;
      _loading = false;
    });
    if (classes.isNotEmpty) _selectClass(classes.first);
  }

  Future<void> _selectClass(String cls) async {
    setState(() { _selectedClass = cls; _loading = true; });
    final structure = await _feeService.getFeeStructure(cls);
    if (!mounted) return;
    setState(() { _structure = structure; _loading = false; });
  }

  Future<void> _editStructure() async {
    if (_selectedClass == null) return;
    final current = _structure ?? FeeStructure.empty(_selectedClass!);

    // Pre-fill controllers from current structure
    final annualCtrl = TextEditingController(
        text: current.totalAnnualFee > 0
            ? current.totalAnnualFee.toStringAsFixed(0)
            : '');

    // Components list (editable)
    final components = List<Map<String, TextEditingController>>.from(
      current.components.map((c) => {
        'name':   TextEditingController(text: c.name),
        'amount': TextEditingController(
            text: c.amount > 0 ? c.amount.toStringAsFixed(0) : ''),
      }),
    );

    final formKey = GlobalKey<FormState>();
    bool saving = false;

    void addComponent(StateSetter setS) {
      setS(() => components.add({
            'name':   TextEditingController(),
            'amount': TextEditingController(),
          }));
    }

    void removeComponent(StateSetter setS, int idx) {
      setS(() => components.removeAt(idx));
    }

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.only(
            left: 18, right: 18, top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 18,
          ),
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text('Fee Structure — $_selectedClass',
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.bold)),
                const SizedBox(height: 14),

                // Total annual fee
                TextFormField(
                  controller: annualCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  decoration: InputDecoration(
                    labelText: 'Total Annual Fee (₹)',
                    prefixIcon: const Icon(Icons.currency_rupee),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Required';
                    final n = double.tryParse(v.trim());
                    if (n == null || n < 1 || n > 9999999) return '1–9,999,999';
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Fee components
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Fee Components',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                    TextButton.icon(
                      onPressed: () => addComponent(setS),
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Add'),
                      style: TextButton.styleFrom(
                          foregroundColor: Colors.green.shade700),
                    ),
                  ],
                ),
                if (components.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'No components added. Tap Add to break down the fee.',
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey.shade500),
                    ),
                  ),
                for (int i = 0; i < components.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(children: [
                      Expanded(
                        flex: 5,
                        child: TextFormField(
                          controller: components[i]['name'],
                          maxLength: 40,
                          maxLengthEnforcement:
                              MaxLengthEnforcement.enforced,
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                                RegExp(r'[a-zA-Z ]')),
                          ],
                          decoration: InputDecoration(
                            labelText: 'Name (e.g. Tuition)',
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8)),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 10),
                            counterText: '',
                          ),
                          validator: (v) =>
                              (v == null || v.trim().isEmpty)
                                  ? 'Required'
                                  : null,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 4,
                        child: TextFormField(
                          controller: components[i]['amount'],
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                                RegExp(r'[0-9.]')),
                          ],
                          decoration: InputDecoration(
                            labelText: '₹ Amount',
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8)),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 10),
                          ),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) return 'Required';
                            final n = double.tryParse(v.trim());
                            if (n == null || n <= 0) return '> 0';
                            return null;
                          },
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline,
                            color: Colors.red, size: 20),
                        onPressed: () => removeComponent(setS, i),
                        padding: EdgeInsets.zero,
                      ),
                    ]),
                  ),

                const SizedBox(height: 12),
                Row(children: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancel'),
                  ),
                  const Spacer(),
                  ElevatedButton.icon(
                    onPressed: saving
                        ? null
                        : () async {
                            if (!formKey.currentState!.validate()) return;
                            final annual =
                                double.tryParse(annualCtrl.text.trim()) ?? 0;
                            final comps = components
                                .where((c) =>
                                    c['name']!.text.trim().isNotEmpty)
                                .map((c) => FeeComponent(
                                      name: c['name']!.text.trim(),
                                      amount: double.tryParse(
                                              c['amount']!.text.trim()) ??
                                          0,
                                    ))
                                .toList();
                            setS(() => saving = true);
                            await FeeService().saveFeeStructure(
                              FeeStructure(
                                className: _selectedClass!,
                                totalAnnualFee: annual,
                                components: comps,
                              ),
                            );
                            if (ctx.mounted) Navigator.pop(ctx, true);
                          },
                    icon: const Icon(Icons.save_outlined, size: 18),
                    label: const Text('Save'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ]),
              ],
            ),
            ),
          ),
        ),
      ),
    );

    if (saved == true && _selectedClass != null) {
      _selectClass(_selectedClass!);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Fee Structure',
                style:
                    TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            Text('Set annual fees per class',
                style: TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
        actions: [
          if (_selectedClass != null)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit structure',
              onPressed: _editStructure,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _classes.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.school_outlined,
                          size: 56, color: Colors.grey.shade400),
                      const SizedBox(height: 12),
                      Text('No classes configured yet.',
                          style: TextStyle(color: Colors.grey.shade500)),
                    ],
                  ),
                )
              : Column(
                  children: [
                    // Class selector
                    Container(
                      color: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: _classes.map((cls) {
                            final selected = cls == _selectedClass;
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text(cls),
                                selected: selected,
                                selectedColor: Colors.green.shade700,
                                labelStyle: TextStyle(
                                  color: selected ? Colors.white : null,
                                  fontWeight: selected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                                onSelected: (_) => _selectClass(cls),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: _structure == null
                          ? const Center(child: CircularProgressIndicator())
                          : _buildStructureView(_structure!),
                    ),
                  ],
                ),
      floatingActionButton: _selectedClass != null && _classes.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: _editStructure,
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.edit),
              label: const Text('Edit'),
            )
          : null,
    );
  }

  Widget _buildStructureView(FeeStructure s) {
    final isEmpty = s.totalAnnualFee == 0 && s.components.isEmpty;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Annual fee hero
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppTheme.primaryDark, AppTheme.primaryMid],
              begin: Alignment.topLeft, end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('ANNUAL FEE',
                  style: TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2)),
              const SizedBox(height: 8),
              Text(
                isEmpty ? 'Not configured' : '₹${_fmt(s.totalAnnualFee)}',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold),
              ),
              if (!isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('per academic year  •  ${s.className}',
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 12)),
                ),
            ],
          ),
        ),

        if (isEmpty) ...[
          const SizedBox(height: 40),
          Icon(Icons.attach_money, size: 56, color: Colors.grey.shade300),
          const SizedBox(height: 14),
          Center(
            child: Text(
              'No fee structure configured yet.\nTap Edit to set up.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade500),
            ),
          ),
        ] else ...[
          if (s.components.isNotEmpty) ...[
            const SizedBox(height: 20),
            const Text('FEE BREAKDOWN',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey,
                    letterSpacing: 0.8)),
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                children: [
                  for (int i = 0; i < s.components.length; i++) ...[
                    if (i > 0) const Divider(height: 1, indent: 16),
                    ListTile(
                      dense: true,
                      leading: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(Icons.receipt_long_outlined,
                            size: 18, color: Colors.green.shade700),
                      ),
                      title: Text(s.components[i].name,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w500)),
                      trailing: Text(
                        '₹${_fmt(s.components[i].amount)}',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.green.shade700),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            // Total check
            _TotalCheck(
              components: s.components,
              totalAnnual: s.totalAnnualFee,
            ),
          ],
        ],
      ],
    );
  }

  String _fmt(double v) {
    if (v == v.truncateToDouble()) return v.toStringAsFixed(0);
    return v.toStringAsFixed(2);
  }
}

class _TotalCheck extends StatelessWidget {
  final List<FeeComponent> components;
  final double totalAnnual;

  const _TotalCheck(
      {required this.components, required this.totalAnnual});

  @override
  Widget build(BuildContext context) {
    final compTotal = components.fold(0.0, (s, c) => s + c.amount);
    final diff = (compTotal - totalAnnual).abs();
    final match = diff < 1;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: match ? Colors.green.shade50 : Colors.orange.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: match
              ? Colors.green.shade200
              : Colors.orange.shade300,
        ),
      ),
      child: Row(children: [
        Icon(
          match ? Icons.check_circle_outline : Icons.warning_amber_rounded,
          color: match ? Colors.green.shade700 : Colors.orange.shade700,
          size: 20,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            match
                ? 'Components total matches annual fee ✓'
                : 'Components total ₹${compTotal.toStringAsFixed(0)} differs '
                    'from annual fee ₹${totalAnnual.toStringAsFixed(0)}',
            style: TextStyle(
              fontSize: 12,
              color: match
                  ? Colors.green.shade800
                  : Colors.orange.shade800,
            ),
          ),
        ),
      ]),
    );
  }
}
