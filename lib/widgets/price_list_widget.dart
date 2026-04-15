import 'package:flutter/material.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// Price List Engine v2 — Multi-category support
//
// Supports:  Balloon decorators  |  Personal trainers
// Data:      users/{uid}.priceList  (Map, schema varies by category type)
// ═══════════════════════════════════════════════════════════════════════════════

// ── Category detection ──────────────────────────────────────────────────────

const Set<String> _balloonCats = {
  'מעצבת בלונים', 'אמנית בלונים', 'בלונים לאירועים', 'עיצוב בלונים',
};
const Set<String> _trainerCats = {
  'מאמן כושר', 'פילאטיס', 'יוגה', 'אימון אישי',
  'כושר כללי', 'אימון כושר', 'ריצה וסיבולת', 'אומנויות לחימה',
};

enum PriceListType { none, balloon, trainer }

PriceListType priceListType(Map<String, dynamic> userData) {
  final svc    = (userData['serviceType']    as String? ?? '').trim();
  final parent = (userData['parentCategory'] as String? ?? '').trim();
  if (_balloonCats.contains(svc) || _balloonCats.contains(parent)) return PriceListType.balloon;
  if (_trainerCats.contains(svc) || _trainerCats.contains(parent)) return PriceListType.trainer;
  return PriceListType.none;
}

bool hasPriceList(Map<String, dynamic> userData) =>
    priceListType(userData) != PriceListType.none;

// ── Shared helpers ──────────────────────────────────────────────────────────

String _fmtN(dynamic v) {
  if (v == null) return '';
  if (v is num && v == v.roundToDouble()) return '${v.toInt()}';
  return '$v';
}

String _fmtPrice(double v) => v == v.roundToDouble() ? '${v.toInt()}' : v.toStringAsFixed(1);

Widget _chip(String text) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text, style: const TextStyle(fontSize: 12, color: Color(0xFF374151))),
    );

Widget _sectionLabel(String text, Color color) => Align(
      alignment: AlignmentDirectional.centerEnd,
      child: Text(text, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: color)),
    );

Widget _numField(TextEditingController ctrl, String hint, {ValueChanged<String>? onChanged}) =>
    TextField(
      controller: ctrl,
      keyboardType: TextInputType.number,
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
      onChanged: onChanged,
    );

// ═════════════════════════════════════════════════════════════════════════════
//  BALLOON — defaults, editor, display + calculator
// ═════════════════════════════════════════════════════════════════════════════

const List<Map<String, String>> _defaultBalloonItems = [
  {'name': 'קשת בלונים אורגנית', 'unit': 'למטר'},
  {'name': 'זר ספרות על בסיס',   'unit': 'יחידה'},
  {'name': 'עמוד בלונים',        'unit': 'יחידה'},
  {'name': 'מרכז שולחן בלונים',  'unit': 'יחידה'},
  {'name': 'קיר בלונים',         'unit': 'למ"ר'},
  {'name': 'בלון ענק עם קונפטי', 'unit': 'יחידה'},
];

// ═════════════════════════════════════════════════════════════════════════════
//  TRAINER — defaults
// ═════════════════════════════════════════════════════════════════════════════

const List<Map<String, String>> _defaultTrainerItems = [
  {'name': 'אימון אישי 1:1',       'unit': 'לשעה'},
  {'name': 'כרטיסיית 10 אימונים',  'unit': 'חבילה'},
  {'name': 'אימון קבוצתי',         'unit': 'למשתתף'},
  {'name': 'ליווי אונליין חודשי',  'unit': 'לחודש'},
];

const List<String> _locationOptions = ['סטודיו', 'בית הלקוח', 'פארק', 'אונליין'];

// ═════════════════════════════════════════════════════════════════════════════
//  UNIFIED EDITOR  (renders balloon or trainer form based on type)
// ═════════════════════════════════════════════════════════════════════════════

