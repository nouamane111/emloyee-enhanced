import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'create_template.dart';
import 'home.dart';
import 'assessment_category.dart';
import 'Profiles.dart';
import 'initiateassessment.dart';

class AssessmentListScreen extends StatefulWidget {
  final String role;
  final String subrole;
  final String username;
  final String position;
 
  final String? nationalSupervisorId;
  final String? supervisorId;
  final dynamic selectedCategory;
  final String? selectedSubCategory;

  const AssessmentListScreen({
    super.key,
    required this.role,
    required this.subrole,
    required this.username,
    required this.position,
    
    this.nationalSupervisorId,
    this.supervisorId,
    required this.selectedCategory,
    this.selectedSubCategory,
  });

  @override
  State<AssessmentListScreen> createState() => _AssessmentListScreenState();
}

class _AssessmentListScreenState extends State<AssessmentListScreen>
    with TickerProviderStateMixin {
  // Data
  List<Map<String, dynamic>> templates = [];
  List<Map<String, dynamic>> assessmentHistory = [];

  // --------- NEW: cache dialog results so we don’t refetch unnecessarily ----------
  final Map<dynamic, Map<String, dynamic>> _resultCache = {}; // <-- ADDED

  // UI state
  bool _isSidebarVisible = false;
  bool _showTemplates = true;
  String searchQuery = '';
  String _selectedPositionFilter = 'All';
  String _sortBy = 'Date';
  bool _sortAscending = false;

  // Loading guards & memo
  bool _loadingTemplates = false;
  bool _loadingHistory = false;
  String? _cachedTemplateKey;
  String? _cachedHistoryKey;

  // Debounce
  Timer? _searchDebounce;

  // Minor gradient animations (kept, but only applied to small widgets)
  late AnimationController _gradientController;
  late Animation<double> _gradientAnimation;
  final List<List<Color>> gradientSets = const [
    Color(0xFF1e3a8a), Color(0xFF3730a3), Color(0xFF4338ca),
    Color(0xFF0f172a), Color(0xFF1e293b), Color(0xFF334155),
    Color(0xFF1a202c), Color(0xFF2d3748), Color(0xFF4a5568),
    Color(0xFF2563eb), Color(0xFF3b82f6), Color(0xFF60a5fa),
  ].slices(3); // helper extension below

  int currentGradientIndex = 0;
  int nextGradientIndex = 1;

  @override
  void initState() {
    super.initState();
    _initAnimations();
    // Initial fetches only once here:
    fetchTemplates();
    fetchAssessmentHistory(); // now hydrates rows with real scores
  }

  void _initAnimations() {
    _gradientController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          currentGradientIndex = nextGradientIndex;
          nextGradientIndex = (nextGradientIndex + 1) % gradientSets.length;
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
    _searchDebounce?.cancel();
    _gradientController.dispose();
    super.dispose();
  }

  // ---------------- Fetchers (guarded + memoized) ----------------

  Future<void> fetchTemplates() async {
    final key =
        '${widget.selectedCategory}|${widget.selectedSubCategory}|${widget.position}|${widget.role}';
    if (_cachedTemplateKey == key && templates.isNotEmpty) return;
    if (_loadingTemplates) return;
    _loadingTemplates = true;

    try {
      final resp = await http.post(
        Uri.parse('http://localhost:5000/get_templates'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'role': widget.selectedCategory.toString().toUpperCase(),
          'subrole': widget.selectedSubCategory?.toString().toUpperCase(),
        }),
      );
      if (!mounted) return;
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final List<Map<String, dynamic>> all =
            List<Map<String, dynamic>>.from(data['templates'] ?? []);
        final filtered = _applyEnhancedFiltering(all);
        setState(() {
          templates = filtered;
          _cachedTemplateKey = key;
        });
      }
    } catch (_) {
      // ignore
    } finally {
      _loadingTemplates = false;
    }
  }

  // -------------------- CHANGED: hydrates rows with real score --------------------
  Future<void> fetchAssessmentHistory() async {
    final key =
        '${widget.selectedCategory}|${widget.selectedSubCategory}|${widget.position}|${widget.role}';
    if (_cachedHistoryKey == key && assessmentHistory.isNotEmpty) return;
    if (_loadingHistory) return;
    _loadingHistory = true;

    try {
      final resp = await http.post(
        Uri.parse('http://localhost:5000/get_assessment_history'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({}),
      );
      if (!mounted) return;

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        if (data['status'] == 'success') {
          final List<Map<String, dynamic>> all =
              List<Map<String, dynamic>>.from(data['history'] ?? []);
          final filtered = _applyHistoryFiltering(all);

          // NEW: hydrate each item with real stats from /get_assessment_result
          final hydrated = await _hydrateHistoryWithResults(filtered);

          setState(() {
            assessmentHistory = hydrated;
            _cachedHistoryKey = key;
          });
        } else {
          setState(() => assessmentHistory = []);
        }
      } else {
        setState(() => assessmentHistory = []);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => assessmentHistory = []);
    } finally {
      _loadingHistory = false;
    }
  }

  // ---------------- NEW: call /get_assessment_result per item (cached) ----------------
  Future<List<Map<String, dynamic>>> _hydrateHistoryWithResults(
    List<Map<String, dynamic>> items,
  ) async {
    final futures = items.map((item) async {
      final id = item['id'];
      if (id == null) return item;

      Map<String, dynamic>? result = _resultCache[id];

      if (result == null) {
        try {
          final r = await http.post(
            Uri.parse('http://localhost:5000/get_assessment_result'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'assessment_id': id}),
          );
          if (r.statusCode == 200) {
            final parsed = jsonDecode(r.body);
            if (parsed['status'] == 'success') {
              result = Map<String, dynamic>.from(parsed['assessment'] ?? {});
              _resultCache[id] = result!;
            }
          }
        } catch (_) {
          // ignore, fallback to the raw row
        }
      }

      if (result == null) return item;

      final stats = Map<String, dynamic>.from(result['statistics'] ?? {});
      final double totalScore = (stats['total_score'] ?? 0.0).toDouble();
      final double maxPossible = (stats['max_possible_score'] ?? 0.0).toDouble();
      final double pct = maxPossible > 0 ? (totalScore / maxPossible * 100.0) : 0.0;
      final double scoreOn3 = (pct / 100.0) * 3.0; // keep your UI scale (x/3)

      final dynamic completedAt = result['completed_at'] ?? item['completed_at'];

      return {
        ...item,
        'final_score': scoreOn3,         // used by _fmtScore and _fmtOn3
        'score_percentage': pct,         // optional
        'completed_at': completedAt,     // date coming from result if present
      };
    }).toList();

    return await Future.wait(futures);
  }

  // ---------------- Filters & Helpers ----------------

  // History filter (by your rules)
  List<Map<String, dynamic>> _applyHistoryFiltering(
      List<Map<String, dynamic>> allHistory) {
    final category = widget.selectedCategory.toString().toUpperCase();
    final subcategory =
        widget.selectedSubCategory?.toString().toLowerCase().trim();
    final position = widget.position.toLowerCase();
    final role = widget.role.toUpperCase();
    final isAdmin = position == 'all';

    List<Map<String, dynamic>> filtered = allHistory.where((history) {
      final templateRole =
          (history['template_role'] ?? history['assessee_role'] ?? '')
              .toString()
              .toUpperCase();
      return templateRole == category;
    }).toList();

    if ((category != 'CC' && category != 'CE') &&
        subcategory != null &&
        subcategory.isNotEmpty) {
      filtered = filtered.where((history) {
        final templateSubrole =
            (history['template_subrole'] ?? '').toString().toLowerCase().trim();
        return templateSubrole == subcategory;
      }).toList();
    }

    if (isAdmin) return filtered;

    // CC/CE special
    if (category == 'CC' || category == 'CE') {
      if (role == category) {
        return filtered.where((h) {
          final templatePosition =
              (h['template_position'] ?? '').toString().toLowerCase();
          return templatePosition == position;
        }).toList();
      }
      return [];
    }

    // SFP hierarchy
    filtered = filtered.where((h) {
      final pos = (h['assessee_position'] ?? '').toString().toLowerCase();
      if (position == 'channel manager') {
        return pos.contains('national supervisor') ||
            pos.contains('supervisor') ||
            pos.contains('sales expert');
      } else if (position == 'national supervisor') {
        return pos.contains('supervisor') || pos.contains('sales expert');
      } else if (position == 'supervisor') {
        return pos.contains('sales expert');
      }
      return false;
    }).toList();

    return filtered;
  }

  // Templates filter
  List<Map<String, dynamic>> _applyEnhancedFiltering(
      List<Map<String, dynamic>> allTemplates) {
    final category = widget.selectedCategory.toString().toUpperCase();
    final subcategory =
        widget.selectedSubCategory?.toString().toLowerCase().trim();
    final position = widget.position.toLowerCase();
    final userRole = widget.role.toUpperCase();
    final isAdmin = position == 'all';

    // 1) Category filter (role)
    List<Map<String, dynamic>> catFiltered =
        allTemplates.where((t) => (t['role'] ?? '').toString().toUpperCase() == category).toList();

    // 2) Subrole
    if (subcategory != null && subcategory.isNotEmpty) {
      catFiltered = catFiltered.where((t) {
        final s = (t['subrole'] ?? '').toString().toLowerCase().trim();
        return s == subcategory;
      }).toList();
    }

    // 3) Admin sees all after that
    if (isAdmin) return catFiltered;

    // 4) CE/CC specific
    if (category == 'CE') {
      if (subcategory == 'supervisor') {
        return catFiltered
            .where((t) =>
                (t['subrole'] ?? '').toString().toLowerCase() ==
                'brand representatives')
            .toList();
      } else {
        return catFiltered
            .where((t) =>
                (t['subrole'] ?? '').toString().toLowerCase() ==
                (subcategory ?? ''))
            .toList();
      }
    }
    if (category == 'CC') {
      // Keep same visibility behavior as your original
      return catFiltered;
    }

    // 5) SFP hierarchy by position
    if (position == 'channel manager') {
      return catFiltered
          .where((t) => (t['position'] ?? '').toString().toLowerCase() != 'all')
          .toList();
    } else if (position == 'national supervisor') {
      return catFiltered.where((t) {
        final p = (t['position'] ?? '').toString().toLowerCase();
        return p == 'sales expert' || p == 'supervisor';
      }).toList();
    } else if (position == 'supervisor') {
      return catFiltered
          .where((t) =>
              (t['position'] ?? '').toString().toLowerCase() == 'sales expert')
          .toList();
    }

    return [];
  }

  // Combined filter/sort for list rendering
  List<Map<String, dynamic>> _getFilteredAndSortedData() {
    final current = _showTemplates ? templates : assessmentHistory;

    // Search (debounced in setter below)
    final filtered = current.where((item) {
      final q = searchQuery.toLowerCase();
      return (item['name'] ?? '').toString().toLowerCase().contains(q) ||
          (item['role'] ?? '').toString().toLowerCase().contains(q) ||
          (item['subrole'] ?? '').toString().toLowerCase().contains(q) ||
          (item['position'] ?? '').toString().toLowerCase().contains(q) ||
          (item['created_by'] ?? '').toString().toLowerCase().contains(q) ||
          (item['created_at'] ?? '').toString().toLowerCase().contains(q) ||
          (item['assessee_name'] ?? '')
              .toString()
              .toLowerCase()
              .contains(q) ||
          (item['assessor_name'] ?? '')
              .toString()
              .toLowerCase()
              .contains(q) ||
          (item['template_name'] ?? '')
              .toString()
              .toLowerCase()
              .contains(q);
    }).where((item) {
      // Position filter
      if (_selectedPositionFilter == 'All') return true;
      final filterPosition = _selectedPositionFilter.toLowerCase().trim();
      final role =
          (item['role'] ?? item['assessee_role'] ?? '').toString().toUpperCase();
      final subrole = (item['subrole'] ?? item['assessee_subrole'] ?? '')
          .toString()
          .toLowerCase()
          .trim();
      final pos = (item['position'] ?? item['assessee_position'] ?? '')
          .toString()
          .toLowerCase()
          .trim();

      if (role == 'SFP') {
        if (filterPosition == 'sales expert') {
          return pos.contains('sales expert') || pos.contains('expert');
        } else if (filterPosition == 'channel manager') {
          return pos.contains('channel manager') || pos.contains('manager');
        } else if (filterPosition == 'national supervisor') {
          return pos.contains('national supervisor');
        } else if (filterPosition == 'supervisor') {
          return pos == 'supervisor';
        }
        return pos.contains(filterPosition);
      } else if (role == 'CE' || role == 'CC') {
        // For CE & CC treat subrole as position
        return subrole == filterPosition || pos == filterPosition;
      }
      return true;
    }).toList();

    // Sort
    filtered.sort((a, b) {
      dynamic aVal, bVal;
      switch (_sortBy) {
        case 'Name':
          aVal = _showTemplates ? (a['name'] ?? '') : (a['assessee_name'] ?? '');
          bVal = _showTemplates ? (b['name'] ?? '') : (b['assessee_name'] ?? '');
          break;
        case 'Role':
          aVal = _showTemplates ? (a['role'] ?? '') : (a['assessee_role'] ?? '');
          bVal = _showTemplates ? (b['role'] ?? '') : (b['assessee_role'] ?? '');
          break;
        case 'Score':
          if (_showTemplates) {
            aVal = a['created_by'] ?? '';
            bVal = b['created_by'] ?? '';
          } else {
            aVal = double.tryParse((a['final_score'] ?? '0').toString()) ?? 0.0;
            bVal = double.tryParse((b['final_score'] ?? '0').toString()) ?? 0.0;
          }
          break;
        case 'Date':
        default:
          aVal = _showTemplates ? (a['created_at'] ?? '') : (a['completed_at'] ?? '');
          bVal = _showTemplates ? (b['created_at'] ?? '') : (b['completed_at'] ?? '');
          if (aVal is String && aVal.isNotEmpty) {
            aVal = DateTime.tryParse(aVal) ?? DateTime.fromMillisecondsSinceEpoch(0);
          }
          if (bVal is String && bVal.isNotEmpty) {
            bVal = DateTime.tryParse(bVal) ?? DateTime.fromMillisecondsSinceEpoch(0);
          }
      }
      final cmp = aVal.toString().compareTo(bVal.toString());
      return _sortAscending ? cmp : -cmp;
    });

    return filtered;
  }

  // ---------------- Navigation ----------------

  void navigateToDashboard() {
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

  void navigateToAssessment() {
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

  void navigateToProfiles() {
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

  void navigateToReports() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Reports page not implemented yet")),
    );
  }

  // ---------------- UI pieces ----------------

  void _toggleSidebar() {
    setState(() => _isSidebarVisible = !_isSidebarVisible);
  }

  Color _answerColor(String answer) {
    switch (answer.toLowerCase()) {
      case 'oui':
      case 'yes':
        return Colors.green;
      case 'partiellement':
      case 'partially':
        return Colors.orange;
      case 'non':
      case 'no':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  Color _scoreColor(dynamic score) {
    if (score == null) return Colors.grey;
    final s = double.tryParse(score.toString()) ?? 0.0;
    if (s >= 2.5) return const Color(0xFF10B981);
    if (s >= 2.0) return const Color(0xFFF59E0B);
    return const Color(0xFFEF4444);
  }

  String _fmtScore(dynamic score) {
    if (score == null) return 'N/A';
    final s = double.tryParse(score.toString()) ?? 0.0;
    return '${(s * 100 / 3).toStringAsFixed(1)}%';
  }

  String _fmtOn3(dynamic score) {
    if (score == null) return 'N/A';
    final s = double.tryParse(score.toString()) ?? 0.0;
    return '${s.toStringAsFixed(2)}/3.0';
  }

  String _fmtDate(dynamic date) {
    if (date == null) return 'N/A';
    try {
      final dt = DateTime.parse(date.toString());
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
    } catch (_) {
      return date.toString();
    }
  }

  Widget _filterDropdown(
      String label, String value, List<String> options, Function(String) onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          items: options
              .map((o) => DropdownMenuItem<String>(value: o, child: Text(o)))
              .toList(),
          onChanged: (v) => v != null ? onChanged(v) : null,
          icon: const Icon(Icons.keyboard_arrow_down, size: 20),
        ),
      ),
    );
  }

  // ---------------- Build ----------------

  @override
  Widget build(BuildContext context) {
    final filteredData = _getFilteredAndSortedData();

    // Resolve animated gradient colors once here for small accents
    final colors = _lerp3(
      gradientSets[currentGradientIndex],
      gradientSets[nextGradientIndex],
      _gradientAnimation.value,
    );

    final bool isAdmin = widget.position.toLowerCase() == 'all';

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Stack(
        children: [
          // Main area
          Padding(
            padding: EdgeInsets.only(
              left: _isSidebarVisible ? 300 : 20,
              right: 20,
              top: 20,
              bottom: 20,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top bar
                Row(
                  children: [
                    // Small animated gradient button ONLY
                    _AnimatedChipButton(
                      colors: colors,
                      icon: _isSidebarVisible ? Icons.close : Icons.menu,
                      onTap: _toggleSidebar,
                    ),
                    const SizedBox(width: 20),
                    Icon(Icons.assessment, color: colors[0], size: 20),
                    const SizedBox(width: 8),
                    Text('Assessments',
                        style: TextStyle(color: colors[0], fontSize: 16)),
                    Icon(Icons.chevron_right, color: Colors.grey[400], size: 20),
                    Text(
                      '${widget.selectedCategory} ${widget.selectedSubCategory ?? 'Templates'}',
                      style: TextStyle(color: Colors.grey[600], fontSize: 16),
                    ),
                    const Spacer(),
                    _AnimatedChipButton(
                      colors: [colors[1], colors[2]],
                      icon: Icons.refresh,
                      onTap: () async {
                        await Future.wait([
                          fetchTemplates(),
                          fetchAssessmentHistory(), // rehydrates
                        ]);
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Data refreshed")),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Title row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      ShaderMask(
                        shaderCallback: (bounds) => LinearGradient(
                          colors: colors,
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ).createShader(bounds),
                        child: const Text(
                          'Assessment',
                          style: TextStyle(
                            fontSize: 28, fontWeight: FontWeight.bold,
                            color: Colors.white, letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${filteredData.length} ${_showTemplates ? 'templates' : 'assessments'} available',
                        style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                      ),
                    ]),
                    // ADMIN-ONLY create button (was visible for everyone)
                    if (_showTemplates && isAdmin)
                      _AnimatedFilledButton(
                        colors: colors,
                        icon: Icons.add,
                        label: 'Create Template',
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => CreateTemplateScreen(
                                role: widget.role,
                                subrole: widget.subrole,
                                username: widget.username,
                                position: widget.position,
                                
                                nationalSupervisorId: widget.nationalSupervisorId,
                                supervisorId: widget.supervisorId,
                              ),
                            ),
                          );
                        },
                      ),
                  ],
                ),

                const SizedBox(height: 20),

                // Toggle templates/history (no network here)
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white, borderRadius: BorderRadius.circular(12),
                    boxShadow: [BoxShadow(color: colors[0].withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 2))],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _showTemplates = true),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            decoration: BoxDecoration(
                              gradient: _showTemplates
                                  ? LinearGradient(colors: colors)
                                  : null,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              'Assessment Templates',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: _showTemplates ? Colors.white : colors[0],
                                fontWeight: FontWeight.w600, fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _showTemplates = false),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            decoration: BoxDecoration(
                              gradient: !_showTemplates
                                  ? LinearGradient(colors: colors)
                                  : null,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              'Assessment History',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: !_showTemplates ? Colors.white : colors[0],
                                fontWeight: FontWeight.w600, fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // Search + Filters
                Row(
                  children: [
                    // Debounced search
                    Expanded(
                      flex: 3,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white, borderRadius: BorderRadius.circular(10),
                          boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.1), blurRadius: 8, offset: const Offset(0, 2))],
                        ),
                        child: TextField(
                          onChanged: (v) {
                            _searchDebounce?.cancel();
                            _searchDebounce = Timer(const Duration(milliseconds: 250), () {
                              if (!mounted) return;
                              setState(() => searchQuery = v);
                            });
                          },
                          decoration: InputDecoration(
                            hintText: _showTemplates
                                ? 'Search templates by name, role, position...'
                                : 'Search history by name, assessor, template...',
                            prefixIcon: Icon(Icons.search, color: colors[0]),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                            filled: true, fillColor: Colors.white,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    _filterDropdown(
                      'All',
                      _selectedPositionFilter,
                      const ['All', 'Sales Expert', 'Channel Manager', 'National Supervisor', 'Supervisor'],
                      (v) => setState(() => _selectedPositionFilter = v),
                    ),
                    const SizedBox(width: 12),
                    _filterDropdown(
                      'Sort by Date',
                      'Sort by $_sortBy',
                      [
                        'Sort by Date',
                        'Sort by Name',
                        'Sort by Role',
                        if (!_showTemplates) 'Sort by Score',
                      ],
                      (v) {
                        setState(() {
                          _sortBy = v.replaceAll('Sort by ', '');
                          _sortAscending = !_sortAscending;
                        });
                      },
                    ),
                    const SizedBox(width: 12),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white, borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey[300]!),
                      ),
                      child: IconButton(
                        onPressed: () => setState(() => _sortAscending = !_sortAscending),
                        icon: Icon(
                          _sortAscending ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                          color: colors[0],
                        ),
                        tooltip: _sortAscending ? 'Sort Ascending' : 'Sort Descending',
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // The table
                Expanded(
                  child: SingleChildScrollView(child: _buildModernTable(filteredData, colors)),
                ),
              ],
            ),
          ),

          // Sidebar (NOT wrapped in AnimatedBuilder for the whole screen)
          if (_isSidebarVisible)
            Positioned(
              left: 0, top: 0, bottom: 0,
              child: _Sidebar(colors: colors, widget: widget,
                onDashboard: navigateToDashboard,
                onAssessments: navigateToAssessment,
                onProfiles: navigateToProfiles,
                onReports: navigateToReports,
              ),
            ),

          if (_isSidebarVisible)
            GestureDetector(
              onTap: _toggleSidebar,
              child: Container(
                margin: const EdgeInsets.only(left: 280),
                color: Colors.black.withOpacity(0.3),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildModernTable(List<Map<String, dynamic>> data, List<Color> colors) {
    final availableWidth =
        MediaQuery.of(context).size.width - (_isSidebarVisible ? 320 : 40);

    if (data.isEmpty) {
      return Container(
        width: availableWidth,
        padding: const EdgeInsets.all(60),
        decoration: _tableBoxDecoration(),
        child: Column(
          children: [
            Icon(_showTemplates ? Icons.description_outlined : Icons.history_outlined,
                size: 72, color: Colors.grey[300]),
            const SizedBox(height: 24),
            Text(
              _showTemplates ? 'No templates found' : 'No assessment history found',
              style: TextStyle(fontSize: 18, color: Colors.grey[500], fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            Text(
              _showTemplates ? 'Create your first template to get started'
                              : 'Complete assessments will appear here',
              style: TextStyle(fontSize: 14, color: Colors.grey[400]),
            ),
          ],
        ),
      );
    }

    return Center(
      child: Container(
        width: availableWidth,
        decoration: _tableBoxDecoration(),
        child: Column(
          children: [
            _tableHeader(),
            ...data.asMap().entries.map((e) {
              final index = e.key;
              final item = e.value;
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(
                    bottom: BorderSide(
                      color: index == data.length - 1 ? Colors.transparent : Colors.grey[100]!,
                      width: 1,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    // Name
                    Expanded(
                      flex: 4,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(
                          _showTemplates ? (item['name'] ?? '') : (item['assessee_name'] ?? ''),
                          style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 15,
                            color: Color(0xFF1F2937), letterSpacing: 0.2,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (_showTemplates && (item['subrole'] ?? '').toString().isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            item['subrole'] ?? '',
                            style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ]
                      ]),
                    ),
                    // Role & Position / Template
                    Expanded(
                      flex: 3,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF3B82F6), borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            _showTemplates ? (item['role'] ?? '') : (item['template_name'] ?? ''),
                            style: const TextStyle(
                              color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.3),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (_showTemplates && (item['position'] ?? '').toString().isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981), borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(
                              item['position'] ?? '',
                              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ]
                      ]),
                    ),
                    // Created by / Assessor
                    Expanded(
                      flex: 2,
                      child: Text(
                        _showTemplates ? (item['created_by'] ?? '') : (item['assessor_name'] ?? ''),
                        style: TextStyle(fontSize: 14, color: Colors.grey[600], fontWeight: FontWeight.w500),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // Date / Score
                    Expanded(
                      flex: 2,
                      child: _showTemplates
                          ? Text(
                              _fmtDate(item['created_at']),
                              style: TextStyle(fontSize: 14, color: Colors.grey[600], fontWeight: FontWeight.w500),
                            )
                          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: _scoreColor(item['final_score']),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Text(
                                  _fmtScore(item['final_score']),
                                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _fmtOn3(item['final_score']),
                                style: TextStyle(fontSize: 12, color: Colors.grey[500], fontWeight: FontWeight.w500),
                              ),
                            ]),
                    ),
                    // Actions
                    SizedBox(
                      width: 80,
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Container(
                          width: 36, height: 36,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF3F4F6),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey[200]!),
                          ),
                          child: IconButton(
                            onPressed: () async {
                              if (_showTemplates) {
                                // Load template to initiate
                                final response = await http.post(
                                  Uri.parse('http://localhost:5000/get_assessment_initiate'),
                                  headers: {'Content-Type': 'application/json'},
                                  body: jsonEncode({'template_name': item['name']}),
                                );
                                if (!mounted) return;
                                if (response.statusCode == 200) {
                                  final fullTemplate = jsonDecode(response.body)['template'];
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => InitiateAssessmentScreen(
                                        template: fullTemplate,
                                        templateName: item['name'] ?? item['template_name'] ?? 'Unnamed Template',
                                        username: widget.username,
                                        role: widget.role,
                                        subrole: widget.subrole,
                                        position: widget.position,
                                        
                                        nationalSupervisorId: widget.nationalSupervisorId,
                                        supervisorId: widget.supervisorId,
                                      ),
                                    ),
                                  );
                                } else {
                                  if (!mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text("Failed to load template")),
                                  );
                                }
                              } else {
                                // History -> open results dialog (and cache)
                                await _openResultDialog(item['id'], colors);
                              }
                            },
                            icon: Icon(Icons.arrow_forward_ios, color: Colors.grey[600], size: 16),
                            padding: EdgeInsets.zero,
                            tooltip: _showTemplates ? 'Initiate Assessment' : 'View Results',
                          ),
                        ),
                        if (_showTemplates && widget.position.toLowerCase() == 'all') ...[
                          const SizedBox(width: 4),
                          Container(
                            width: 36, height: 36,
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF2F2),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFFFECACA)),
                            ),
                            child: IconButton(
                              onPressed: () => _confirmDelete(item['name']),
                              icon: const Icon(Icons.delete_outline, color: Color(0xFFEF4444), size: 16),
                              padding: EdgeInsets.zero,
                              tooltip: 'Delete Template',
                            ),
                          ),
                        ],
                      ]),
                    ),
                  ],
                ),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }

  BoxDecoration _tableBoxDecoration() => BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.08),
            blurRadius: 20,
            spreadRadius: 0,
            offset: const Offset(0, 4),
          ),
        ],
      );

  Widget _tableHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16), topRight: Radius.circular(16),
        ),
        border: Border(bottom: BorderSide(color: Colors.grey[200]!, width: 1)),
      ),
      child: const Row(
        children: [
          Expanded(flex: 4, child: Text('Template / Assessee', style: _thStyle)),
          Expanded(flex: 3, child: Text('Role & Position / Template', style: _thStyle)),
          Expanded(flex: 2, child: Text('Created By ', style: _thStyle)),
          Expanded(flex: 2, child: Text('Date ', style: _thStyle)),
          SizedBox(width: 80, child: Text('Actions', textAlign: TextAlign.center, style: _thStyle)),
        ],
      ),
    );
  }

  // --------- MODERN DELETE DIALOG ----------
  Future<void> _confirmDelete(String name) async {
    final yes = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 60, height: 60,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFFE4E6), Color(0xFFFFC1C7)],
                      begin: Alignment.topLeft, end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626), size: 34),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Delete template?',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                  '“$name” will be permanently removed. This action cannot be undone.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[700]),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: Colors.grey[300]!),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: InkWell(
                        onTap: () => Navigator.pop(ctx, true),
                        borderRadius: BorderRadius.circular(12),
                        child: Ink(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            gradient: const LinearGradient(
                              colors: [Color(0xFFEF4444), Color(0xFFDC2626)],
                              begin: Alignment.topLeft, end: Alignment.bottomRight,
                            ),
                            boxShadow: const [
                              BoxShadow(color: Color(0x33EF4444), blurRadius: 10, offset: Offset(0, 4)),
                            ],
                          ),
                          child: const Center(
                            child: Text(
                              'Delete',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    if (yes == true) await deleteTemplateByName(name);
  }

  Future<void> deleteTemplateByName(String name) async {
    final resp = await http.post(
      Uri.parse('http://localhost:5000/delete_template'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'name': name}),
    );
    if (!mounted) return;
    if (resp.statusCode == 200) {
      final result = jsonDecode(resp.body);
      if (result['status'] == 'success') {
        setState(() => templates.removeWhere((t) => t['name'] == name));
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Template deleted')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: ${result['message']}')));
      }
    }
  }

  Future<void> _openResultDialog(dynamic assessmentId, List<Color> colors) async {
    final response = await http.post(
      Uri.parse('http://localhost:5000/get_assessment_result'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'assessment_id': assessmentId}),
    );

    if (!mounted) return;
    if (response.statusCode != 200) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Failed to load results")));
      return;
    }

    final data = jsonDecode(response.body);
    if (data['status'] != 'success') {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Failed to load results")));
      return;
    }

    final assessment = data['assessment'];

    // NEW: keep cache/state in sync if dialog fetched newer data
    _resultCache[assessmentId] = Map<String, dynamic>.from(assessment);
    final stats = Map<String, dynamic>.from(assessment['statistics'] ?? {});
    final double totalScore = (stats['total_score'] ?? 0.0).toDouble();
    final double maxPossible = (stats['max_possible_score'] ?? 0.0).toDouble();
    final double pct = maxPossible > 0 ? (totalScore / maxPossible * 100.0) : 0.0;
    final double scoreOn3 = (pct / 100.0) * 3.0;
    final dynamic completedAt = assessment['completed_at'];

    // Patch row in list immediately (nice touch)
    setState(() {
      final idx = assessmentHistory.indexWhere((h) => h['id'] == assessmentId);
      if (idx != -1) {
        assessmentHistory[idx] = {
          ...assessmentHistory[idx],
          'final_score': scoreOn3,
          'score_percentage': pct,
          'completed_at': completedAt ?? assessmentHistory[idx]['completed_at'],
        };
      }
    });

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: MediaQuery.of(context).size.width * 0.7,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10)],
              ),
              child: SingleChildScrollView(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    'Assessment Result - ${assessment['template_name'] ?? ''}',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),

                  if (assessment['statistics'] != null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.blue[100]!),
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('Overall Statistics',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blue)),
                        const SizedBox(height: 8),
                        Text('Total Questions: ${assessment['statistics']['total_questions']}'),
                        Text('Answered: ${assessment['statistics']['answered_questions']}'),
                        Text('Completion: ${assessment['statistics']['completion_rate']}%'),
                        Text(
                          'Score: ${assessment['statistics']['total_score'].toStringAsFixed(1)}'
                          '/${assessment['statistics']['max_possible_score'].toStringAsFixed(1)} '
                          '(${assessment['statistics']['score_percentage']}%)',
                        ),
                        Text('Performance: ${assessment['statistics']['performance_level']}'),
                      ]),
                    ),

                  ...assessment['categories'].map<Widget>((cat) {
                    final double catScore = (cat['category_score'] ?? 0.0) * 1.0;
                    final double catMax =
                        (cat['max_category_score'] ?? ((cat['total_questions'] ?? 0) * 3.0)) * 1.0;
                    final double catPct = catMax > 0 ? (catScore / catMax * 100) : 0.0;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey[200]!),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${cat['title']} | ${catScore.toStringAsFixed(1)}/${catMax.toStringAsFixed(1)} '
                            '(${catPct.toStringAsFixed(1)}%) | '
                            'Answered: ${cat['answered_questions']}/${cat['total_questions']}',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                          ),
                          if ((cat['description'] ?? '').toString().isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(cat['description'], style: const TextStyle(color: Colors.grey)),
                            ),
                          ...cat['questions'].map<Widget>((q) {
                            final double qScore = (q['score_obtained'] ?? 0.0) * 1.0;
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6.0),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text("Q: ${q['question_text']}", style: const TextStyle(fontWeight: FontWeight.w500)),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: _answerColor(q['answer'] ?? ''),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        q['answer'] ?? 'N/A',
                                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text('Score: ${qScore.toStringAsFixed(1)}/3.0',
                                        style: TextStyle(color: Colors.grey[600])),
                                  ],
                                ),
                                if ((q['comment'] ?? '').toString().isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4.0),
                                    child: Text("Comment: ${q['comment']}",
                                        style: const TextStyle(color: Colors.grey)),
                                  ),
                                const Divider(),
                              ]),
                            );
                          }).toList(),
                        ],
                      ),
                    );
                  }).toList(),
                ]),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ---------- Small animated UI helpers (not wrapping the whole page) ----------

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
        gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: colors.first.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: IconButton(onPressed: onTap, icon: Icon(icon, color: Colors.white)),
    );
  }
}

