// lib/screens/ReportsScreen.dart
// FINAL REPORTS MODULE V3.1 CLEAN FIX
// Includes:
// - Overview scope selector for Admin: ALL / SFP / CC / CE
// - Premium dropdown design, not autocomplete
// - Individual search with local autocomplete
// - Person-specific categories/templates
// - Category breakdown under individual chart
// - Comparison no-data message
// - Premium PDF with logo + KPI + trend + category tables

import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'api_helper.dart';
import 'assessment_category.dart';
import 'home.dart';
import 'Profiles.dart';

// ==================== VISUAL CONSTANTS ====================
const _bg = Color(0xFFEFF6FF);
const _text = Color(0xFF0F172A);
const _muted = Color(0xFF64748B);
const _primary = Color(0xFF2563EB);
const _primarySoft = Color(0xFFEFF6FF);
const _border = Color(0xFFE2E8F0);
const _success = Color(0xFF16A34A);
const _danger = Color(0xFFDC2626);
const _warning = Color(0xFFF59E0B);

class ReportsScreen extends StatefulWidget {
  final String role;
  final String username;
  final String subrole;
  final String position;
  final String? nationalSupervisorId;
  final String? supervisorId;

  const ReportsScreen({
    super.key,
    required this.role,
    required this.username,
    required this.subrole,
    required this.position,
    this.nationalSupervisorId,
    this.supervisorId,
  });

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen>
    with TickerProviderStateMixin {
  bool _isSidebarVisible = false;
  int _selectedTab = 0;

  // Global filter options from backend
  List<Map<String, dynamic>> _employees = [];
  List<Map<String, dynamic>> _teams = [];
  List<String> _subroles = [];
  List<String> _roles = [];

  // Individual person-specific filters
  List<String> _personCategories = [];
  List<Map<String, dynamic>> _personTemplates = [];
  bool _loadingPersonFilters = false;

  bool _loadingFilters = true;
  String? _filterError;

  // Overview state
  Map<String, dynamic>? _overviewData;
  bool _loadingOverview = false;
  String? _overviewError;
  String _overviewRange = 'All Time';
  String _overviewScope = 'ALL';

  // Individual trend state
  final TextEditingController _employeeSearchCtrl = TextEditingController();
  List<Map<String, dynamic>> _employeeSuggestions = [];
  bool _searchingEmployees = false;
  Timer? _employeeDebounce;

  Map<String, dynamic>? _selectedEmployee;
  String _trendType = 'overall';
  String? _selectedCategory;
  Map<String, dynamic>? _selectedTemplate;
  List<Map<String, dynamic>> _trendData = [];
  Map<String, dynamic>? _trendSummary;
  bool _loadingTrend = false;
  String? _trendError;

  // Individual category breakdown
  List<Map<String, dynamic>> _categoryBreakdown = [];
  bool _loadingCategoryBreakdown = false;
  String? _categoryBreakdownError;

  // Comparison state
  final TextEditingController _leftSearchCtrl = TextEditingController();
  final TextEditingController _rightSearchCtrl = TextEditingController();
  List<Map<String, dynamic>> _leftSuggestions = [];
  List<Map<String, dynamic>> _rightSuggestions = [];
  bool _searchingLeft = false;
  bool _searchingRight = false;
  Timer? _leftDebounce;
  Timer? _rightDebounce;

  String _comparisonType = 'person';
  Map<String, dynamic>? _leftEntity;
  Map<String, dynamic>? _rightEntity;
  String? _leftSubrole;
  String? _rightSubrole;
  String? _leftRole;
  String? _rightRole;
  List<Map<String, dynamic>> _leftTrend = [];
  List<Map<String, dynamic>> _rightTrend = [];
  Map<String, dynamic>? _comparisonSummary;
  bool _loadingComparison = false;
  String? _comparisonError;

  // Gradient animation
  late AnimationController _gradientController;
  late Animation<double> _gradientAnimation;

  final List<List<Color>> gradientSets = const [
    Color(0xFF1E3A8A),
    Color(0xFF3730A3),
    Color(0xFF4338CA),
    Color(0xFF0F172A),
    Color(0xFF1E293B),
    Color(0xFF334155),
    Color(0xFF2563EB),
    Color(0xFF3B82F6),
    Color(0xFF60A5FA),
  ].slices(3);

  int _gNow = 0;
  int _gNext = 1;

  bool get _isAdmin =>
      widget.role.toLowerCase() == 'admin' ||
      widget.position.toLowerCase() == 'all';

  bool get _isChannelManager =>
      widget.position.toLowerCase() == 'channel manager';

  bool get _isSupervisor => widget.position.toLowerCase() == 'supervisor';

  List<String> get _overviewScopeItems {
    if (_isAdmin) return const ['ALL', 'SFP', 'CC', 'CE'];
    final role = widget.role.trim().toUpperCase();
    if (role.isEmpty) return const ['ALL'];
    return [role];
  }

  @override
  void initState() {
    super.initState();
    if (!_isAdmin) {
      _overviewScope = widget.role.trim().toUpperCase().isEmpty
          ? 'ALL'
          : widget.role.trim().toUpperCase();
    }
    _initGradient();
    _loadFilterOptions();
    _loadOverviewData();
  }

  void _initGradient() {
    _gradientController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _gNow = _gNext;
          _gNext = (_gNext + 1) % gradientSets.length;
          _gradientController.forward(from: 0);
        }
      });

    _gradientAnimation = CurvedAnimation(
      parent: _gradientController,
      curve: Curves.easeInOut,
    );
    _gradientController.forward();
  }

  @override
  void dispose() {
    _gradientController.dispose();
    _employeeSearchCtrl.dispose();
    _leftSearchCtrl.dispose();
    _rightSearchCtrl.dispose();
    _employeeDebounce?.cancel();
    _leftDebounce?.cancel();
    _rightDebounce?.cancel();
    super.dispose();
  }

  // ==================== DATA LOADING ====================

  Future<void> _loadFilterOptions() async {
    setState(() {
      _loadingFilters = true;
      _filterError = null;
    });

    try {
      final resp = await ApiHelper.post('/reports/filter_options', {
        'username': widget.username,
        'position': widget.position,
        'role': widget.role,
        'subrole': widget.subrole,
      });

      if (!mounted) return;

      if (resp.statusCode == 401) {
        await _handleUnauthorized();
        return;
      }

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;

        setState(() {
          _employees = _asMapList(data['employees']);
          _teams = _asMapList(data['teams']);
          _subroles = _asStringList(data['subroles']);
          _roles = _asStringList(data['roles']);
          if (_roles.isEmpty && _isAdmin) _roles = ['SFP', 'CC', 'CE'];
          _loadingFilters = false;
        });
      } else {
        setState(() {
          _filterError = _extractMessage(
            resp.body,
            'Failed to load filters: HTTP ${resp.statusCode}',
          );
          _loadingFilters = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _filterError = 'Connection error: $e';
        _loadingFilters = false;
      });
    }
  }

  Future<void> _loadOverviewData() async {
    setState(() {
      _loadingOverview = true;
      _overviewError = null;
    });

    try {
      final range = _resolveRange(_overviewRange);
      final body = <String, dynamic>{
        'date_from': range.$1,
        'date_to': range.$2,
      };

      // Admin can choose between ALL / SFP / CC / CE.
      // Backend must apply this optional role_scope filter.
      if (_isAdmin && _overviewScope != 'ALL') {
        body['role_scope'] = _overviewScope;
      }

      final resp = await ApiHelper.post('/reports/team_overview', body);

      if (!mounted) return;

      if (resp.statusCode == 401) {
        await _handleUnauthorized();
        return;
      }

      if (resp.statusCode == 200) {
        setState(() {
          _overviewData = jsonDecode(resp.body) as Map<String, dynamic>;
          _loadingOverview = false;
        });
      } else {
        setState(() {
          _overviewError = _extractMessage(
            resp.body,
            'Failed to load overview: HTTP ${resp.statusCode}',
          );
          _loadingOverview = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _overviewError = 'Connection error: $e';
        _loadingOverview = false;
      });
    }
  }

  Future<void> _loadPersonFilterOptions(int profileId) async {
    setState(() {
      _loadingPersonFilters = true;
      _personCategories = [];
      _personTemplates = [];
      _selectedCategory = null;
      _selectedTemplate = null;
    });

    try {
      final resp = await ApiHelper.post('/reports/person_filter_options', {
        'profile_id': profileId,
      });

      if (!mounted) return;

      if (resp.statusCode == 401) {
        await _handleUnauthorized();
        return;
      }

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        setState(() {
          _personCategories = _asStringListPreserveCase(data['categories']);
          _personTemplates = _asMapList(data['templates']);
          _loadingPersonFilters = false;
        });
      } else {
        setState(() => _loadingPersonFilters = false);
        _toast(_extractMessage(resp.body, 'Could not load person filters.'));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingPersonFilters = false);
      _toast('Could not load person filters: $e');
    }
  }

  Future<void> _loadPersonCategoryBreakdown() async {
    if (_selectedEmployee == null) return;

    setState(() {
      _loadingCategoryBreakdown = true;
      _categoryBreakdownError = null;
      _categoryBreakdown = [];
    });

    try {
      final resp = await ApiHelper.post('/reports/person_category_breakdown', {
        'profile_id': _selectedEmployee!['id'],
      });

      if (!mounted) return;

      if (resp.statusCode == 401) {
        await _handleUnauthorized();
        return;
      }

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        setState(() {
          _categoryBreakdown = _asMapList(data['categories']);
          _loadingCategoryBreakdown = false;
        });
      } else {
        setState(() {
          _categoryBreakdownError = _extractMessage(
            resp.body,
            'Failed to load category breakdown.',
          );
          _loadingCategoryBreakdown = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _categoryBreakdownError = 'Connection error: $e';
        _loadingCategoryBreakdown = false;
      });
    }
  }

  Future<void> _loadPersonTrend() async {
    if (_selectedEmployee == null) {
      _toast('Please select an employee first.');
      return;
    }

    if (_trendType == 'category' && _selectedCategory == null) {
      _toast('Please select a category.');
      return;
    }

    if (_trendType == 'template' && _selectedTemplate == null) {
      _toast('Please select a template.');
      return;
    }

    setState(() {
      _loadingTrend = true;
      _trendError = null;
      _trendData = [];
      _trendSummary = null;
    });

    try {
      final body = <String, dynamic>{
        'profile_id': _selectedEmployee!['id'],
        'trend_type': _trendType,
        if (_trendType == 'category') 'category_title': _selectedCategory,
        if (_trendType == 'template') 'template_id': _selectedTemplate!['id'],
      };

      final resp = await ApiHelper.post('/reports/person_trend', body);

      if (!mounted) return;

      if (resp.statusCode == 401) {
        await _handleUnauthorized();
        return;
      }

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        setState(() {
          _trendData = _asMapList(data['trend']);
          _trendSummary = data['summary'] is Map
              ? Map<String, dynamic>.from(data['summary'] as Map)
              : null;
          _loadingTrend = false;
        });
      } else {
        setState(() {
          _trendError = _extractMessage(
            resp.body,
            'Failed to load trend: HTTP ${resp.statusCode}',
          );
          _loadingTrend = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _trendError = 'Connection error: $e';
        _loadingTrend = false;
      });
    }
  }

  Future<void> _loadComparisonTrend() async {
    if (_comparisonType == 'person' &&
        (_leftEntity == null || _rightEntity == null)) {
      _toast('Please select both employees.');
      return;
    }

    if (_comparisonType == 'team' &&
        (_leftEntity == null || _rightEntity == null)) {
      _toast('Please select both teams.');
      return;
    }

    if (_comparisonType == 'subrole' &&
        (_leftSubrole == null || _rightSubrole == null)) {
      _toast('Please select both subroles.');
      return;
    }

    if (_comparisonType == 'role' && (_leftRole == null || _rightRole == null)) {
      _toast('Please select both roles.');
      return;
    }

    setState(() {
      _loadingComparison = true;
      _comparisonError = null;
      _leftTrend = [];
      _rightTrend = [];
      _comparisonSummary = null;
    });

    try {
      final body = <String, dynamic>{
        'comparison_type': _comparisonType,
        'metric_mode': 'overall',
        if (_comparisonType == 'person' || _comparisonType == 'team') ...{
          'left_id': _leftEntity!['id'],
          'right_id': _rightEntity!['id'],
        },
        if (_comparisonType == 'subrole') ...{
          'left_value': _leftSubrole,
          'right_value': _rightSubrole,
        },
        if (_comparisonType == 'role') ...{
          'left_value': _leftRole,
          'right_value': _rightRole,
        },
      };

      final resp = await ApiHelper.post('/reports/comparison_trend', body);

      if (!mounted) return;

      if (resp.statusCode == 401) {
        await _handleUnauthorized();
        return;
      }

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final left = data['left'] is Map ? data['left'] as Map : {};
        final right = data['right'] is Map ? data['right'] as Map : {};

        final parsedLeftTrend = _asMapList(left['trend']);
        final parsedRightTrend = _asMapList(right['trend']);
        final summary = data['summary'] is Map
            ? Map<String, dynamic>.from(data['summary'] as Map)
            : null;

        final leftLabel = summary?['left_label']?.toString() ?? 'Left';
        final rightLabel = summary?['right_label']?.toString() ?? 'Right';

        String? noDataMessage;
        if (parsedLeftTrend.isEmpty && parsedRightTrend.isEmpty) {
          noDataMessage = 'No assessment data is available for both selected sides.';
        } else if (parsedLeftTrend.isEmpty) {
          noDataMessage = '$leftLabel has no assessment data for this comparison.';
        } else if (parsedRightTrend.isEmpty) {
          noDataMessage = '$rightLabel has no assessment data for this comparison.';
        }

        setState(() {
          _leftTrend = parsedLeftTrend;
          _rightTrend = parsedRightTrend;
          _comparisonSummary = summary;
          _comparisonError = noDataMessage;
          _loadingComparison = false;
        });
      } else {
        setState(() {
          _comparisonError = _extractMessage(
            resp.body,
            'Failed to load comparison: HTTP ${resp.statusCode}',
          );
          _loadingComparison = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _comparisonError = 'Connection error: $e';
        _loadingComparison = false;
      });
    }
  }

  Future<void> _handleUnauthorized() async {
    await ApiHelper.clearToken();
    if (!mounted) return;
    _toast('Session expired. Please log in again.');
    Navigator.pushReplacementNamed(context, '/');
  }

  // ==================== LOCAL AUTOCOMPLETE ====================