class PriceListEditor extends StatefulWidget {
  final Map<String, dynamic> initialData;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final PriceListType type;

  const PriceListEditor({
    super.key,
    required this.initialData,
    required this.onChanged,
    this.type = PriceListType.balloon,
  });

  @override
  State<PriceListEditor> createState() => _PriceListEditorState();
}

class _PriceListEditorState extends State<PriceListEditor> {
  // Shared
  final List<_ItemRow> _items = [];
  final List<_PackageRow> _packages = [];

  // Balloon-specific
  late final TextEditingController _minOrderCtrl;
  late final TextEditingController _setupFeeCtrl;
  late final TextEditingController _radiusCtrl;

  // Trainer-specific
  Set<String> _locations = {};
  bool _healthDeclaration = false;
  late final TextEditingController _cancellationCtrl;
  late final TextEditingController _trialPriceCtrl;

  bool get _isBalloon => widget.type == PriceListType.balloon;
  bool get _isTrainer => widget.type == PriceListType.trainer;

  @override
  void initState() {
    super.initState();
    final d = widget.initialData;

    // Balloon fields
    _minOrderCtrl = TextEditingController(text: _fmtN(d['minOrder']));
    _setupFeeCtrl = TextEditingController(text: _fmtN(d['setupFee']));
    _radiusCtrl   = TextEditingController(text: '${(d['deliveryRadius'] as num?) ?? 30}');

    // Trainer fields
    _locations = Set<String>.from((d['locations'] as List?) ?? []);
    _healthDeclaration = d['healthDeclaration'] == true;
    _cancellationCtrl = TextEditingController(text: d['cancellationNote'] as String? ?? '');
    _trialPriceCtrl = TextEditingController(text: _fmtN(d['trialPrice']));

    // Items
    final rawItems = d['items'] as List? ?? [];
    final defaults = _isBalloon ? _defaultBalloonItems : _defaultTrainerItems;
    if (rawItems.isNotEmpty) {
      for (final item in rawItems) {
        final m = item as Map<String, dynamic>;
        _items.add(_ItemRow(
          name: m['name'] as String? ?? '',
          unit: m['unit'] as String? ?? 'יחידה',
          priceCtrl: TextEditingController(text: _fmtN(m['price'])),
        ));
      }
    } else {
      for (final def in defaults) {
        _items.add(_ItemRow(name: def['name']!, unit: def['unit']!, priceCtrl: TextEditingController()));
      }
    }

    // Packages
    final rawPkgs = d['packages'] as List? ?? [];
    for (final pkg in rawPkgs) {
      final m = pkg as Map<String, dynamic>;
      _packages.add(_PackageRow(
        nameCtrl: TextEditingController(text: m['name'] as String? ?? ''),
        descCtrl: TextEditingController(text: m['desc'] as String? ?? ''),
        priceCtrl: TextEditingController(text: _fmtN(m['price'])),
      ));
    }
  }

  void _emit() {
    final items = _items
        .where((i) => i.priceCtrl.text.trim().isNotEmpty)
        .map((i) => {'name': i.name, 'unit': i.unit, 'price': double.tryParse(i.priceCtrl.text.trim()) ?? 0})
        .toList();
    final packages = _packages
        .where((p) => p.nameCtrl.text.trim().isNotEmpty)
        .map((p) => {'name': p.nameCtrl.text.trim(), 'desc': p.descCtrl.text.trim(), 'price': double.tryParse(p.priceCtrl.text.trim()) ?? 0})
        .toList();

    final data = <String, dynamic>{'items': items, 'packages': packages};

    if (_isBalloon) {
      data['minOrder'] = double.tryParse(_minOrderCtrl.text.trim()) ?? 0;
      data['setupFee'] = double.tryParse(_setupFeeCtrl.text.trim()) ?? 0;
      data['deliveryRadius'] = int.tryParse(_radiusCtrl.text.trim()) ?? 30;
    }
    if (_isTrainer) {
      data['locations'] = _locations.toList();
      data['healthDeclaration'] = _healthDeclaration;
      data['cancellationNote'] = _cancellationCtrl.text.trim();
      final trial = double.tryParse(_trialPriceCtrl.text.trim()) ?? 0;
      if (trial > 0) data['trialPrice'] = trial;
    }

    widget.onChanged(data);
  }

