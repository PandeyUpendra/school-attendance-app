import 'package:flutter/material.dart';

import '../../services/dropdown_options_service.dart';
import '../../theme.dart';

/// A drop-in replacement for [DropdownButtonFormField]<String> whose options are
/// **user-manageable and persisted per school** (see [DropdownOptionsService]).
///
/// On top of a normal dropdown it adds:
///   • an "➕ Add custom…" entry — type a value not in the list and optionally
///     **Save to list** so it persists for everyone in the school;
///   • a settings gear (⚙) beside the field that opens a manager to add or
///     remove options.
///
/// Pass a stable [fieldKey] (e.g. `'fee_mode'`) and the built-in [seeds]. The
/// effective list is `(seeds − removed) ++ additions`, resolved at runtime.
class ManagedDropdown extends StatefulWidget {
  final String              fieldKey;
  final List<String>        seeds;
  final String?             value;
  final ValueChanged<String?> onChanged;
  final String?             label;
  final Widget?             prefixIcon;
  final String?             hint;
  final bool                isDense;
  final bool                allowCustom;
  final bool                allowManage;
  final String?             Function(String?)? validator;

  const ManagedDropdown({
    super.key,
    required this.fieldKey,
    required this.seeds,
    required this.value,
    required this.onChanged,
    this.label,
    this.prefixIcon,
    this.hint,
    this.isDense = true,
    this.allowCustom = true,
    this.allowManage = true,
    this.validator,
  });

  @override
  State<ManagedDropdown> createState() => _ManagedDropdownState();
}

const _kAddSentinel = '__managed_dropdown_add_custom__';

class _ManagedDropdownState extends State<ManagedDropdown> {
  final _svc = DropdownOptionsService();

  List<String> _options = [];
  // Custom values picked this session but not saved to the school list.
  final List<String> _sessionExtras = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _options = List.of(widget.seeds); // optimistic until Firestore resolves
    _load();
  }

  Future<void> _load() async {
    final opts = await _svc.getOptions(widget.fieldKey, widget.seeds);
    if (!mounted) return;
    setState(() {
      _options = opts;
      _loading = false;
    });
  }

  /// All values the dropdown can display, guaranteeing the current [value] is
  /// present so the framework's value-must-match-an-item invariant holds.
  List<String> get _effective {
    final list = [..._options, ..._sessionExtras];
    final v = widget.value;
    if (v != null && v.isNotEmpty && !list.contains(v)) list.add(v);
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final items = <DropdownMenuItem<String>>[
      for (final o in _effective)
        DropdownMenuItem(value: o, child: Text(o)),
      if (widget.allowCustom)
        const DropdownMenuItem(
          value: _kAddSentinel,
          child: Row(children: [
            Icon(Icons.add, size: 16, color: AppTheme.primary),
            SizedBox(width: 6),
            Text('Add custom…',
                style: TextStyle(color: AppTheme.primary)),
          ]),
        ),
    ];

    final dropdown = DropdownButtonFormField<String>(
      value: (widget.value != null && widget.value!.isNotEmpty)
          ? widget.value
          : null,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hint,
        prefixIcon: widget.prefixIcon,
        isDense: widget.isDense,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        suffixIcon: _loading
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                    width: 14, height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2)),
              )
            : null,
      ),
      items: items,
      validator: widget.validator,
      onChanged: (v) {
        if (v == _kAddSentinel) {
          _promptAddCustom();
        } else {
          widget.onChanged(v);
        }
      },
    );

    if (!widget.allowManage) return dropdown;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: dropdown),
        const SizedBox(width: 4),
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: IconButton(
            icon: const Icon(Icons.settings_outlined, size: 20),
            color: AppTheme.primary,
            tooltip: 'Manage options',
            visualDensity: VisualDensity.compact,
            onPressed: _openManager,
          ),
        ),
      ],
    );
  }

  // ── Add a custom value inline ──────────────────────────────────────────────

  Future<void> _promptAddCustom() async {
    final ctrl = TextEditingController();
    bool saveToList = true;

    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          title: Text(widget.label == null
              ? 'Add value'
              : 'Add ${widget.label}'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: ctrl,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: 'New value',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
                isDense: true,
              ),
              onSubmitted: (_) => Navigator.pop(ctx, ctrl.text.trim()),
            ),
            CheckboxListTile(
              value: saveToList,
              onChanged: (b) => setDlg(() => saveToList = b ?? true),
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              activeColor: AppTheme.primary,
              title: const Text('Save to list',
                  style: TextStyle(fontSize: 13)),
              subtitle: const Text('Keep this option for next time',
                  style: TextStyle(fontSize: 11)),
            ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary),
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );

    if (value == null || value.isEmpty || !mounted) return;

    if (saveToList) {
      await _svc.addOption(widget.fieldKey, value, widget.seeds);
      await _load();
    } else if (!_effective.contains(value)) {
      setState(() => _sessionExtras.add(value));
    }
    widget.onChanged(value);
  }

  // ── Manage (add / remove) ──────────────────────────────────────────────────

  Future<void> _openManager() async {
    final addCtrl = TextEditingController();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          Future<void> reloadSheet() async {
            await _load();
            setSheet(() {});
          }

          return Padding(
            padding: EdgeInsets.only(
              left: 18, right: 18, top: 16,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 18,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.tune, color: AppTheme.primary, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.label == null
                          ? 'Manage options'
                          : 'Manage ${widget.label}',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                Flexible(
                  child: _options.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Text('No options yet — add one below.'),
                        )
                      : ListView(
                          shrinkWrap: true,
                          children: [
                            for (final o in _options)
                              ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                title: Text(o),
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete_outline,
                                      color: AppTheme.danger, size: 20),
                                  tooltip: 'Remove',
                                  onPressed: () async {
                                    await _svc.removeOption(
                                        widget.fieldKey, o, widget.seeds);
                                    await reloadSheet();
                                  },
                                ),
                              ),
                          ],
                        ),
                ),
                const Divider(),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: addCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(
                        labelText: 'Add new option',
                        isDense: true,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      onSubmitted: (_) async {
                        await _svc.addOption(
                            widget.fieldKey, addCtrl.text, widget.seeds);
                        addCtrl.clear();
                        await reloadSheet();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14)),
                    onPressed: () async {
                      await _svc.addOption(
                          widget.fieldKey, addCtrl.text, widget.seeds);
                      addCtrl.clear();
                      await reloadSheet();
                    },
                    child: const Text('Add'),
                  ),
                ]),
              ],
            ),
          );
        },
      ),
    );

    if (mounted) setState(() {}); // reflect any changes in the field
  }
}