void _searchEmployees(String query) {
  _employeeDebounce?.cancel();

  _employeeDebounce = Timer(const Duration(milliseconds: 160), () {
    final q = query.trim().toLowerCase();

    if (q.isEmpty) {
      if (!mounted) return;
      setState(() {
        _employeeSuggestions = [];
        _searchingEmployees = false;
      });
      return;
    }

    final startsWith = <Map<String, dynamic>>[];
    final contains = <Map<String, dynamic>>[];

    for (final e in _employees) {
      final name = _entityLabel(e).toLowerCase();
      final role = (e['role'] ?? '').toString().toLowerCase();
      final position = (e['position'] ?? '').toString().toLowerCase();
      final subrole = (e['subrole'] ?? '').toString().toLowerCase();

      final searchable = '$name $role $position $subrole';

      if (name.startsWith(q)) {
        startsWith.add(e);
      } else if (searchable.contains(q)) {
        contains.add(e);
      }
    }

    final filtered = [
      ...startsWith,
      ...contains,
    ].take(10).toList();

    if (!mounted) return;
    setState(() {
      _employeeSuggestions = filtered;
      _searchingEmployees = false;
    });
  });

  setState(() => _searchingEmployees = query.trim().isNotEmpty);
}

  void _searchLeft(String query) => _searchLocalComparison(query, true);
  void _searchRight(String query) => _searchLocalComparison(query, false);