class _AnimatedFilledButton extends StatelessWidget {
  final List<Color> colors;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _AnimatedFilledButton({
    required this.colors,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [BoxShadow(color: colors.first.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, color: Colors.white),
        label: Text(label, style: const TextStyle(color: Colors.white)),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent, shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  final List<Color> colors;
  final AssessmentListScreen widget;
  final VoidCallback onDashboard;
  final VoidCallback onAssessments;
  final VoidCallback onProfiles;
  final VoidCallback onReports;

  const _Sidebar({
    required this.colors,
    required this.widget,
    required this.onDashboard,
    required this.onAssessments,
    required this.onProfiles,
    required this.onReports,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 280,
      height: MediaQuery.of(context).size.height,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
        boxShadow: [
          BoxShadow(color: colors.first.withOpacity(0.3), blurRadius: 20, spreadRadius: 5, offset: const Offset(5, 0)),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withOpacity(0.2)),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset('assets/logo.png', width: 90),
              ),
            ),
            const SizedBox(height: 24),
            const Text('PHILIP MORRIS',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 2.2)),
            const SizedBox(height: 4),
            Text('INTERNATIONAL',
                style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 12, letterSpacing: 1.8)),
            const SizedBox(height: 36),

            GestureDetector(onTap: onDashboard, child: _navItem(Icons.dashboard_outlined, 'Dashboard', false)),
            const SizedBox(height: 16),
            GestureDetector(onTap: onAssessments, child: _navItem(Icons.assessment_outlined, 'Assessments', true)),
            const SizedBox(height: 16),
            GestureDetector(onTap: onProfiles, child: _navItem(Icons.people_outlined, 'Profiles', false)),
            const SizedBox(height: 16),
            GestureDetector(onTap: onReports, child: _navItem(Icons.analytics_outlined, 'Reports', false)),

            const Spacer(),
            _userInfo(widget.username, widget.role),
          ]),
        ),
      ),
    );
  }

  Widget _navItem(IconData icon, String title, bool active) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: active ? Colors.white.withOpacity(0.15) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: active ? Border.all(color: Colors.white.withOpacity(0.3)) : null,
      ),
      child: Row(
        children: [
          Icon(icon, color: active ? Colors.white : Colors.white.withOpacity(0.7), size: 22),
          const SizedBox(width: 16),
          Text(title,
              style: TextStyle(
                  color: active ? Colors.white : Colors.white.withOpacity(0.7),
                  fontSize: 16,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                  letterSpacing: 0.5)),
        ],
      ),
    );
  }

  Widget _userInfo(String username, String role) {
    return Container(
      margin: const EdgeInsets.only(bottom: 30),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: Colors.white.withOpacity(0.2),
            child: Text(
              username.isNotEmpty ? username[0].toUpperCase() : 'U',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(username,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1),
              Text(role,
                  style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 10),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1),
            ]),
          ),
          IconButton(
            onPressed: () {},
            icon: Icon(Icons.settings, color: Colors.white.withOpacity(0.8), size: 16),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
          ),
        ],
      ),
    );
  }
}

// ---------- Small utilities ----------

const TextStyle _thStyle =
    TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Color(0xFF374151), letterSpacing: 0.5);

extension _Slice3 on List<Color> {
  static List<List<Color>> slices3(List<Color> src) {
    final out = <List<Color>>[];
    for (int i = 0; i + 2 < src.length; i += 3) {
      out.add([src[i], src[i + 1], src[i + 2]]);
    }
    return out;
  }
}

extension _ColorListExt on List<Color> {
  static List<List<Color>> get _noop => [];
  // ignore: unused_element
  static List<List<Color>> slices(int size) => _noop;
}

// Helper to split flat color list into triplets
extension on List<Color> {
  List<List<Color>> slices(int size) {
    final out = <List<Color>>[];
    for (var i = 0; i < length; i += size) {
      if (i + size <= length) out.add(sublist(i, i + size));
    }
    return out;
  }
}

List<Color> _lerp3(List<Color> a, List<Color> b, double t) => [
      Color.lerp(a[0], b[0], t) ?? a[0],
      Color.lerp(a[1], b[1], t) ?? a[1],
      Color.lerp(a[2], b[2], t) ?? a[2],
    ];