  @override
  void dispose() {
    _minOrderCtrl.dispose(); _setupFeeCtrl.dispose(); _radiusCtrl.dispose();
    _cancellationCtrl.dispose(); _trialPriceCtrl.dispose();
    for (final i in _items) { i.priceCtrl.dispose(); }
    for (final p in _packages) { p.nameCtrl.dispose(); p.descCtrl.dispose(); p.priceCtrl.dispose(); }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = _isBalloon ? const Color(0xFF92400E) : const Color(0xFF065F46);
    final bg     = _isBalloon ? const Color(0xFFFFF7ED) : const Color(0xFFECFDF5);
    final border = _isBalloon ? const Color(0xFFFDBA74) : const Color(0xFF6EE7B7);
    final icon   = _isBalloon ? Icons.receipt_long_rounded : Icons.fitness_center_rounded;
    final iconC  = _isBalloon ? const Color(0xFFF59E0B) : const Color(0xFF10B981);
    final title  = _isBalloon ? 'מחירון מפורט' : 'מחירון אימונים';

    return Container(
      margin: const EdgeInsets.only(top: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16), border: Border.all(color: border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(children: [
            Icon(icon, color: iconC, size: 22), const SizedBox(width: 8),
            Expanded(child: Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: accent))),
          ]),
          const SizedBox(height: 4),
          Text('המחירון יוצג ללקוחות בפרופיל שלך', style: TextStyle(fontSize: 12, color: accent.withValues(alpha: 0.7))),
          const SizedBox(height: 16),

          // ── Category-specific settings ──────────────────────────────────
          if (_isBalloon) ..._buildBalloonSettings(accent),
          if (_isTrainer) ..._buildTrainerSettings(accent),

          // ── Items ──────────────────────────────────────────────────────
          const SizedBox(height: 20),
          _sectionLabel(_isBalloon ? 'פריטים' : 'שירותים', accent),
          const SizedBox(height: 8),
          ...List.generate(_items.length, (i) => _buildItemRow(i, accent)),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: () => setState(() => _items.add(_ItemRow(name: 'פריט חדש', unit: 'יחידה', priceCtrl: TextEditingController()))),
              icon: const Icon(Icons.add, size: 18), label: Text('הוסף ${_isBalloon ? "פריט" : "שירות"}', style: const TextStyle(fontSize: 13)),
            ),
          ),
          const SizedBox(height: 16),

          // ── Packages ──────────────────────────────────────────────────
          _sectionLabel(_isTrainer ? 'חבילות טרנספורמציה' : 'חבילות הכל כלול', accent),
          const SizedBox(height: 8),
          ...List.generate(_packages.length, (i) => _buildPackageRow(i, border)),
          if (_packages.length < 3)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: () => setState(() => _packages.add(_PackageRow(nameCtrl: TextEditingController(), descCtrl: TextEditingController(), priceCtrl: TextEditingController()))),
                icon: const Icon(Icons.add, size: 18), label: const Text('הוסף חבילה', style: TextStyle(fontSize: 13)),
              ),
            ),
        ],
      ),
    );
  }

  // ── Balloon settings row ──────────────────────────────────────────────────
  List<Widget> _buildBalloonSettings(Color accent) => [
        _sectionLabel('כללי', accent),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: _numField(_minOrderCtrl, 'מינימום ₪', onChanged: (_) => _emit())),
          const SizedBox(width: 10),
          Expanded(child: _numField(_setupFeeCtrl, 'הקמה ₪', onChanged: (_) => _emit())),
          const SizedBox(width: 10),
          Expanded(child: _numField(_radiusCtrl, 'רדיוס ק"מ', onChanged: (_) => _emit())),
        ]),
      ];

  // ── Trainer settings ──────────────────────────────────────────────────────
  List<Widget> _buildTrainerSettings(Color accent) => [
        _sectionLabel('מיקום אימון', accent),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8, runSpacing: 6,
          children: _locationOptions.map((loc) {
            final selected = _locations.contains(loc);
            return FilterChip(
              label: Text(loc, style: TextStyle(fontSize: 13, color: selected ? Colors.white : const Color(0xFF065F46))),
              selected: selected,
              selectedColor: const Color(0xFF10B981),
              checkmarkColor: Colors.white,
              backgroundColor: Colors.white,
              side: BorderSide(color: selected ? const Color(0xFF10B981) : Colors.grey.shade300),
              onSelected: (v) { setState(() { v ? _locations.add(loc) : _locations.remove(loc); }); _emit(); },
            );
          }).toList(),
        ),
        const SizedBox(height: 14),
        // Trial session
        Row(children: [
          SizedBox(width: 90, child: _numField(_trialPriceCtrl, '₪', onChanged: (_) => _emit())),
          const SizedBox(width: 10),
          const Expanded(child: Text('מחיר אימון ניסיון', textAlign: TextAlign.end, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14))),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: const Color(0xFFEF4444), borderRadius: BorderRadius.circular(6)),
            child: const Text('מבצע', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
          ),
        ]),
        const SizedBox(height: 14),
        // Health declaration + cancellation
        SwitchListTile.adaptive(
          value: _healthDeclaration,
          onChanged: (v) { setState(() => _healthDeclaration = v); _emit(); },
          activeColor: const Color(0xFF10B981),
          contentPadding: EdgeInsets.zero,
          title: const Text('נדרש הצהרת בריאות', textAlign: TextAlign.end, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
        ),
        TextField(
          controller: _cancellationCtrl,
          textAlign: TextAlign.end,
          maxLines: 2,
          style: const TextStyle(fontSize: 13),
          decoration: InputDecoration(
            hintText: 'מדיניות ביטול (למשל: ביטול עד 12 שעות לפני)',
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onChanged: (_) => _emit(),
        ),
      ];

  // ── Shared item row builder ───────────────────────────────────────────────
  Widget _buildItemRow(int i, Color accent) {
    final item = _items[i];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        GestureDetector(
          onTap: () { setState(() => _items.removeAt(i)); _emit(); },
          child: const Icon(Icons.remove_circle_outline, color: Colors.red, size: 20),
        ),
        const SizedBox(width: 8),
        SizedBox(width: 80, child: _numField(item.priceCtrl, '₪', onChanged: (_) => _emit())),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade300)),
          child: Text(item.unit, style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(item.name, textAlign: TextAlign.end, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500))),
      ]),
    );
  }

  // ── Shared package row builder ────────────────────────────────────────────
  Widget _buildPackageRow(int i, Color border) {
    final pkg = _packages[i];
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: border.withValues(alpha: 0.5))),
      child: Column(children: [
        Row(children: [
          GestureDetector(onTap: () { setState(() => _packages.removeAt(i)); _emit(); }, child: const Icon(Icons.close, color: Colors.red, size: 18)),
          const SizedBox(width: 8),
          SizedBox(width: 80, child: _numField(pkg.priceCtrl, '₪', onChanged: (_) => _emit())),
          const SizedBox(width: 8),
          Expanded(child: TextField(
            controller: pkg.nameCtrl, textAlign: TextAlign.end,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            decoration: const InputDecoration(hintText: 'שם החבילה', isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8), border: OutlineInputBorder()),
            onChanged: (_) => _emit(),
          )),
        ]),
        const SizedBox(height: 8),
        TextField(
          controller: pkg.descCtrl, textAlign: TextAlign.end, maxLines: 2,
          style: const TextStyle(fontSize: 13),
          decoration: const InputDecoration(hintText: 'תיאור (מה כלול?)', isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8), border: OutlineInputBorder()),
          onChanged: (_) => _emit(),
        ),
      ]),
    );
  }
}