void _searchLocalComparison(String query, bool isLeft) {
  final timer = Timer(const Duration(milliseconds: 160), () {
    final q = query.trim().toLowerCase();
    final list = _comparisonType == 'team' ? _teams : _employees;

    if (q.isEmpty) {
      if (!mounted) return;
      setState(() {
        if (isLeft) {
          _leftSuggestions = [];
          _searchingLeft = false;
        } else {
          _rightSuggestions = [];
          _searchingRight = false;
        }
      });
      return;
    }

    final startsWith = <Map<String, dynamic>>[];
    final contains = <Map<String, dynamic>>[];

    for (final e in list) {
      final name = _entityLabel(e).toLowerCase();
      final role = (e['role'] ?? '').toString().toLowerCase();
      final position = (e['position'] ?? '').toString().toLowerCase();
      final subrole = (e['subrole'] ?? '').toString().toLowerCase();

      final searchable = '$name $role $position $subrole';

      if (name.startsWith(q)) {
        startsWith.add(e);
      } else if (searchable.contains(q)) {
        contains.add(e);
      }
    }

    final filtered = [
      ...startsWith,
      ...contains,
    ].take(10).toList();

    if (!mounted) return;
    setState(() {
      if (isLeft) {
        _leftSuggestions = filtered;
        _searchingLeft = false;
      } else {
        _rightSuggestions = filtered;
        _searchingRight = false;
      }
    });
  });

  if (isLeft) {
    _leftDebounce?.cancel();
    _leftDebounce = timer;
    setState(() => _searchingLeft = query.trim().isNotEmpty);
  } else {
    _rightDebounce?.cancel();
    _rightDebounce = timer;
    setState(() => _searchingRight = query.trim().isNotEmpty);
  }
}
  // ==================== PREMIUM PDF EXPORT ====================

  Future<void> _exportToPDF() async {
    final pdf = pw.Document();
    final generatedAt = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());

    pw.MemoryImage? logoImage;
    try {
      final logoBytes = await rootBundle.load('assets/logo.png');
      logoImage = pw.MemoryImage(logoBytes.buffer.asUint8List());
    } catch (_) {
      logoImage = null;
    }

    pdf.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          margin: const pw.EdgeInsets.all(28),
          theme: pw.ThemeData.base(),
        ),
        build: (context) => [
          _pdfHeader(generatedAt, logoImage),
          pw.SizedBox(height: 18),
          if (_selectedTab == 0) ..._overviewPdfContent(),
          if (_selectedTab == 1) ..._individualPdfContent(),
          if (_selectedTab == 2) ..._comparisonPdfContent(),
          pw.SizedBox(height: 24),
          pw.Text(
            'This report was generated from LEAP analytics based on the currently authorized user scope.',
            style: pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
          ),
        ],
      ),
    );

    await Printing.layoutPdf(onLayout: (_) => pdf.save());
  }

  pw.Widget _pdfHeader(String generatedAt, pw.MemoryImage? logoImage) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(18),
      decoration: pw.BoxDecoration(
        color: PdfColor.fromInt(0xFF0F172A),
        borderRadius: pw.BorderRadius.circular(14),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: 54,
            height: 54,
            padding: const pw.EdgeInsets.all(6),
            decoration: pw.BoxDecoration(
              color: PdfColors.white,
              borderRadius: pw.BorderRadius.circular(12),
            ),
            child: logoImage != null
                ? pw.Image(logoImage, fit: pw.BoxFit.contain)
                : pw.Center(
                    child: pw.Text(
                      'PMI',
                      style: pw.TextStyle(
                        color: PdfColor.fromInt(0xFF1E3A8A),
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
          ),
          pw.SizedBox(width: 14),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'PMI LEAP Performance Report',
                  style: pw.TextStyle(
                    color: PdfColors.white,
                    fontSize: 22,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 5),
                pw.Text(
                  'Generated: $generatedAt  •  User: ${widget.username}  •  Scope: ${_pdfScopeLabel()}',
                  style: pw.TextStyle(color: PdfColors.grey300, fontSize: 10),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _pdfScopeLabel() {
    if (_selectedTab == 0) {
      return _isAdmin ? 'Overview / $_overviewScope' : '${widget.role} / ${widget.position}';
    }
    return '${widget.role} / ${widget.position}';
  }

  List<pw.Widget> _overviewPdfContent() {
    final totals = _overviewData?['totals'] as Map?;
    final assessments = totals?['assessments'] ?? 0;
    final avg = _num(totals?['avg_on3']);
    final trend = _asMapList(_overviewData?['trend']);
    final status = _trendStatusFromPoints(trend, scoreKey: 'avg_on3');

    return [
      _pdfSectionTitle('Overview Summary'),
      pw.SizedBox(height: 6),
      pw.Text('Date range: $_overviewRange  •  Scope: $_overviewScope'),
      pw.SizedBox(height: 10),
      pw.Row(
        children: [
          _pdfKpi('Total Assessments', assessments.toString(), PdfColor.fromInt(0xFF2563EB)),
          pw.SizedBox(width: 10),
          _pdfKpi('Average Score', '${avg.toStringAsFixed(2)}/3.0', PdfColor.fromInt(0xFFF59E0B)),
          pw.SizedBox(width: 10),
          _pdfKpi('Trend Status', status, _pdfStatusColor(status)),
        ],
      ),
      pw.SizedBox(height: 18),
      _pdfSimpleTable(
        headers: ['Date', 'Average Score', 'Count'],
        rows: trend
            .map((e) => [
                  e['date']?.toString() ?? '-',
                  '${_num(e['avg_on3']).toStringAsFixed(2)}/3.0',
                  e['count']?.toString() ?? '0',
                ])
            .toList(),
      ),
    ];
  }

  List<pw.Widget> _individualPdfContent() {
    final status = _trendSummary?['status']?.toString() ?? '-';
    final totalAvg = _averageTrendScore(_trendData);
    final totalLevel = _levelFromScore(totalAvg);
    return [
      _pdfSectionTitle('Individual Trend Analysis'),
      pw.SizedBox(height: 10),
      pw.Text('Employee: ${_selectedEmployee == null ? '-' : _entityLabel(_selectedEmployee!)}'),
      pw.Text('Trend Type: $_trendType'),
      pw.Text('Overall Level: $totalLevel (${totalAvg.toStringAsFixed(2)}/3.0)'),
      if (_selectedCategory != null) pw.Text('Category: $_selectedCategory'),
      if (_selectedTemplate != null) pw.Text('Template: ${_selectedTemplate?['name']}'),
      pw.SizedBox(height: 14),
      pw.Row(
        children: [
          _pdfKpi('First Score', '${_num(_trendSummary?['first_score']).toStringAsFixed(2)}/3.0', PdfColor.fromInt(0xFF2563EB)),
          pw.SizedBox(width: 10),
          _pdfKpi('Latest Score', '${_num(_trendSummary?['latest_score']).toStringAsFixed(2)}/3.0', PdfColor.fromInt(0xFF16A34A)),
          pw.SizedBox(width: 10),
          _pdfKpi('Status', status, _pdfStatusColor(status)),
        ],
      ),
      pw.SizedBox(height: 18),
      _pdfSimpleTable(
        headers: ['Date', 'Score', 'Template'],
        rows: _trendData
            .map((e) => [
                  e['date']?.toString() ?? '-',
                  '${_num(e['score']).toStringAsFixed(2)}/3.0',
                  e['template']?.toString() ?? '-',
                ])
            .toList(),
      ),
      if (_trendType == 'overall') ...[
        pw.SizedBox(height: 18),
        _pdfSectionTitle('Category Breakdown'),
        pw.SizedBox(height: 10),
        _pdfSimpleTable(
          headers: ['Category', 'Avg', 'Correct', 'Partial', 'Wrong'],
          rows: _categoryBreakdown.map((c) {
            final avgOn3 = _num(c['avg_on3']);
            return [
              (c['category'] ?? '-').toString(),
              '${avgOn3.toStringAsFixed(2)}/3.0',
              (c['right'] ?? 0).toString(),
              (c['partial'] ?? 0).toString(),
              (c['wrong'] ?? 0).toString(),
            ];
          }).toList(),
        ),
      ],
    ];
  }

  List<pw.Widget> _comparisonPdfContent() {
    return [
      _pdfSectionTitle('Comparison Analysis'),
      pw.SizedBox(height: 10),
      pw.Text('Comparison Type: $_comparisonType'),
      pw.Text('Left: ${_comparisonSummary?['left_label'] ?? _selectedLeftLabel()}'),
      pw.Text('Right: ${_comparisonSummary?['right_label'] ?? _selectedRightLabel()}'),
      pw.SizedBox(height: 14),
      pw.Container(
        padding: const pw.EdgeInsets.all(12),
        decoration: pw.BoxDecoration(
          color: PdfColor.fromInt(0xFFEFF6FF),
          borderRadius: pw.BorderRadius.circular(10),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('Winner: ${_comparisonSummary?['winner'] ?? '-'}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Text('Insight: ${_comparisonSummary?['insight'] ?? _comparisonError ?? '-'}'),
          ],
        ),
      ),
    ];
  }

  pw.Widget _pdfSectionTitle(String title) {
    return pw.Text(
      title,
      style: pw.TextStyle(
        fontSize: 17,
        fontWeight: pw.FontWeight.bold,
        color: PdfColor.fromInt(0xFF0F172A),
      ),
    );
  }

  pw.Widget _pdfKpi(String title, String value, PdfColor color) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.all(12),
        decoration: pw.BoxDecoration(
          color: PdfColors.white,
          border: pw.Border.all(color: PdfColor.fromInt(0xFFE2E8F0)),
          borderRadius: pw.BorderRadius.circular(10),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(title, style: pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
            pw.SizedBox(height: 5),
            pw.Text(value, style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold, color: color)),
          ],
        ),
      ),
    );
  }

  pw.Widget _pdfSimpleTable({required List<String> headers, required List<List<String>> rows}) {
    if (rows.isEmpty) {
      return pw.Container(
        padding: const pw.EdgeInsets.all(12),
        decoration: pw.BoxDecoration(
          color: PdfColor.fromInt(0xFFF8FAFC),
          borderRadius: pw.BorderRadius.circular(8),
        ),
        child: pw.Text('No table data available.'),
      );
    }

    return pw.Table.fromTextArray(
      headers: headers,
      data: rows.take(40).toList(),
      headerDecoration: pw.BoxDecoration(color: PdfColor.fromInt(0xFF1E3A8A)),
      headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 10),
      cellStyle: const pw.TextStyle(fontSize: 9),
      cellAlignment: pw.Alignment.centerLeft,
      border: pw.TableBorder.all(color: PdfColor.fromInt(0xFFE2E8F0), width: 0.5),
      cellPadding: const pw.EdgeInsets.all(6),
    );
  }

  PdfColor _pdfStatusColor(String status) {
    final s = status.toLowerCase();
    if (s.contains('improv')) return PdfColor.fromInt(0xFF16A34A);
    if (s.contains('declin')) return PdfColor.fromInt(0xFFDC2626);
    return PdfColor.fromInt(0xFFF59E0B);
  }

  // ==================== NAVIGATION ====================

  void _goDashboard() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => homeScreen(
          role: widget.role,
          subrole: widget.subrole,
          username: widget.username,
          position: widget.position,
          nationalSupervisorId: widget.nationalSupervisorId,
          supervisorId: widget.supervisorId,
        ),
      ),
    );
  }

  void _goAssessments() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => AssessmentCategoryScreen(
          role: widget.role,
          subrole: widget.subrole,
          username: widget.username,
          position: widget.position,
          nationalSupervisorId: widget.nationalSupervisorId,
          supervisorId: widget.supervisorId,
        ),
      ),
    );
  }

  void _goProfiles() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => ProfilesScreen(
          role: widget.role,
          subrole: widget.subrole,
          username: widget.username,
          position: widget.position,
          nationalSupervisorId: widget.nationalSupervisorId,
          supervisorId: widget.supervisorId,
        ),
      ),
    );
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ==================== BUILD ====================

  @override
  Widget build(BuildContext context) {
    final colors = _lerp3(
      gradientSets[_gNow],
      gradientSets[_gNext],
      _gradientAnimation.value,
    );

    final isNarrow = MediaQuery.of(context).size.width < 1000;

    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFFEFF6FF), Color(0xFFF8FAFC), Colors.white],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.only(
              left: (_isSidebarVisible && !isNarrow) ? 300 : 20,
              right: 20,
              top: 20,
              bottom: 20,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _topBar(colors),
                const SizedBox(height: 20),
                _title(colors),
                const SizedBox(height: 24),
                if (_filterError != null) ...[
                  _errorBox(_filterError!),
                  const SizedBox(height: 16),
                ],
                _tabs(colors),
                const SizedBox(height: 20),
                Expanded(
                  child: _loadingFilters
                      ? const Center(child: CircularProgressIndicator())
                      : IndexedStack(
                          index: _selectedTab,
                          children: [
                            _buildOverviewTab(),
                            _buildIndividualTrendsTab(),
                            _buildComparisonTab(),
                          ],
                        ),
                ),
              ],
            ),
          ),
          if (_isSidebarVisible && !isNarrow)
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: _Sidebar(
                colors: colors,
                username: widget.username,
                role: widget.role,
                onDashboard: _goDashboard,
                onAssessments: _goAssessments,
                onProfiles: _goProfiles,
                onReports: () => setState(() => _isSidebarVisible = false),
              ),
            ),
          if (_isSidebarVisible && isNarrow)
            Positioned.fill(
              child: GestureDetector(
                onTap: () => setState(() => _isSidebarVisible = false),
                child: Container(
                  color: Colors.black.withOpacity(0.3),
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                    width: 280,
                    child: _Sidebar(
                      colors: colors,
                      username: widget.username,
                      role: widget.role,
                      onDashboard: _goDashboard,
                      onAssessments: _goAssessments,
                      onProfiles: _goProfiles,
                      onReports: () => setState(() => _isSidebarVisible = false),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _topBar(List<Color> colors) {
    return Row(
      children: [
        _AnimatedChipButton(
          colors: colors,
          icon: _isSidebarVisible ? Icons.close : Icons.menu,
          onTap: () => setState(() => _isSidebarVisible = !_isSidebarVisible),
        ),
        const SizedBox(width: 20),
        Icon(Icons.analytics_outlined, color: colors[0], size: 20),
        const SizedBox(width: 8),
        Text('Reports', style: TextStyle(color: colors[0], fontSize: 16)),
        const Spacer(),
        _GradientActionBtn(
          colors: [colors[1], colors[2]],
          icon: Icons.picture_as_pdf,
          label: 'Export PDF',
          onTap: _exportToPDF,
        ),
        const SizedBox(width: 8),
        _GradientActionBtn(
          colors: [colors[1], colors[2]],
          icon: Icons.refresh,
          label: 'Refresh',
          onTap: () {
            _loadFilterOptions();
            _loadOverviewData();
            if (_selectedTab == 1 && _selectedEmployee != null) {
              _loadPersonTrend();
              _loadPersonCategoryBreakdown();
            }
            if (_selectedTab == 2) _loadComparisonTrend();
          },
        ),
      ],
    );
  }

  Widget _title(List<Color> colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ShaderMask(
          shaderCallback: (bounds) => LinearGradient(
            colors: colors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ).createShader(bounds),
          child: const Text(
            'Analytics & Reports',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              letterSpacing: 0.5,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Track performance trends, category progress, and team comparisons.',
          style: TextStyle(fontSize: 14, color: Colors.grey[600]),
        ),
      ],
    );
  }

  Widget _tabs(List<Color> colors) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.92),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: colors[0].withOpacity(0.1),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          _buildTab('Overview', 0, Icons.dashboard_outlined, colors),
          _buildTab('Individual Trends', 1, Icons.trending_up, colors),
          _buildTab('Comparison', 2, Icons.compare_arrows, colors),
        ],
      ),
    );
  }

  Widget _buildTab(String label, int index, IconData icon, List<Color> colors) {
    final active = _selectedTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedTab = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            gradient: active ? LinearGradient(colors: colors) : null,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: active ? Colors.white : _muted, size: 18),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: active ? Colors.white : _muted,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==================== OVERVIEW TAB ====================

  Widget _buildOverviewTab() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionCard(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final narrow = constraints.maxWidth < 700;
                final children = [
                  Expanded(
                    child: _labeledControl(
                      label: 'Date Range',
                      child: _buildDropdown<String>(
                        value: _overviewRange,
                        items: const [
                          'Last 7 Days',
                          'Last 30 Days',
                          'Last 90 Days',
                          'Last 180 Days',
                          'Last 12 Months',
                          'All Time',
                        ],
                        hint: 'Select range',
                        displayText: (r) => r,
                        icon: Icons.calendar_month_rounded,
                        onChanged: (val) {
                          if (val == null) return;
                          setState(() => _overviewRange = val);
                          _loadOverviewData();
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 14, height: 14),
                  Expanded(
                    child: _labeledControl(
                      label: _isAdmin ? 'Business Scope' : 'Scope',
                      child: _buildDropdown<String>(
                        value: _overviewScopeItems.contains(_overviewScope)
                            ? _overviewScope
                            : _overviewScopeItems.first,
                        items: _overviewScopeItems,
                        hint: 'Select scope',
                        displayText: (s) => s == 'ALL' ? 'ALL ROLES' : s,
                        icon: Icons.account_tree_rounded,
                        onChanged: _isAdmin
                            ? (val) {
                                if (val == null) return;
                                setState(() => _overviewScope = val);
                                _loadOverviewData();
                              }
                            : null,
                      ),
                    ),
                  ),
                ];

                if (narrow) {
                  return Column(
                    children: [children[0], children[1], children[2]],
                  );
                }
                return Row(children: children);
              },
            ),
          ),
          const SizedBox(height: 16),
          if (_loadingOverview)
            const Center(child: CircularProgressIndicator())
          else if (_overviewError != null)
            _errorBox(_overviewError!)
          else if (_overviewData == null)
            _emptyState('No overview data available.', Icons.bar_chart)
          else ...[
            _overviewKpis(),
            const SizedBox(height: 16),
            _overviewTrendAndBreakdown(),
          ],
        ],
      ),
    );
  }

  Widget _labeledControl({required String label, required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w700, color: _text)),
        const SizedBox(height: 8),
        child,
      ],
    );
  }

  Widget _overviewKpis() {
    final totals = _overviewData?['totals'] as Map?;
    final assessments = totals?['assessments'] ?? 0;
    final avg = _num(totals?['avg_on3']);
    final byRole = _asMapList(_overviewData?['by_role']);
    final bySecondary = _asMapList(_overviewData?['by_secondary']);
    final trend = _asMapList(_overviewData?['trend']);

    final bestSource = _isAdmin && _overviewScope == 'ALL' ? byRole : bySecondary;

    String bestName = '-';

    if (bestSource.isNotEmpty) {
      final bestRow = bestSource.reduce(
        (a, b) => _num(a['avg_on3']) >= _num(b['avg_on3']) ? a : b,
      );

      bestName = (bestRow['role'] ?? bestRow['name'] ?? '-').toString();
    }

    final bestTitle = _isAdmin && _overviewScope == 'ALL'
        ? 'Best Role'
        : 'Best Segment';

    final trendStatus = _trendStatusFromPoints(trend, scoreKey: 'avg_on3');

    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 900;
        final cards = [
          _buildKPICard('Total Assessments', assessments.toString(), Icons.description_outlined, _primary),
          _buildKPICard('Average Score', '${avg.toStringAsFixed(2)}/3.0', Icons.star_rounded, Colors.orange),
          _buildKPICard(bestTitle, bestName, Icons.workspace_premium_outlined, _success),
          _buildKPICard('Trend Status', trendStatus, Icons.trending_up, _statusColor(trendStatus)),
        ];

        if (narrow) {
          return Column(
            children: cards.map((c) => Padding(padding: const EdgeInsets.only(bottom: 12), child: c)).toList(),
          );
        }

        return Row(
          children: cards
              .map((c) => Expanded(child: Padding(padding: const EdgeInsets.only(right: 12), child: c)))
              .toList(),
        );
      },
    );
  }

  Widget _overviewTrendAndBreakdown() {
    final trend = _asMapList(_overviewData?['trend']);
    final byRole = _asMapList(_overviewData?['by_role']);
    final bySecondary = _asMapList(_overviewData?['by_secondary']);

    final breakdownTitle = _isAdmin && _overviewScope == 'ALL'
        ? 'Performance by Role and Segment'
        : 'Performance by Segment';

    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 1000;
        final left = _sectionCard(
          title: 'Performance Trend',
          subtitle: 'Average score over the selected period',
          child: trend.isEmpty
              ? _emptyState('No trend data for this period.', Icons.show_chart)
              : _lineChart(
                  points: trend,
                  lines: [
                    _TrendLineConfig(
                      label: 'Average Score',
                      color: _primary,
                      scoreKey: 'avg_on3',
                    ),
                  ],
                ),
        );
        final right = _sectionCard(
          title: 'Breakdown',
          subtitle: breakdownTitle,
          child: Column(
            children: [
              if (_isAdmin && _overviewScope == 'ALL' && byRole.isNotEmpty)
                _miniBreakdown('By Role', byRole, 'role', 'avg_on3'),
              if (_isAdmin && _overviewScope == 'ALL' && byRole.isNotEmpty && bySecondary.isNotEmpty)
                const SizedBox(height: 16),
              if (bySecondary.isNotEmpty) _miniBreakdown('By Segment', bySecondary, 'name', 'avg_on3'),
              if (byRole.isEmpty && bySecondary.isEmpty) _emptyState('No breakdown data.', Icons.pie_chart_outline),
            ],
          ),
        );

        if (narrow) return Column(children: [left, const SizedBox(height: 16), right]);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 3, child: left),
            const SizedBox(width: 16),
            Expanded(flex: 2, child: right),
          ],
        );
      },
    );
  }

  Widget _buildKPICard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.11),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: _text),
                ),
                const SizedBox(height: 4),
                Text(
                  title,
                  style: const TextStyle(color: _muted, fontSize: 13, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniBreakdown(String title, List<Map<String, dynamic>> rows, String labelKey, String scoreKey) {
    final sorted = [...rows]..sort((a, b) => _num(b[scoreKey]).compareTo(_num(a[scoreKey])));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w800, color: _text)),
        const SizedBox(height: 10),
        ...sorted.take(8).map((r) {
          final score = _num(r[scoreKey]);
          final pct = (score / 3).clamp(0.0, 1.0);
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        (r[labelKey] ?? '-').toString(),
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: _text, fontWeight: FontWeight.w600),
                      ),
                    ),
                    Text('${score.toStringAsFixed(2)}/3', style: const TextStyle(color: _muted, fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: pct,
                    minHeight: 7,
                    backgroundColor: const Color(0xFFE5E7EB),
                    valueColor: AlwaysStoppedAnimation<Color>(_scoreColor(score)),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  // ==================== INDIVIDUAL TRENDS TAB ====================

  Widget _buildIndividualTrendsTab() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionCard(
            title: 'Individual Trend Analysis',
            subtitle: 'Select one employee and choose overall, category, or template trend.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Employee', style: TextStyle(fontWeight: FontWeight.w700, color: _text)),
                const SizedBox(height: 10),
                _buildAutocompleteSearch(
                  controller: _employeeSearchCtrl,
                  suggestions: _employeeSuggestions,
                  isSearching: _searchingEmployees,
                  hint: 'Type to search employees...',
                  onChanged: _searchEmployees,
                  onSelected: (employee) async {
                    final id = _asInt(employee['id']);

                    setState(() {
                      _selectedEmployee = employee;
                      _employeeSearchCtrl.text = _entityLabel(employee);
                      _employeeSuggestions = [];

                      // Clear old selected filters/data from the previous employee
                      _selectedCategory = null;
                      _selectedTemplate = null;
                      _personCategories = [];
                      _personTemplates = [];
                      _categoryBreakdown = [];

                      _trendData = [];
                      _trendSummary = null;
                      _trendError = null;
                    });

                    if (id > 0) {
                      await _loadPersonFilterOptions(id);
                      await _loadPersonCategoryBreakdown();

                      // Only auto-load trend when the selected mode is Overall.
                      // For category/template, user must choose a category/template first.
                      if (_trendType == 'overall') {
                        await _loadPersonTrend();
                      }
                    } else {
                      _toast('Invalid employee selected. Missing profile id.');
                    }
                  },
                ),
                const SizedBox(height: 18),
                const Text('Trend Type', style: TextStyle(fontWeight: FontWeight.w700, color: _text)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _choiceChip('Overall', 'overall', _trendType, (v) {
                      setState(() {
                        _trendType = v;
                        _selectedCategory = null;
                        _selectedTemplate = null;
                        _trendData = [];
                        _trendSummary = null;
                        _trendError = null;
                      });
                      if (_selectedEmployee != null) _loadPersonTrend();
                    }),
                    _choiceChip('Selected Category', 'category', _trendType, (v) {
                      setState(() {
                        _trendType = v;
                        _selectedTemplate = null;
                        _trendData = [];
                        _trendSummary = null;
                        _trendError = null;
                      });
                    }),
                    _choiceChip('Selected Template', 'template', _trendType, (v) {
                      setState(() {
                        _trendType = v;
                        _selectedCategory = null;
                        _trendData = [];
                        _trendSummary = null;
                        _trendError = null;
                      });
                    }),
                  ],
                ),
                if (_loadingPersonFilters) ...[
                  const SizedBox(height: 16),
                  const LinearProgressIndicator(minHeight: 3),
                ],
                if (_trendType == 'category') ...[
                  const SizedBox(height: 18),
                  const Text('Category', style: TextStyle(fontWeight: FontWeight.w700, color: _text)),
                  const SizedBox(height: 10),
                  _personCategories.isEmpty
                      ? _smallMutedText('Select an employee with answered categories first.')
                      : _buildDropdown<String>(
                          value: _selectedCategory,
                          items: _personCategories,
                          hint: 'Choose an answered category...',
                          displayText: (cat) => cat,
                          icon: Icons.category_rounded,
                          onChanged: (val) {
                            setState(() => _selectedCategory = val);
                            if (val != null && _selectedEmployee != null) _loadPersonTrend();
                          },
                        ),
                ],
                if (_trendType == 'template') ...[
                  const SizedBox(height: 18),
                  const Text('Template', style: TextStyle(fontWeight: FontWeight.w700, color: _text)),
                  const SizedBox(height: 10),
                  _personTemplates.isEmpty
                      ? _smallMutedText('Select an employee with completed template history first.')
                      : _buildDropdown<Map<String, dynamic>>(
                          value: _selectedTemplate,
                          items: _personTemplates,
                          hint: 'Choose an answered template...',
                          displayText: (t) => (t['name'] ?? '').toString(),
                          icon: Icons.article_rounded,
                          onChanged: (val) {
                            setState(() => _selectedTemplate = val);
                            if (val != null && _selectedEmployee != null) _loadPersonTrend();
                          },
                        ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (_trendError != null) ...[
            _errorBox(_trendError!),
            const SizedBox(height: 16),
          ],
          if (_loadingTrend)
            const Center(child: CircularProgressIndicator())
          else if (_trendData.isNotEmpty)
            _trendResultCard()
          else if (_selectedEmployee != null)
            _emptyState('No assessment data available for the selected trend.', Icons.info_outline),
        ],
      ),
    );
  }

  Widget _smallMutedText(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
      ),
      child: Text(text, style: const TextStyle(color: _muted)),
    );
  }

  Widget _trendResultCard() {
    final title = _trendType == 'overall'
        ? 'Overall Performance Trend'
        : _trendType == 'category'
            ? 'Category Trend: $_selectedCategory'
            : 'Template Trend: ${_selectedTemplate?['name'] ?? '-'}';

    return _sectionCard(
      title: title,
      subtitle: _selectedEmployee == null ? null : _entityLabel(_selectedEmployee!),
      child: Column(
        children: [
          if (_trendSummary != null) ...[
            _summaryCards(_trendSummary!),
            const SizedBox(height: 22),
          ],
          _lineChart(
            points: _trendData,
            lines: [
              _TrendLineConfig(label: 'Score', color: _primary, scoreKey: 'score'),
            ],
          ),
          if (_trendType == 'overall') ...[
            const SizedBox(height: 24),
            _personPerformanceLevelBanner(),
            const SizedBox(height: 16),
            _buildCategoryBreakdownCard(),
          ],
        ],
      ),
    );
  }

  Widget _summaryCards(Map<String, dynamic> summary) {
    final first = _num(summary['first_score']);
    final latest = _num(summary['latest_score']);
    final change = _num(summary['change']);
    final status = (summary['status'] ?? 'Stable').toString();

    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 850;
        final cards = [
          _smallStat('First Score', '${first.toStringAsFixed(2)}/3.0', Colors.blue),
          _smallStat('Latest Score', '${latest.toStringAsFixed(2)}/3.0', _success),
          _smallStat('Change', '${change >= 0 ? '+' : ''}${change.toStringAsFixed(2)}', change >= 0 ? _success : _danger),
          _smallStat('Status', status, _statusColor(status)),
        ];

        if (narrow) return Wrap(spacing: 10, runSpacing: 10, children: cards);
        return Row(
          children: cards
              .map((c) => Expanded(child: Padding(padding: const EdgeInsets.only(right: 10), child: c)))
              .toList(),
        );
      },
    );
  }

  Widget _smallStat(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.09),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: _muted, fontWeight: FontWeight.w600)),
          const SizedBox(height: 5),
          Text(value, style: TextStyle(fontSize: 18, color: color, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  Widget _personPerformanceLevelBanner() {
    final avg = _averageTrendScore(_trendData);
    final level = _levelFromScore(avg);
    final color = _levelColor(level);
    final percentage = ((avg / 3.0) * 100).clamp(0, 100).toStringAsFixed(1);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withOpacity(0.12), Colors.white],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(Icons.workspace_premium_rounded, color: color, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Overall Performance Level: $level',
                  style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 17),
                ),
                const SizedBox(height: 4),
                Text(
                  'Based on this person’s total average score: ${avg.toStringAsFixed(2)}/3.0 ($percentage%).',
                  style: const TextStyle(color: _muted, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryBreakdownCard() {
    if (_loadingCategoryBreakdown) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_categoryBreakdownError != null) {
      return _errorBox(_categoryBreakdownError!);
    }

    if (_categoryBreakdown.isEmpty) {
      return _emptyState('No category breakdown available for this employee.', Icons.category_outlined);
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Category Performance Breakdown',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: _text),
          ),
          const SizedBox(height: 6),
          const Text(
            'Correct, partial, and wrong answers by category. The level above is based on the person’s total average.',
            style: TextStyle(color: _muted, fontSize: 13),
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 850;

              if (isNarrow) {
                return Column(
                  children: _categoryBreakdown
                      .map((cat) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _categoryBreakdownMobileCard(cat),
                          ))
                      .toList(),
                );
              }

              return Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E3A8A),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Row(
                      children: [
                        Expanded(flex: 3, child: Text('Category', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800))),
                        Expanded(child: Text('Avg', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800))),
                        Expanded(child: Text('Correct', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800))),
                        Expanded(child: Text('Partial', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800))),
                        Expanded(child: Text('Wrong', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800))),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  ..._categoryBreakdown.map((cat) => _categoryBreakdownRow(cat)),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _categoryBreakdownRow(Map<String, dynamic> cat) {
    final name = (cat['category'] ?? '-').toString();
    final avg = _num(cat['avg_on3']);
    final right = cat['right']?.toString() ?? '0';
    final partial = cat['partial']?.toString() ?? '0';
    final wrong = cat['wrong']?.toString() ?? '0';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              name,
              style: const TextStyle(fontWeight: FontWeight.w700, color: _text),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(child: Text('${avg.toStringAsFixed(2)}/3')),
          Expanded(child: Text(right, style: const TextStyle(color: _success, fontWeight: FontWeight.w700))),
          Expanded(child: Text(partial, style: const TextStyle(color: _warning, fontWeight: FontWeight.w700))),
          Expanded(child: Text(wrong, style: const TextStyle(color: _danger, fontWeight: FontWeight.w700))),
        ],
      ),
    );
  }

  Widget _categoryBreakdownMobileCard(Map<String, dynamic> cat) {
    final name = (cat['category'] ?? '-').toString();
    final avg = _num(cat['avg_on3']);
    final right = cat['right']?.toString() ?? '0';
    final partial = cat['partial']?.toString() ?? '0';
    final wrong = cat['wrong']?.toString() ?? '0';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name, style: const TextStyle(fontWeight: FontWeight.w800, color: _text)),
          const SizedBox(height: 10),
          Text('Average: ${avg.toStringAsFixed(2)}/3.0'),
          const SizedBox(height: 8),
          Row(
            children: [
              _miniCount('Correct', right, _success),
              const SizedBox(width: 8),
              _miniCount('Partial', partial, _warning),
              const SizedBox(width: 8),
              _miniCount('Wrong', wrong, _danger),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniCount(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(value, style: TextStyle(color: color, fontWeight: FontWeight.w900)),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(color: _muted, fontSize: 11)),
          ],
        ),
      ),
    );
  }

  // ==================== COMPARISON TAB ====================

  Widget _buildComparisonTab() {
    final availableTypes = _availableComparisonTypes();

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionCard(
            title: 'Comparison Analysis',
            subtitle: 'Compare people, supervisor teams, subroles, or roles based on your access level.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Comparison Type', style: TextStyle(fontWeight: FontWeight.w700, color: _text)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: availableTypes.entries
                      .map((e) => _choiceChip(e.value, e.key, _comparisonType, (v) {
                            setState(() {
                              _comparisonType = v;
                              _resetComparisonSelection();
                            });
                          }))
                      .toList(),
                ),
                const SizedBox(height: 20),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final narrow = constraints.maxWidth < 800;
                    final left = _buildComparisonSide('Left Side', true);
                    final right = _buildComparisonSide('Right Side', false);
                    return narrow
                        ? Column(children: [left, const SizedBox(height: 14), right])
                        : Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: left),
                              const SizedBox(width: 16),
                              Expanded(child: right),
                            ],
                          );
                  },
                ),
                const SizedBox(height: 20),
                Align(
                  alignment: Alignment.center,
                  child: ElevatedButton.icon(
                    onPressed: _loadComparisonTrend,
                    icon: const Icon(Icons.compare_arrows),
                    label: const Text('Compare'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 34, vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (_comparisonError != null) ...[
            _errorBox(_comparisonError!),
            const SizedBox(height: 16),
          ],
          if (_loadingComparison)
            const Center(child: CircularProgressIndicator())
          else if (_leftTrend.isNotEmpty && _rightTrend.isNotEmpty)
            _comparisonResultCard()
          else
            _emptyState('Choose two sides and click Compare to generate the trend.', Icons.compare_arrows),
        ],
      ),
    );
  }

  Map<String, String> _availableComparisonTypes() {
    final map = <String, String>{'person': 'Person vs Person'};

    if (!_isSupervisor && _teams.length >= 2) {
      map['team'] = 'Team vs Team';
    }

    if ((_isAdmin || _isChannelManager) && _subroles.length >= 2) {
      map['subrole'] = 'Subrole vs Subrole';
    }

    if (_isAdmin) {
      map['role'] = 'Role vs Role';
    }

    return map;
  }

  void _resetComparisonSelection() {
    _leftEntity = null;
    _rightEntity = null;
    _leftSubrole = null;
    _rightSubrole = null;
    _leftRole = null;
    _rightRole = null;
    _leftTrend = [];
    _rightTrend = [];
    _comparisonSummary = null;
    _comparisonError = null;
    _leftSearchCtrl.clear();
    _rightSearchCtrl.clear();
    _leftSuggestions = [];
    _rightSuggestions = [];
  }

  Widget _buildComparisonSide(String title, bool isLeft) {
    final color = isLeft ? Colors.blue : Colors.orange;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: color)),
          const SizedBox(height: 14),
          if (_comparisonType == 'person' || _comparisonType == 'team')
            _buildAutocompleteSearch(
              controller: isLeft ? _leftSearchCtrl : _rightSearchCtrl,
              suggestions: isLeft ? _leftSuggestions : _rightSuggestions,
              isSearching: isLeft ? _searchingLeft : _searchingRight,
              hint: _comparisonType == 'team' ? 'Type supervisor/team name...' : 'Type employee name...',
              onChanged: isLeft ? _searchLeft : _searchRight,
              onSelected: (val) {
                setState(() {
                  if (isLeft) {
                    _leftEntity = val;
                    _leftSearchCtrl.text = _comparisonType == 'team' ? '${_entityLabel(val)} Team' : _entityLabel(val);
                    _leftSuggestions = [];
                  } else {
                    _rightEntity = val;
                    _rightSearchCtrl.text = _comparisonType == 'team' ? '${_entityLabel(val)} Team' : _entityLabel(val);
                    _rightSuggestions = [];
                  }
                });
              },
            ),
          if (_comparisonType == 'subrole')
            _buildDropdown<String>(
              value: isLeft ? _leftSubrole : _rightSubrole,
              items: _subroles,
              hint: 'Select segment...',
              displayText: (s) => s,
              icon: Icons.account_tree_rounded,
              onChanged: (val) {
                setState(() {
                  if (isLeft) {
                    _leftSubrole = val;
                  } else {
                    _rightSubrole = val;
                  }
                });
              },
            ),
          if (_comparisonType == 'role')
            _buildDropdown<String>(
              value: isLeft ? _leftRole : _rightRole,
              items: _roles.isEmpty ? const ['SFP', 'CC', 'CE'] : _roles,
              hint: 'Select role...',
              displayText: (r) => r,
              icon: Icons.groups_rounded,
              onChanged: (val) {
                setState(() {
                  if (isLeft) {
                    _leftRole = val;
                  } else {
                    _rightRole = val;
                  }
                });
              },
            ),
        ],
      ),
    );
  }

  Widget _comparisonResultCard() {
    final leftLabel = _comparisonSummary?['left_label']?.toString() ?? _selectedLeftLabel();
    final rightLabel = _comparisonSummary?['right_label']?.toString() ?? _selectedRightLabel();

    return _sectionCard(
      title: 'Comparison Result',
      subtitle: '$leftLabel vs $rightLabel',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_comparisonSummary != null) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _primarySoft,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _primary.withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.insights, color: _primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Winner: ${_comparisonSummary?['winner'] ?? 'Tie'}',
                          style: const TextStyle(color: _text, fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 4),
                        Text(_comparisonSummary?['insight']?.toString() ?? '', style: const TextStyle(color: _muted)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
          ],
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _legendItem(leftLabel, Colors.blue),
              const SizedBox(width: 24),
              _legendItem(rightLabel, Colors.orange),
            ],
          ),
          const SizedBox(height: 14),
          _lineChart(
            points: _mergedComparisonPoints(),
            lines: [
              _TrendLineConfig(label: leftLabel, color: Colors.blue, scoreKey: 'left_score'),
              _TrendLineConfig(label: rightLabel, color: Colors.orange, scoreKey: 'right_score'),
            ],
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _mergedComparisonPoints() {
    final maxLen = _leftTrend.length > _rightTrend.length ? _leftTrend.length : _rightTrend.length;
    final out = <Map<String, dynamic>>[];

    for (var i = 0; i < maxLen; i++) {
      out.add({
        'date': i < _leftTrend.length ? _leftTrend[i]['date'] : (i < _rightTrend.length ? _rightTrend[i]['date'] : ''),
        if (i < _leftTrend.length) 'left_score': _leftTrend[i]['score'],
        if (i < _rightTrend.length) 'right_score': _rightTrend[i]['score'],
      });
    }

    return out;
  }

  String _selectedLeftLabel() {
    if (_comparisonType == 'subrole') return _leftSubrole ?? 'Left';
    if (_comparisonType == 'role') return _leftRole ?? 'Left';
    if (_comparisonType == 'team') return _leftEntity == null ? 'Left Team' : '${_entityLabel(_leftEntity!)} Team';
    return _leftEntity == null ? 'Left' : _entityLabel(_leftEntity!);
  }

  String _selectedRightLabel() {
    if (_comparisonType == 'subrole') return _rightSubrole ?? 'Right';
    if (_comparisonType == 'role') return _rightRole ?? 'Right';
    if (_comparisonType == 'team') return _rightEntity == null ? 'Right Team' : '${_entityLabel(_rightEntity!)} Team';
    return _rightEntity == null ? 'Right' : _entityLabel(_rightEntity!);
  }

  // ==================== SHARED WIDGETS ====================

  Widget _sectionCard({String? title, String? subtitle, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.96),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: _text)),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(subtitle, style: const TextStyle(color: _muted, fontSize: 13)),
            ],
            const SizedBox(height: 18),
          ],
          child,
        ],
      ),
    );
  }

  Widget _errorBox(String msg) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: Colors.red.shade700),
          const SizedBox(width: 10),
          Expanded(child: Text(msg, style: TextStyle(color: Colors.red.shade700))),
        ],
      ),
    );
  }

  Widget _emptyState(String message, IconData icon) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 46, color: Colors.grey[300]),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center, style: const TextStyle(color: _muted)),
        ],
      ),
    );
  }

  Widget _choiceChip(String label, String value, String group, ValueChanged<String> onTap) {
    final selected = group == value;
    return GestureDetector(
      onTap: () => onTap(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? _primary : Colors.grey[100],
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: selected ? _primary : _border),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : _text,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildAutocompleteSearch({
    required TextEditingController controller,
    required List<Map<String, dynamic>> suggestions,
    required bool isSearching,
    required String hint,
    required ValueChanged<String> onChanged,
    required ValueChanged<Map<String, dynamic>> onSelected,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
      ),
      child: Column(
        children: [
          TextField(
            controller: controller,
            decoration: InputDecoration(
              border: InputBorder.none,
              hintText: hint,
              prefixIcon: Icon(isSearching ? Icons.hourglass_empty : Icons.search, color: _muted),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
            onChanged: onChanged,
          ),
          if (suggestions.isNotEmpty)
            Container(
              constraints: const BoxConstraints(maxHeight: 260),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: _border))),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: suggestions.length,
                separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
                itemBuilder: (context, index) {
                  final item = suggestions[index];
                  final name = _entityLabel(item);
                  final position = (item['position'] ?? '').toString();
                  final role = (item['role'] ?? item['category'] ?? '').toString();
                  final label = _comparisonType == 'team' && (name.toLowerCase().contains('team') == false)
                      ? '$name Team'
                      : name;

                  return ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      backgroundColor: _primarySoft,
                      child: Text(
                        name.isNotEmpty ? name[0].toUpperCase() : '?',
                        style: const TextStyle(color: _primary, fontWeight: FontWeight.w800),
                      ),
                    ),
                    title: Text(label, style: const TextStyle(fontWeight: FontWeight.w700, color: _text)),
                    subtitle: Text(
                      [position, role].where((e) => e.isNotEmpty).join(' • '),
                      style: const TextStyle(fontSize: 12, color: _muted),
                    ),
                    onTap: () => onSelected(item),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDropdown<T>({
    required T? value,
    required List<T> items,
    required String hint,
    required String Function(T) displayText,
    required ValueChanged<T?>? onChanged,
    IconData icon = Icons.keyboard_arrow_down_rounded,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          borderRadius: BorderRadius.circular(14),
          dropdownColor: Colors.white,
          icon: Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Icon(Icons.keyboard_arrow_down_rounded, color: _muted, size: 22),
          ),
          hint: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              hint,
              style: const TextStyle(color: _muted, fontSize: 14, fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          selectedItemBuilder: (context) {
            return items.map((item) {
              return Row(
                children: [
                  Container(
                    margin: const EdgeInsets.only(left: 14, right: 10),
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: _primarySoft,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, size: 17, color: _primary),
                  ),
                  Expanded(
                    child: Text(
                      displayText(item),
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: _text, fontSize: 14, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              );
            }).toList();
          },
          items: items.map((item) {
            return DropdownMenuItem<T>(
              value: item,
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: _primarySoft,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, size: 17, color: _primary),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      displayText(item),
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: _text, fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _lineChart({required List<Map<String, dynamic>> points, required List<_TrendLineConfig> lines}) {
    if (points.isEmpty) return _emptyState('No chart data available.', Icons.show_chart);

    final lineBars = <LineChartBarData>[];

    for (final line in lines) {
      final spots = <FlSpot>[];
      for (var i = 0; i < points.length; i++) {
        if (points[i][line.scoreKey] == null) continue;
        spots.add(FlSpot(i.toDouble(), _num(points[i][line.scoreKey])));
      }
      if (spots.isEmpty) continue;

      lineBars.add(
        LineChartBarData(
          spots: spots,
          isCurved: true,
          color: line.color,
          barWidth: 3,
          isStrokeCapRound: true,
          dotData: const FlDotData(show: true),
          belowBarData: BarAreaData(show: true, color: line.color.withOpacity(0.08)),
        ),
      );
    }

    if (lineBars.isEmpty) return _emptyState('No valid score values for this chart.', Icons.show_chart);

    return SizedBox(
      height: 320,
      child: LineChart(
        LineChartData(
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: 0.5,
            getDrawingHorizontalLine: (_) => FlLine(color: Colors.grey[200]!, strokeWidth: 1),
          ),
          titlesData: FlTitlesData(
            show: true,
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 42,
                interval: points.length <= 8 ? 1 : (points.length / 6).ceilToDouble(),
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index < 0 || index >= points.length) return const SizedBox();
                  final label = _formatShortDate(points[index]['date']);
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(label, style: const TextStyle(color: _muted, fontSize: 10)),
                  );
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 42,
                interval: 0.5,
                getTitlesWidget: (value, meta) => Text(value.toStringAsFixed(1), style: const TextStyle(color: _muted, fontSize: 12)),
              ),
            ),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: true, border: Border.all(color: Colors.grey[300]!)),
          minX: 0,
          maxX: points.length <= 1 ? 1 : (points.length - 1).toDouble(),
          minY: 0,
          maxY: 3,
          lineBarsData: lineBars,
          lineTouchData: LineTouchData(
            enabled: true,
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (items) {
                return items.map((spot) {
                  final line = lines.length > spot.barIndex ? lines[spot.barIndex] : lines.first;
                  return LineTooltipItem(
                    '${line.label}\n${spot.y.toStringAsFixed(2)}/3.0',
                    const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                  );
                }).toList();
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _legendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 18, height: 4, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4))),
        const SizedBox(width: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 240),
          child: Text(label, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _muted, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }

  // ==================== HELPERS ====================

  List<Map<String, dynamic>> _asMapList(dynamic value) {
    if (value is! List) return [];
    return value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  List<String> _asStringList(dynamic value) {
    if (value is! List) return [];
    final cleaned = value
        .map((e) => e.toString().trim().toUpperCase())
        .where((e) => e.isNotEmpty)
        .where((e) => e.toLowerCase() != 'all')
        .where((e) => e.toLowerCase() != 'n/a')
        .toSet()
        .toList();
    cleaned.sort();
    return cleaned;
  }

  // Preserve exact category names from the database.
  // Do NOT uppercase categories, otherwise category trend matching can fail.
  List<String> _asStringListPreserveCase(dynamic value) {
    if (value is! List) return [];
    final cleaned = value
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .where((e) => e.toLowerCase() != 'all')
        .where((e) => e.toLowerCase() != 'n/a')
        .toSet()
        .toList();
    cleaned.sort();
    return cleaned;
  }

  int _asInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  double _num(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  Color _scoreColor(double score) {
    if (score >= 2.55) return _success;
    if (score >= 2.25) return _primary;
    return _danger;
  }

  double _averageTrendScore(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) return 0.0;
    final values = rows
        .map((e) => _num(e['score'] ?? e['avg_on3']))
        .where((v) => v > 0)
        .toList();

    if (values.isEmpty) return 0.0;
    return values.reduce((a, b) => a + b) / values.length;
  }

  Color _statusColor(String status) {
    final s = status.toLowerCase();
    if (s.contains('improv')) return _success;
    if (s.contains('declin')) return _danger;
    return _warning;
  }

  String _levelFromScore(double avgOn3) {
    final percentage = (avgOn3 / 3.0) * 100;
    if (percentage >= 85) return 'Accelerate';
    if (percentage >= 75) return 'Advanced';
    return 'Inadequate';
  }

  Color _levelColor(String level) {
    final l = level.toLowerCase();
    if (l.contains('accelerate')) return _success;
    if (l.contains('advanced')) return _primary;
    return _danger;
  }

  String _trendStatusFromPoints(List<Map<String, dynamic>> points, {required String scoreKey}) {
    if (points.length < 2) return 'Stable';
    final first = _num(points.first[scoreKey]);
    final last = _num(points.last[scoreKey]);
    final diff = last - first;
    if (diff > 0.05) return 'Improving';
    if (diff < -0.05) return 'Declining';
    return 'Stable';
  }

  String _entityLabel(Map<String, dynamic> e) {
    return (e['full_name'] ?? e['name'] ?? e['label'] ?? '').toString();
  }

  String _formatShortDate(dynamic value) {
    final raw = value?.toString() ?? '';
    if (raw.isEmpty) return '';
    final date = DateTime.tryParse(raw);
    if (date != null) return DateFormat('MM-dd').format(date);
    final parts = raw.split('-');
    if (parts.length >= 3) return '${parts[1]}-${parts[2]}';
    return raw;
  }

  String _extractMessage(String body, String fallback) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        return (decoded['message'] ?? decoded['error'] ?? decoded['detail'] ?? fallback).toString();
      }
    } catch (_) {}
    return fallback;
  }

  (String, String) _resolveRange(String label) {
    final now = DateTime.now().toUtc();
    DateTime from;
    switch (label) {
      case 'Last 7 Days':
        from = now.subtract(const Duration(days: 7));
        break;
      case 'Last 90 Days':
        from = now.subtract(const Duration(days: 90));
        break;
      case 'Last 180 Days':
        from = now.subtract(const Duration(days: 180));
        break;
      case 'Last 12 Months':
        from = now.subtract(const Duration(days: 365));
        break;
      case 'All Time':
        from = DateTime.utc(2000, 1, 1);
        break;
      case 'Last 30 Days':
      default:
        from = now.subtract(const Duration(days: 30));
    }
    return (from.toIso8601String(), now.toIso8601String());
  }

  List<Color> _lerp3(List<Color> a, List<Color> b, double t) => [
        Color.lerp(a[0], b[0], t) ?? a[0],
        Color.lerp(a[1], b[1], t) ?? a[1],
        Color.lerp(a[2], b[2], t) ?? a[2],
      ];
}

class _TrendLineConfig {
  final String label;
  final Color color;
  final String scoreKey;

  const _TrendLineConfig({
    required this.label,
    required this.color,
    required this.scoreKey,
  });
}

// ==================== SMALL WIDGETS ====================

class _AnimatedChipButton extends StatelessWidget {
  final List<Color> colors;
  final IconData icon;
  final VoidCallback onTap;

  const _AnimatedChipButton({
    required this.colors,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: colors),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: colors.first.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: IconButton(onPressed: onTap, icon: Icon(icon, color: Colors.white)),
    );
  }
}

class _GradientActionBtn extends StatelessWidget {
  final List<Color> colors;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _GradientActionBtn({
    required this.colors,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: colors),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: colors.first.withOpacity(0.25), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, color: Colors.white),
        label: Text(label, style: const TextStyle(color: Colors.white)),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  final List<Color> colors;
  final String username;
  final String role;
  final VoidCallback onDashboard;
  final VoidCallback onAssessments;
  final VoidCallback onProfiles;
  final VoidCallback onReports;

  const _Sidebar({
    required this.colors,
    required this.username,
    required this.role,
    required this.onDashboard,
    required this.onAssessments,
    required this.onProfiles,
    required this.onReports,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          width: 280,
          height: MediaQuery.of(context).size.height,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                colors[0].withOpacity(0.88),
                colors[1].withOpacity(0.78),
                colors[2].withOpacity(0.68),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border(right: BorderSide(color: Colors.white.withOpacity(0.2))),
            boxShadow: [BoxShadow(color: colors.first.withOpacity(0.25), blurRadius: 24, offset: const Offset(6, 0))],
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: Colors.white.withOpacity(0.3), width: 2),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.asset('assets/logo.png', width: 110),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  const Text(
                    'PHILIP MORRIS',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 17, letterSpacing: 2.5),
                  ),
                  const SizedBox(height: 6),
                  Text('INTERNATIONAL', style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 13, letterSpacing: 2.0)),
                  const SizedBox(height: 40),
                  _navItem(Icons.dashboard_outlined, 'Dashboard', false, onDashboard),
                  const SizedBox(height: 16),
                  _navItem(Icons.assessment_outlined, 'Assessments', false, onAssessments),
                  const SizedBox(height: 16),
                  _navItem(Icons.people_outlined, 'Profiles', false, onProfiles),
                  const SizedBox(height: 16),
                  _navItem(Icons.analytics_outlined, 'Reports', true, onReports),
                  const Spacer(),
                  _userInfo(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _navItem(IconData icon, String title, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: active ? Colors.white.withOpacity(0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: active ? Border.all(color: Colors.white.withOpacity(0.4)) : null,
        ),
        child: Row(
          children: [
            Icon(icon, color: active ? Colors.white : Colors.white.withOpacity(0.78), size: 22),
            const SizedBox(width: 16),
            Text(
              title,
              style: TextStyle(
                color: active ? Colors.white : Colors.white.withOpacity(0.78),
                fontSize: 16,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _userInfo() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: Colors.white.withOpacity(0.3),
            child: Text(username.isNotEmpty ? username[0].toUpperCase() : 'U', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(username, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13), overflow: TextOverflow.ellipsis),
                Text(role, style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 11), overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

extension on List<Color> {
  List<List<Color>> slices(int size) {
    final out = <List<Color>>[];
    for (var i = 0; i < length; i += size) {
      if (i + size <= length) out.add(sublist(i, i + size));
    }
    return out;
  }
}