class _ItemRow {
  String name;
  String unit;
  final TextEditingController priceCtrl;
  _ItemRow({required this.name, required this.unit, required this.priceCtrl});
}

class _PackageRow {
  final TextEditingController nameCtrl;
  final TextEditingController descCtrl;
  final TextEditingController priceCtrl;
  _PackageRow({required this.nameCtrl, required this.descCtrl, required this.priceCtrl});
}

// ═════════════════════════════════════════════════════════════════════════════
//  UNIFIED DISPLAY  (client view — renders balloon or trainer style)
// ═════════════════════════════════════════════════════════════════════════════

class PriceListDisplay extends StatefulWidget {
  final Map<String, dynamic> priceList;
  final Map<String, dynamic> userData;
  /// Called with a pre-filled message string when the client taps "Send Quote".
  final ValueChanged<String>? onSendQuote;

  const PriceListDisplay({
    super.key,
    required this.priceList,
    required this.userData,
    this.onSendQuote,
  });

  @override
  State<PriceListDisplay> createState() => _PriceListDisplayState();
}

class _PriceListDisplayState extends State<PriceListDisplay> {
  // Calculator state (balloon only)
  final Map<int, int> _quantities = {}; // itemIndex → qty

  double get _setupFee => (widget.priceList['setupFee'] as num?)?.toDouble() ?? 0;

  double get _calcTotal {
    final items = (widget.priceList['items'] as List? ?? []).cast<Map<String, dynamic>>();
    double sum = 0;
    for (int i = 0; i < items.length; i++) {
      final qty = _quantities[i] ?? 0;
      if (qty <= 0) continue;
      final price = (items[i]['price'] as num?)?.toDouble() ?? 0;
      sum += price * qty;
    }
    if (sum > 0) sum += _setupFee;
    return sum;
  }

  String _buildQuoteMessage() {
    final items = (widget.priceList['items'] as List? ?? []).cast<Map<String, dynamic>>();
    final lines = <String>[];
    for (int i = 0; i < items.length; i++) {
      final qty = _quantities[i] ?? 0;
      if (qty <= 0) continue;
      final name = items[i]['name'] as String? ?? '';
      final unit = items[i]['unit'] as String? ?? '';
      final price = (items[i]['price'] as num?)?.toDouble() ?? 0;
      lines.add('$name — $qty $unit × ₪${_fmtPrice(price)} = ₪${_fmtPrice(price * qty)}');
    }
    if (_setupFee > 0) lines.add('דמי הקמה: ₪${_fmtPrice(_setupFee)}');
    lines.add('סה"כ משוער: ₪${_fmtPrice(_calcTotal)}');
    return 'היי, אשמח לקבל הצעת מחיר:\n${lines.join('\n')}';
  }

  @override
  Widget build(BuildContext context) {
    final type     = priceListType(widget.userData);
    final items    = (widget.priceList['items']    as List? ?? []).cast<Map<String, dynamic>>();
    final packages = (widget.priceList['packages'] as List? ?? []).cast<Map<String, dynamic>>();
    final minOrder = (widget.priceList['minOrder'] as num?)?.toDouble() ?? 0;
    final setupFee = _setupFee;
    final radius   = (widget.priceList['deliveryRadius'] as num?)?.toInt() ?? 0;
    final trialPrice = (widget.priceList['trialPrice'] as num?)?.toDouble() ?? 0;
    final locations  = (widget.priceList['locations'] as List?)?.cast<String>() ?? [];
    final healthDecl = widget.priceList['healthDeclaration'] == true;
    final cancelNote = widget.priceList['cancellationNote'] as String? ?? '';

    if (items.isEmpty && packages.isEmpty && trialPrice <= 0) return const SizedBox.shrink();

    final isBalloon = type == PriceListType.balloon;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        const Divider(height: 1),
        const SizedBox(height: 24),
        // Header
        Row(children: [
          Icon(isBalloon ? Icons.receipt_long_rounded : Icons.fitness_center_rounded,
              color: isBalloon ? const Color(0xFFF59E0B) : const Color(0xFF10B981), size: 22),
          const SizedBox(width: 8),
          const Expanded(child: Text('מחירון וחבילות', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17))),
        ]),
        const SizedBox(height: 12),

        // ── Trainer: location chips + trial session ─────────────────────
        if (!isBalloon && locations.isNotEmpty) ...[
          Wrap(
            spacing: 8, runSpacing: 6,
            children: locations.map((l) => _chip(l)).toList(),
          ),
          const SizedBox(height: 10),
        ],
        if (!isBalloon && trialPrice > 0) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFFECFDF5), Color(0xFFD1FAE5)]),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF6EE7B7)),
            ),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: const Color(0xFFEF4444), borderRadius: BorderRadius.circular(6)),
                child: const Text('מבצע', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 8),
              Text('₪${_fmtPrice(trialPrice)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: Color(0xFF065F46))),
              const Spacer(),
              const Text('אימון ניסיון', textAlign: TextAlign.end, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              const SizedBox(width: 6),
              const Icon(Icons.local_fire_department_rounded, color: Color(0xFFEF4444), size: 20),
            ]),
          ),
          const SizedBox(height: 12),
        ],

        // ── Balloon: general info chips ─────────────────────────────────
        if (isBalloon && (minOrder > 0 || setupFee > 0 || radius > 0)) ...[
          Wrap(spacing: 8, runSpacing: 6, children: [
            if (minOrder > 0) _chip('מינימום: ₪${_fmtPrice(minOrder)}'),
            if (setupFee > 0) _chip('הקמה: ₪${_fmtPrice(setupFee)}'),
            if (radius > 0)   _chip('משלוח עד $radius ק"מ'),
          ]),
          const SizedBox(height: 16),
        ],

        // ── Items ───────────────────────────────────────────────────────
        if (items.isNotEmpty) ...[
          ...List.generate(items.length, (i) {
            final item  = items[i];
            final name  = item['name'] as String? ?? '';
            final unit  = item['unit'] as String? ?? '';
            final price = (item['price'] as num?)?.toDouble() ?? 0;
            if (price <= 0) return const SizedBox.shrink();
            final isPerUnit = unit.contains('מטר') || unit.contains('מ"ר') || unit.contains('משתתף');
            final qty = _quantities[i] ?? 0;

            return Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: qty > 0 ? const Color(0xFFF0F0FF) : Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: qty > 0 ? const Color(0xFF6366F1).withValues(alpha: 0.3) : Colors.grey.shade200),
              ),
              child: Column(
                children: [
                  Row(children: [
                    Text('₪${_fmtPrice(price)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF6366F1))),
                    const SizedBox(width: 6),
                    Text('/ $unit', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                    const Spacer(),
                    Flexible(child: Text(name, textAlign: TextAlign.end, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500))),
                  ]),
                  // Quantity selector for per-unit items (balloon calculator)
                  if (isBalloon && isPerUnit) ...[
                    const SizedBox(height: 8),
                    Row(children: [
                      // Decrement
                      _qtyBtn(Icons.remove, () { if (qty > 0) setState(() => _quantities[i] = qty - 1); }),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text('$qty', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      ),
                      // Increment
                      _qtyBtn(Icons.add, () => setState(() => _quantities[i] = qty + 1)),
                      const Spacer(),
                      if (qty > 0) Text('= ₪${_fmtPrice(price * qty)}', style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF6366F1))),
                    ]),
                  ],
                  // Fixed items: simple add/remove toggle
                  if (isBalloon && !isPerUnit) ...[
                    const SizedBox(height: 6),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: GestureDetector(
                        onTap: () => setState(() => _quantities[i] = qty > 0 ? 0 : 1),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: qty > 0 ? const Color(0xFF6366F1) : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(qty > 0 ? 'נבחר' : 'הוסף',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: qty > 0 ? Colors.white : Colors.grey[600])),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            );
          }),
          const SizedBox(height: 8),
        ],

        // ── Balloon event calculator total ──────────────────────────────
        if (isBalloon && _calcTotal > 0) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF6366F1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(children: [
              Row(children: [
                Text('₪${_fmtPrice(_calcTotal)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 22, color: Colors.white)),
                if (_setupFee > 0) ...[
                  const SizedBox(width: 8),
                  Text('(כולל ₪${_fmtPrice(_setupFee)} הקמה)', style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.7))),
                ],
                const Spacer(),
                const Text('סה"כ משוער', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white)),
              ]),
              if (widget.onSendQuote != null) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF6366F1),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    icon: const Icon(Icons.send_rounded, size: 18),
                    label: const Text('שלח בקשת הצעת מחיר', style: TextStyle(fontWeight: FontWeight.bold)),
                    onPressed: () => widget.onSendQuote!(_buildQuoteMessage()),
                  ),
                ),
              ],
            ]),
          ),
          const SizedBox(height: 16),
        ],

        // ── Packages ────────────────────────────────────────────────────
        if (packages.isNotEmpty) ...[
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Text(isBalloon ? 'חבילות הכל כלול' : 'חבילות טרנספורמציה',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFFD97706))),
          ),
          const SizedBox(height: 8),
          ...packages.map((pkg) {
            final name  = pkg['name'] as String? ?? '';
            final desc  = pkg['desc'] as String? ?? '';
            final price = (pkg['price'] as num?)?.toDouble() ?? 0;
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isBalloon
                      ? [const Color(0xFFFFF7ED), const Color(0xFFFEF3C7)]
                      : [const Color(0xFFECFDF5), const Color(0xFFD1FAE5)],
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: isBalloon ? const Color(0xFFFBBF24) : const Color(0xFF6EE7B7)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isBalloon ? const Color(0xFFF59E0B) : const Color(0xFF10B981),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('₪${_fmtPrice(price)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white)),
                  ),
                  const Spacer(),
                  Flexible(child: Text(name, textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
                  const SizedBox(width: 6),
                  const Icon(Icons.local_offer_rounded, color: Color(0xFFF59E0B), size: 18),
                ]),
                if (desc.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(desc, textAlign: TextAlign.end, style: TextStyle(fontSize: 13, color: Colors.grey[700])),
                ],
              ]),
            );
          }),
        ],

        // ── Trainer: health declaration + cancellation ──────────────────
        if (!isBalloon && (healthDecl || cancelNote.isNotEmpty)) ...[
          const SizedBox(height: 12),
          if (healthDecl)
            Row(children: [
              const Icon(Icons.medical_services_outlined, size: 16, color: Color(0xFFEF4444)),
              const SizedBox(width: 6),
              const Text('נדרש הצהרת בריאות', style: TextStyle(fontSize: 13, color: Color(0xFFEF4444), fontWeight: FontWeight.w500)),
            ]),
          if (cancelNote.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(children: [
              const Icon(Icons.info_outline, size: 16, color: Color(0xFF6B7280)),
              const SizedBox(width: 6),
              Expanded(child: Text(cancelNote, style: TextStyle(fontSize: 12, color: Colors.grey[600]))),
            ]),
          ],
        ],
      ],
    );
  }

  Widget _qtyBtn(IconData icon, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 32, height: 32,
          decoration: BoxDecoration(
            color: const Color(0xFF6366F1).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 18, color: const Color(0xFF6366F1)),
        ),
      );
}
