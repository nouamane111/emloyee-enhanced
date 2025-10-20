// lib/screens/reports_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:fl_chart/fl_chart.dart';

// Navigation targets used by the sidebar:
import 'home.dart';
import 'assessment_category.dart';
import 'Profiles.dart';

// ---- Visual constants ----
const _bg = Color(0xFFF6F8FB);
const _text = Color(0xFF0F172A);
const _muted = Color(0xFF64748B);
const _primary = Color(0xFF2563EB);
const _primarySoft = Color(0xFFEFF6FF);
const _success = Color(0xFF10B981);
const _cardRadius = 14.0;

final _cardShadow = [
  BoxShadow(color: Color(0x1F000000), blurRadius: 18, offset: Offset(0, 8)),
];

class ReportsScreen extends StatefulWidget {
  final String username;
  final String role;     // SFP/CE/CC/ADMIN/...
  final String subrole;  // subrole
  final String position; // 'All' | 'Channel manager' | 'National supervisor' | 'Supervisor' | 'Sales expert'

  const ReportsScreen({
    super.key,
    required this.username,
    required this.role,
    required this.subrole,
    required this.position, 
  });

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> with TickerProviderStateMixin {
  // ---- Config ----
  final String baseUrl = 'http://localhost:5000';

  // ---- Tabs ----
  late TabController _tab;

  // ---- Filters (Team) ----
  String teamRange = 'Last 30 Days';
  String? teamRole;
  String? teamSubrole;
  String? teamPosition;

  // ---- Filters (Individual) ----
  String indivRange = 'Last 180 Days';
  String? selectedMemberId;
  String? selectedMemberName;

  // ---- Data ----
  bool teamLoading = false;
  Map<String, dynamic>? teamData;
  String? teamError;

  bool indivLoading = false;
  Map<String, dynamic>? indivData;
  String? indivError;

  final Map<String, List<Map<String, dynamic>>> categorySeriesCache = {};
  final TextEditingController _personCtrl = TextEditingController();

  // -------- AssessmentList-style gradient + sidebar --------
  bool _isSidebarVisible = false;

  late AnimationController _gradientController;
  late Animation<double> _gradientAnimation;

  final List<List<Color>> gradientSets = const [
    Color(0xFF1e3a8a), Color(0xFF3730a3), Color(0xFF4338ca),
    Color(0xFF0f172a), Color(0xFF1e293b), Color(0xFF334155),
    Color(0xFF2563eb), Color(0xFF3b82f6), Color(0xFF60a5fa),
  ].slices(3);

  int _gNow = 0;
  int _gNext = 1;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);

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

    _gradientAnimation = CurvedAnimation(parent: _gradientController, curve: Curves.easeInOut);
    _gradientController.forward();

    _fetchTeam();
  }

  @override
  void dispose() {
    _tab.dispose();
    _personCtrl.dispose();
    _gradientController.dispose();
    super.dispose();
  }

  // ---------------------------- FETCHERS ----------------------------
  Future<void> _fetchTeam() async {
    setState(() { teamLoading = true; teamError = null; });

    final range = _resolveRange(teamRange);
    final body = {
      "date_from": range.$1,
      "date_to": range.$2,
      "role": teamRole,
      "subrole": teamSubrole,
      "position": teamPosition,
    }..removeWhere((k, v) => v == null || (v is String && v.trim().isEmpty));

    try {
      final r = await http.post(
        Uri.parse('$baseUrl/reports/team_overview'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );
      if (r.statusCode == 200) {
        final json = jsonDecode(r.body);
        if (json['status'] == 'success') {
          setState(() => teamData = Map<String, dynamic>.from(json));
        } else {
          setState(() => teamError = json['message']?.toString() ?? 'Server error');
        }
      } else {
        setState(() => teamError = 'HTTP ${r.statusCode}');
      }
    } catch (e) {
      setState(() => teamError = e.toString());
    } finally {
      setState(() => teamLoading = false);
    }
  }

  Future<void> _fetchIndividual() async {
    if (selectedMemberId == null) {
      setState(() { indivData = null; indivError = null; });
      return;
    }

    setState(() { indivLoading = true; indivError = null; });

    final range = _resolveRange(indivRange);
    final body = {
      "member_id": int.tryParse(selectedMemberId ?? ''),
      "date_from": range.$1,
      "date_to": range.$2,
    };

    try {
      final r = await http.post(
        Uri.parse('$baseUrl/reports/individual_overview'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );
      if (r.statusCode == 200) {
        final json = jsonDecode(r.body);
        if (json['status'] == 'success') {
          setState(() => indivData = Map<String, dynamic>.from(json));
        } else {
          setState(() => indivError = json['message']?.toString() ?? 'Server error');
        }
      } else {
        setState(() => indivError = 'HTTP ${r.statusCode}');
      }
    } catch (e) {
      setState(() => indivError = e.toString());
    } finally {
      setState(() => indivLoading = false);
    }
  }

  Future<void> _fetchCategorySeries(String categoryTitle) async {
    if (selectedMemberId == null) return;
    final key = '${selectedMemberId}|$categoryTitle';
    if (categorySeriesCache[key] != null) return;

    try {
      final r = await http.post(
        Uri.parse('$baseUrl/reports/individual_category_series'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          "member_id": int.tryParse(selectedMemberId!),
          "category_title": categoryTitle
        }),
      );
      if (r.statusCode == 200) {
        final json = jsonDecode(r.body);
        if (json['status'] == 'success') {
          final list = List<Map<String, dynamic>>.from(json['series'] ?? []);
          setState(() => categorySeriesCache[key] = list);
        }
      }
    } catch (_) {}
  }

  // ---------------------------- NAME/ID RESOLVER ----------------------------
  Future<void> _applyPersonInput() async {
    final raw = _personCtrl.text.trim();
    if (raw.isEmpty) {
      setState(() { selectedMemberId = null; selectedMemberName = null; });
      return;
    }

    final maybeId = int.tryParse(raw);
    if (maybeId != null) {
      setState(() {
        selectedMemberId = maybeId.toString();
        selectedMemberName = 'Employee #$maybeId';
      });
      await _fetchIndividual();
      return;
    }

    final params = <String, String>{
      'position': widget.position.toLowerCase(),
      'username': widget.username,
      'query': raw,
      'limit': '15',
    };
    final ru = widget.role.toUpperCase();
    if (ru == 'SFP' || ru == 'CE' || ru == 'CC') params['role'] = ru;

    try {
      final uri = Uri.parse('$baseUrl/search_profiles').replace(queryParameters: params);
      final r = await http.get(uri);

      if (r.statusCode != 200) {
        String msg = 'HTTP ${r.statusCode}';
        try {
          final body = jsonDecode(r.body);
          if (body is Map && body['error'] != null) msg = body['error'].toString();
        } catch (_) {}
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
        return;
      }

      final decoded = jsonDecode(r.body);
      if (decoded is! List || decoded.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No matching employee found')),
          );
        }
        return;
      }

      Map<String, dynamic>? chosen;
      if (decoded.length == 1) {
        chosen = Map<String, dynamic>.from(decoded.first);
      } else {
        chosen = await _pickFromResults(decoded.cast<Map<String, dynamic>>());
      }
      if (chosen == null) return;

      final id = (chosen['id'] ?? '').toString();
      final name = (chosen['full_name'] ?? '').toString();
      if (id.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Result missing id')),
          );
        }
        return;
      }

      setState(() {
        selectedMemberId = id;
        selectedMemberName = name.isEmpty ? 'Employee #$id' : name;
        _personCtrl.text = selectedMemberName!;
      });
      await _fetchIndividual();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Search failed')),
        );
      }
    }
  }

  Future<Map<String, dynamic>?> _pickFromResults(List<Map<String, dynamic>> results) async {
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Select employee'),
          content: SizedBox(
            width: 420,
            height: 360,
            child: ListView.separated(
              itemCount: results.length,
              separatorBuilder: (context, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final s = results[i];
                final name = (s['full_name'] ?? '').toString();
                final role = (s['role'] ?? s['category'] ?? '').toString();
                final pos  = (s['position'] ?? '').toString();
                return ListTile(
                  dense: true,
                  leading: const Icon(Icons.person),
                  title: Text(name.isEmpty ? '(no name)' : name,
                    overflow: TextOverflow.ellipsis, maxLines: 1),
                  subtitle: Text([role, pos].where((e) => e.isNotEmpty).join(' • '),
                    overflow: TextOverflow.ellipsis, maxLines: 1),
                  onTap: () => Navigator.of(context).pop(s),
                );
              },
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(null), child: const Text('Cancel')),
          ],
        );
      },
    );
  }

  // ---------------------------- HELPERS ----------------------------
  (String, String) _resolveRange(String label) { 
    final now = DateTime.now().toUtc();
    DateTime from;
    switch (label) {
      case 'Last 7 Days': from = now.subtract(const Duration(days: 7)); break;
      case 'Last 90 Days': from = now.subtract(const Duration(days: 90)); break;
      case 'Last 180 Days': from = now.subtract(const Duration(days: 180)); break;
      case 'Last Year': from = DateTime(now.year - 1, now.month, now.day).toUtc(); break;
      case 'Last 30 Days':
      default: from = now.subtract(const Duration(days: 30));
    }
    return (from.toIso8601String(), now.toIso8601String());
  }

  String _fmtPct(double v) => '${v.toStringAsFixed(1)}%';
  String _fmtOn3(double v) => '${v.toStringAsFixed(2)}/3.0';

  String _shortDateLabel(int i, List<Map<String, dynamic>> rows) {
    if (i < 0 || i >= rows.length) return '';
    final d = (rows[i]['date'] ?? '').toString();
    return d.length >= 5 ? d.substring(d.length - 5) : d;
  }

  BoxDecoration _panel() => BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_cardRadius),
        boxShadow: _cardShadow,
        gradient: const LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [Color(0xFFFFFFFF), Color(0xFFF9FBFF)],
        ),
      );

  BoxDecoration _card() => BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_cardRadius),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [BoxShadow(color: const Color(0x0D2563EB), blurRadius: 12, offset: Offset(0, 6))],
      );

  Widget _pillWrap(Widget child) => Container(
        decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [BoxShadow(color: const Color(0x0F000000), blurRadius: 10, offset: Offset(0, 4))],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: child,
      );

  // Simple shimmer-ish block for loading skeletons
  Widget _shimmerBlock({double height = 140, double radius = _cardRadius}) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          colors: [Colors.grey.shade300, Colors.grey.shade200, Colors.grey.shade300],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
      ),
    );
  }

  Widget _empty(String title, {String? subtitle, IconData icon = Icons.inbox_outlined}) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 40, color: _muted),
        const SizedBox(height: 8),
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700, color: _text)),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(color: _muted)),
        ]
      ]),
    );
  }

  Widget _stagger(int i, Widget child, {int base = 120, int step = 40}) {
    return TweenAnimationBuilder<double>(
      duration: Duration(milliseconds: base + i * step),
      tween: Tween(begin: 0, end: 1),
      curve: Curves.easeOut,
      builder: (context, t, _) => Transform.translate(
        offset: Offset(0, (1 - t) * 12),
        child: Opacity(opacity: t, child: child),
      ),
      child: child,
    );
  }

  // ---------- Performance level based on overall GPA (on 3.0) ----------
  String getPerformanceLevel(double gpaOn3) {
    if (gpaOn3 >= 2.55) return 'Accelerate';
    if (gpaOn3 >= 2.10) return 'Advanced';
    return 'Inadequate';
  }

  Color performanceColor(String level) {
    switch (level) {
      case 'Accelerate': return const Color(0xFF10B981); // green
      case 'Advanced':   return const Color(0xFF3B82F6); // blue
      default:           return const Color(0xFFEF4444); // red
    }
  }

  // Normalize "By Role" bars to always show SFP, CE, CC in the same order
  List<Map<String, dynamic>> normalizeByRole(List<Map<String, dynamic>> raw) {
    final map = <String, double>{};
    for (final r in raw) {
      final role = (r['role'] ?? '').toString().toUpperCase();
      final count = (r['count'] ?? 0) * 1.0;
      map[role] = (map[role] ?? 0) + count;
    }
    final order = ['SFP', 'CE', 'CC'];
    return order.map((k) => {'role': k, 'count': (map[k] ?? 0.0)}).toList();
  }

  // ---------------------------- BUILD ----------------------------
  @override
  Widget build(BuildContext context) {
    final colors = _lerp3(
      gradientSets[_gNow],
      gradientSets[_gNext],
      _gradientAnimation.value,
    );
    final isNarrow = MediaQuery.of(context).size.width < 1000;

    // clamp text scale to avoid overflow explosions
    final clamped = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.15);

    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: clamped),
      child: Scaffold(
        backgroundColor: _bg,
        body: Stack(
          children: [
            // Main area
            Padding(
              padding: EdgeInsets.only(
                left: (_isSidebarVisible && !isNarrow) ? 300 : 20,
                right: 20, top: 20, bottom: 20,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top bar (gradient chip buttons + title)
                  Row(
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
                      _AnimatedChipButton(
                        colors: [colors[1], colors[2]],
                        icon: Icons.refresh,
                        onTap: () async {
                          await Future.wait([_fetchTeam(), _fetchIndividual()]);
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Data refreshed")));
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Title row
                  ShaderMask(
                    shaderCallback: (bounds) => LinearGradient(
                      colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight,
                    ).createShader(bounds),
                    child: const Text(
                      'Analytics',
                      style: TextStyle(
                        fontSize: 28, fontWeight: FontWeight.bold,
                        color: Colors.white, letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Team & Individual performance',
                    style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                  ),

                  const SizedBox(height: 20),

                  // Toggle for tabs
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white, borderRadius: BorderRadius.circular(12),
                      boxShadow: [BoxShadow(color: colors[0].withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 2))],
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() => _tab.index = 0),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              decoration: BoxDecoration(
                                gradient: _tab.index == 0 ? LinearGradient(colors: colors) : null,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                'Team',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: _tab.index == 0 ? Colors.white : colors[0],
                                  fontWeight: FontWeight.w600, fontSize: 16,
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() => _tab.index = 1),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              decoration: BoxDecoration(
                                gradient: _tab.index == 1 ? LinearGradient(colors: colors) : null,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                'Individual',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: _tab.index == 1 ? Colors.white : colors[0],
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

                  // Keep swipe between tabs with TabBarView
                  Expanded(
                    child: TabBarView(
                      controller: _tab,
                      children: [
                        _buildTeamTab(colors),
                        _buildIndividualTab(colors),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Sidebar (static on wide, modal overlay on narrow)
            if (_isSidebarVisible && !isNarrow)
              Positioned(
                left: 0, top: 0, bottom: 0,
                child: _Sidebar(
                  colors: colors,
                  username: widget.username,
                  role: widget.role,
                  onDashboard: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (_) => homeScreen(
                          role: widget.role, subrole: widget.subrole, username: widget.username, position: widget.position,
                        ),
                      ),
                    );
                  },
                  onAssessments: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AssessmentCategoryScreen(
                          role: widget.role, subrole: widget.subrole, username: widget.username, position: widget.position,
                        ),
                      ),
                    );
                  },
                  onProfiles: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ProfilesScreen(
                          role: widget.role, subrole: widget.subrole, username: widget.username, position: widget.position,
                        ),
                      ),
                    );
                  },
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
                        onDashboard: () {
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                              builder: (_) => homeScreen(
                                role: widget.role, subrole: widget.subrole, username: widget.username, position: widget.position,
                              ),
                            ),
                          );
                        },
                        onAssessments: () {
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                              builder: (_) => AssessmentCategoryScreen(
                                role: widget.role, subrole: widget.subrole, username: widget.username, position: widget.position,
                              ),
                            ),
                          );
                        },
                        onProfiles: () {
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ProfilesScreen(
                                role: widget.role, subrole: widget.subrole, username: widget.username, position: widget.position,
                              ),
                            ),
                          );
                        },
                        onReports: () => setState(() => _isSidebarVisible = false),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ---------------------------- TEAM TAB ----------------------------
  Widget _buildTeamTab(List<Color> colors) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _teamFilters(),
          const SizedBox(height: 12),
          Expanded(
            child: TweenAnimationBuilder<double>(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOut,
              tween: Tween(begin: 0, end: 1),
              builder: (context, t, child) => Transform.translate(
                offset: Offset(0, (1 - t) * 12),
                child: Opacity(opacity: t, child: child),
              ),
              child: Container(
                decoration: _panel(),
                padding: const EdgeInsets.all(16),
                child: teamLoading
                    // FIX: make loading content scrollable to avoid overflow at small heights
                    ? SingleChildScrollView(
                        child: Column(children: [
                          _shimmerBlock(height: 64),
                          const SizedBox(height: 12),
                          _shimmerBlock(height: 240),
                        ]),
                      )
                    : teamError != null
                        ? Center(child: Text(teamError!, style: const TextStyle(color: Colors.red)))
                        : teamData == null
                            ? _empty('No data', subtitle: 'Adjust filters and try again')
                            : _teamContent(teamData!),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _teamFilters() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 10,
        runSpacing: 10,
        children: [
          _pillWrap(
            DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                value: teamRange,
                hint: const Text('Range'),
                items: const ['Last 7 Days', 'Last 30 Days', 'Last 90 Days', 'Last 180 Days', 'Last Year']
                    .map((e) => DropdownMenuItem<String?>(value: e, child: Text(e))).toList(),
                onChanged: (v) => setState(() { teamRange = v!; _fetchTeam(); }),
              ),
            ),
          ),
          _pillWrap(
            DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                value: teamRole,
                hint: const Text('Role'),
                items: const <String?>[null, 'SFP', 'CE', 'CC']
                    .map((e) => DropdownMenuItem<String?>(value: e, child: Text(e ?? 'Any'))).toList(),
                onChanged: (v) => setState(() { teamRole = v; teamSubrole = null; teamPosition = null; _fetchTeam(); }),
              ),
            ),
          ),
          if (teamRole != null && teamRole!.isNotEmpty)
            _pillWrap(
              SizedBox(
                width: 240,
                child: TextField(
                  onChanged: (v) => teamSubrole = v.isEmpty ? null : v,
                  onSubmitted: (_) => _fetchTeam(),
                  decoration: const InputDecoration(
                    border: InputBorder.none, labelText: 'Subrole', hintText: 'e.g. Brand representatives',
                    contentPadding: EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ),
          _pillWrap(
            SizedBox(
              width: 220,
              child: TextField(
                onChanged: (v) => teamPosition = v.isEmpty ? null : v,
                onSubmitted: (_) => _fetchTeam(),
                decoration: const InputDecoration(
                  border: InputBorder.none, labelText: 'Position', hintText: 'e.g. Sales expert',
                  contentPadding: EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ),
          _gradientActionBtn(icon: Icons.refresh, label: 'Refresh', onTap: _fetchTeam),
        ],
      ),
    );
  }

  Widget _teamContent(Map<String, dynamic> d) {
    final totals = Map<String, dynamic>.from(d['totals'] ?? {});
    final rawByRole = List<Map<String, dynamic>>.from(d['by_role'] ?? []);
    final byRole = normalizeByRole(rawByRole); // SFP / CE / CC in order
    final bySec = List<Map<String, dynamic>>.from(d['by_secondary'] ?? []);
    final trend = List<Map<String, dynamic>>.from(d['trend'] ?? []);

    return SingleChildScrollView(
      child: Column(
        children: [
          Row(children: [
            Expanded(child: _stagger(0, _kpi('Assessments', (totals['assessments'] ?? 0).toString(), Icons.description))),
            const SizedBox(width: 10),
            Expanded(child: _stagger(1, _kpi('Avg Score', _fmtOn3((totals['avg_on3'] ?? 0.0) * 1.0), Icons.trending_up))),
          ]),
          const SizedBox(height: 16),
          LayoutBuilder(builder: (context, c) {
            final narrow = c.maxWidth < 1000;

            // Build panels once
            final trendPanel = _panelChart(
              title: 'Trend (Avg on 3 by day)',
              icon: Icons.show_chart,
              child: _lineTrend(trend),
            );
            final byRolePanel = _panelChart(
              title: 'By Role (SFP / CE / CC)',
              icon: Icons.group,
              child: _hBars(
                byRole.map((e) => (e['role'] ?? 'Unknown').toString()).toList(),
                byRole.map((e) => ((e['count'] ?? 0) * 1.0) as double).toList(),
              ),
            );
            final bySecPanel = _panelChart(
              title: (bySec.isNotEmpty ? (bySec.first['label'] ?? 'Breakdown') : 'Breakdown').toString(),
              icon: Icons.pie_chart_outline_rounded,
              child: _hBars(
                bySec.map((e) => (e['name'] ?? 'Unknown').toString()).toList(),
                bySec.map((e) => (e['count'] ?? 0) * 1.0).cast<double>().toList(),
              ),
            );

            if (narrow) {
              // FIX: no Expanded in a vertical column inside a scroll view
              return Column(
                children: [
                  trendPanel,
                  const SizedBox(height: 12),
                  byRolePanel,
                  const SizedBox(height: 12),
                  bySecPanel,
                ],
              );
            }

            // Wide: use Expanded inside a Row (bounded horizontally)
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 2, child: trendPanel),
                const SizedBox(width: 12),
                Expanded(child: byRolePanel),
                const SizedBox(width: 12),
                Expanded(child: bySecPanel),
              ],
            );
          }),
        ],
      ),
    );
  }

  // ---------------------------- INDIVIDUAL TAB ----------------------------
  Widget _buildIndividualTab(List<Color> colors) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _indivFilters(),
          const SizedBox(height: 12),
          Expanded(
            child: TweenAnimationBuilder<double>(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOut,
              tween: Tween(begin: 0, end: 1),
              builder: (context, t, child) => Transform.translate(
                offset: Offset(0, (1 - t) * 12),
                child: Opacity(opacity: t, child: child),
              ),
              child: Container(
                decoration: _panel(),
                padding: const EdgeInsets.all(16),
                child: indivLoading
                    // FIX: make loading content scrollable to avoid overflow at small heights
                    ? SingleChildScrollView(
                        child: Column(children: [
                          _shimmerBlock(height: 64),
                          const SizedBox(height: 12),
                          _shimmerBlock(height: 240),
                        ]),
                      )
                    : indivError != null
                        ? Center(child: Text(indivError!, style: const TextStyle(color: Colors.red)))
                        : indivData == null
                            ? _empty('Pick an employee to view', subtitle: 'Search by id or name above', icon: Icons.search)
                            : _indivContent(indivData!),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _indivFilters() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.center,
        children: [
          _pillWrap(
            DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                value: indivRange,
                hint: const Text('Range'),
                items: const ['Last 30 Days', 'Last 90 Days', 'Last 180 Days', 'Last Year']
                    .map((e) => DropdownMenuItem<String?>(value: e, child: Text(e))).toList(),
                onChanged: (v) => setState(() { indivRange = v!; _fetchIndividual(); }),
              ),
            ),
          ),
          SizedBox(
            width: 420,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(28), border: Border.all(color: const Color(0xFFE5E7EB)),
                boxShadow: [BoxShadow(color: const Color(0x0F000000), blurRadius: 12, offset: Offset(0, 6))],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: TextField(
                controller: _personCtrl,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  hintText: 'Search employee by id or name…',
                  prefixIcon: Icon(Icons.search, color: _muted),
                ),
                onSubmitted: (_) => _applyPersonInput(),
              ),
            ),
          ),
          _gradientActionBtn(icon: Icons.check, label: 'Apply', onTap: _applyPersonInput),
          _gradientActionBtn(icon: Icons.refresh, label: 'Refresh', onTap: _fetchIndividual),
        ],
      ),
    );
  }

  Widget _indivContent(Map<String, dynamic> d) {
    final member = Map<String, dynamic>.from(d['member'] ?? {});
    final overall = Map<String, dynamic>.from(d['overall'] ?? {});
    final cats = List<Map<String, dynamic>>.from(d['categories'] ?? []);
    final timeline = List<Map<String, dynamic>>.from(d['timeline'] ?? []);
    final overallOn3 = (overall['final_on3'] ?? 0.0) * 1.0;

    return SingleChildScrollView(
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: _memberHeader(member),
          ),
          const SizedBox(height: 12),

          // Donut + Performance + Timeline
          LayoutBuilder(
            builder: (context, c) {
              final narrow = c.maxWidth < 900;

              // build the three panels once
              final donutPanel = _panelChart(
                title: 'Overall (on 3)',
                icon: Icons.donut_large_outlined,
                child: _donut(overallOn3),
              );
              final perfCard = _performanceCard(overallOn3);
              final linePanel = _panelChart(
                title: 'Timeline (final on 3)',
                icon: Icons.timeline,
                child: _lineTimeline(timeline),
              );

              if (narrow) {
                // FIX: no Expanded for the line chart inside a vertical column in a scroll view
                return Column(children: [
                  Row(children: [
                    Expanded(child: donutPanel),
                    const SizedBox(width: 12),
                    Expanded(child: perfCard),
                  ]),
                  const SizedBox(height: 12),
                  linePanel,
                ]);
              }
              return Row(children: [
                Expanded(child: donutPanel),
                const SizedBox(width: 12),
                Expanded(child: perfCard),
                const SizedBox(width: 12),
                Expanded(flex: 2, child: linePanel),
              ]);
            },
          ),

          const SizedBox(height: 16),

          // Category cards (modern, no mini-graphs)
          Container(
            decoration: _card(),
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Icon(Icons.category_outlined, color: _primary, size: 18),
                      SizedBox(width: 8),
                      Text('Categories (averages)',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: _text)),
                    ],
                  ),
                ),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: cats.map((c) {
                    final title = (c['category'] ?? '').toString();
                    final avg = ((c['avg_on3'] ?? 0.0) * 1.0).toDouble();
                    final answered = (c['answered_q'] ?? 0) as int;
                    final total = (c['total_q'] ?? 0) as int;
                    final right = (c['right'] ?? 0) as int;
                    final partial = (c['partial'] ?? 0) as int;
                    final wrong = (c['wrong'] ?? 0) as int;

                    return SizedBox(
                      width: 260,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(_cardRadius),
                          border: Border.all(color: const Color(0xFFE5E7EB)),
                          boxShadow: [BoxShadow(color: const Color(0x0D2563EB), blurRadius: 12, offset: Offset(0, 6))],
                        ),
                        padding: const EdgeInsets.all(12),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w700, color: _text)),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(color: _primarySoft, borderRadius: BorderRadius.circular(8)),
                                child: Text('${avg.toStringAsFixed(2)} / 3.0',
                                    style: const TextStyle(color: _primary, fontWeight: FontWeight.w600)),
                              ),
                              const SizedBox(width: 8),
                              Text('Answered $answered/$total', style: const TextStyle(color: _muted, fontSize: 12)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              _dotStat(color: Color(0xFF10B981), label: 'Right $right'),
                              const SizedBox(width: 10),
                              _dotStat(color: Color(0xFFF59E0B), label: 'Partial $partial'),
                              const SizedBox(width: 10),
                              _dotStat(color: Color(0xFFEF4444), label: 'Wrong $wrong'),
                            ],
                          ),
                        ]),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _memberHeader(Map<String, dynamic> m) {
    final parts = [
      (m['name'] ?? selectedMemberName ?? 'Employee').toString(),
      (m['role'] ?? '').toString(),
      (m['subrole'] ?? '').toString(),
      (m['position'] ?? '').toString(),
    ].where((s) => s.isNotEmpty).toList();

    return Wrap(
      spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(parts.first, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: _text)),
        ...parts.skip(1).map((p) => Chip(
          label: Text(p, overflow: TextOverflow.ellipsis),
          backgroundColor: _primarySoft,
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        )),
      ],
    );
  }

  Widget _dotStat({required Color color, required String label}) {
    return Row(children: [
      Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 6),
      Text(label, style: const TextStyle(color: _muted, fontSize: 12)),
    ]);
  }

  Widget _performanceCard(double gpaOn3) {
    final level = getPerformanceLevel(gpaOn3);
    final col = performanceColor(level);
    return Container(
      decoration: _card(),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Icon(Icons.speed_outlined, color: _primary, size: 18),
                SizedBox(width: 8),
                Text('Performance',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: _text)),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: col.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
                child: Text(level, style: TextStyle(color: col, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 12),
              Text('${gpaOn3.toStringAsFixed(2)} / 3.0',
                style: const TextStyle(fontWeight: FontWeight.w600, color: _text)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            level == 'Accelerate'
                ? 'High performer. Keep stretching targets and mentor others.'
                : level == 'Advanced'
                    ? 'Solid performance. Focus on category gaps to move up.'
                    : 'Needs improvement. Prioritize training and guided practice.',
            style: const TextStyle(color: _muted, fontSize: 12),
          ),
        ],
      ),
    );
  }

  // ---------------------------- REUSABLE UI ----------------------------
  Widget _kpi(String title, String value, IconData icon) => Container(
        decoration: _card(),
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(backgroundColor: _primarySoft, child: Icon(icon, color: _primary)),
            const SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: _text)),
              Text(title, style: const TextStyle(color: _muted)),
            ]),
          ],
        ),
      );

  Widget _panelChart({required String title, required Widget child, IconData? icon}) => Container(
        decoration: _card(),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                if (icon != null)
                  Container(width: 28, height: 28, decoration: const BoxDecoration(shape: BoxShape.circle, color: _primarySoft),
                    child: Icon(icon, size: 16, color: _primary)),
                if (icon != null) const SizedBox(width: 8),
                Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: _text)),
              ]),
            ),
            SizedBox(height: 240, child: child),
          ],
        ),
      );

  // gradient-styled small action button (label+icon)
  Widget _gradientActionBtn({required IconData icon, required String label, required VoidCallback onTap}) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: _lerp3(gradientSets[_gNow], gradientSets[_gNext], _gradientAnimation.value)),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [BoxShadow(color: gradientSets[_gNow].first.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, color: Colors.white),
        label: Text(label, style: const TextStyle(color: Colors.white)),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent, shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    );
  }

  // ---------------------------- CHARTS ----------------------------
  Widget _lineTrend(List<Map<String, dynamic>> trend) {
    if (trend.isEmpty) return _empty('No data', subtitle: 'Try another date range');
    final spots = <FlSpot>[];
    for (int i = 0; i < trend.length; i++) {
      final y = (trend[i]['avg_on3'] ?? 0.0) * 1.0;
      spots.add(FlSpot(i.toDouble(), y));
    }
    return LineChart(
      LineChartData(
        gridData: FlGridData(show: true, drawVerticalLine: false, horizontalInterval: 0.5,
          getDrawingHorizontalLine: (v) => const FlLine(color: Color(0xFFE2E8F0), strokeWidth: 1)),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 36,
            getTitlesWidget: (v, _) => Text(v.toStringAsFixed(1), style: const TextStyle(fontSize: 10, color: _muted)),
          )),
          bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true,
            getTitlesWidget: (v, _) => Text(_shortDateLabel(v.toInt(), trend), style: const TextStyle(fontSize: 10, color: _muted)),
          )),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots, isCurved: true, barWidth: 3, color: _primary,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(show: true, color: _primary.withOpacity(.12)),
          ),
        ],
        lineTouchData: LineTouchData(
          handleBuiltInTouches: true,
          touchTooltipData: LineTouchTooltipData(
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            tooltipRoundedRadius: 10,
            tooltipPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            tooltipBgColor: const Color(0xFF111827), // dark bg
            getTooltipItems: (ts) => ts.map((t) => LineTooltipItem(
              '${t.y.toStringAsFixed(2)} / 3.0',
              const TextStyle(fontWeight: FontWeight.w700, color: Colors.white),
              children: const [TextSpan(text: '\nAvg on 3', style: TextStyle(fontWeight: FontWeight.w400, color: Colors.white70))],
            )).toList(),
          ),
        ),
      ),
    );
  }

  Widget _hBars(List<String> labels, List<double> values) {
    if (labels.isEmpty || values.isEmpty) return _empty('No data');
    final maxY = values.reduce((a, b) => a > b ? a : b);
    final groups = <BarChartGroupData>[];
    for (int i = 0; i < labels.length; i++) {
      groups.add(BarChartGroupData(
        x: i,
        barRods: [
          BarChartRodData(
            toY: values[i], width: 14, borderRadius: BorderRadius.circular(6), color: _primary,
            backDrawRodData: BackgroundBarChartRodData(show: true, toY: maxY, color: _primary.withOpacity(0.08)),
          ),
        ],
      ));
    }
    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceBetween,
        gridData: FlGridData(show: false),
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true,
            getTitlesWidget: (v, _) {
              final idx = v.toInt();
              if (idx >= 0 && idx < labels.length) {
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: SizedBox(
                    width: 70,
                    child: Text(
                      labels[idx],
                      style: const TextStyle(fontSize: 10, color: _muted),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 2,
                      softWrap: true,
                      textAlign: TextAlign.center, // FIX: center the labels so they don't drift
                    ),
                  ),
                );
              }
              return const SizedBox.shrink();
            },
          )),
        ),
        borderData: FlBorderData(show: false),
        barGroups: groups,
        barTouchData: BarTouchData(
          enabled: true,
          touchTooltipData: BarTouchTooltipData(
            tooltipRoundedRadius: 8,
            tooltipBgColor: const Color(0xFF111827),
            getTooltipItem: (group, groupIndex , rod, _) => BarTooltipItem(
              '${rod.toY.toStringAsFixed(0)}',
              const TextStyle(fontWeight: FontWeight.w700, color: Colors.white),
              children: [TextSpan(text: '\n${labels[group.x.toInt()]}', style: const TextStyle(color: Colors.white70))],
            ),
          ),
        ),
      ),
    );
  }

  // --------- CATEGORIES: horizontally scrollable chart was removed (now cards) ---------

  // Donut & timeline
  Widget _donut(double on3) {
    final pct = (on3 / 3.0).clamp(0.0, 1.0);
    return Stack(
      alignment: Alignment.center,
      children: [
        PieChart(PieChartData(centerSpaceRadius: 58, sectionsSpace: 2, sections: [
          PieChartSectionData(value: pct, radius: 72, color: _success, title: ''),
          PieChartSectionData(value: 1 - pct, radius: 72, color: const Color(0xFFE2E8F0), title: ''),
        ])),
        Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_fmtOn3(on3), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: _text)),
          Text(_fmtPct(pct * 100), style: const TextStyle(color: _muted)),
        ]),
      ],
    );
  }

  Widget _lineTimeline(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) return _empty('No data', subtitle: 'No timeline entries yet');
    final spots = <FlSpot>[];
    for (int i = 0; i < rows.length; i++) {
      final y = (rows[i]['final_on3'] ?? 0.0) * 1.0;
      spots.add(FlSpot(i.toDouble(), y));
    }
    return LineChart(
      LineChartData(
        gridData: FlGridData(show: true, drawVerticalLine: false, horizontalInterval: 0.5,
          getDrawingHorizontalLine: (v) => const FlLine(color: Color(0xFFE2E8F0), strokeWidth: 1)),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 36,
            getTitlesWidget: (v, _) => Text(v.toStringAsFixed(1), style: const TextStyle(fontSize: 10, color: _muted)),
          )),
          bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true,
            getTitlesWidget: (v, _) => Text(_shortDateLabel(v.toInt(), rows), style: const TextStyle(fontSize: 10, color: _muted)),
          )),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots, isCurved: true, barWidth: 3, color: _primary,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(show: true, color: _primary.withOpacity(.12)),
          ),
        ],
        lineTouchData: LineTouchData(
          handleBuiltInTouches: true,
          touchTooltipData: LineTouchTooltipData(
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            tooltipRoundedRadius: 10,
            tooltipPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            tooltipBgColor: const Color(0xFF111827),
            getTooltipItems: (ts) => ts.map((t) => LineTooltipItem(
              '${t.y.toStringAsFixed(2)} / 3.0',
              const TextStyle(fontWeight: FontWeight.w700, color: Colors.white),
              children: const [TextSpan(text: '\nFinal on 3', style: TextStyle(fontWeight: FontWeight.w400, color: Colors.white70))],
            )).toList(),
          ),
        ),
      ),
    );
  }

  // ---------------------- Gradient helpers + sidebar + chips ----------------------
  List<Color> _lerp3(List<Color> a, List<Color> b, double t) => [
        Color.lerp(a[0], b[0], t) ?? a[0],
        Color.lerp(a[1], b[1], t) ?? a[1],
        Color.lerp(a[2], b[2], t) ?? a[2],
      ];
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

// Small gradient chip button (copied from AssessmentList)
class _AnimatedChipButton extends StatelessWidget {
  final List<Color> colors;
  final IconData icon;
  final VoidCallback onTap;

  const _AnimatedChipButton({required this.colors, required this.icon, required this.onTap});

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

// Sidebar (copied/adapted from AssessmentList)
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
    return Container(
      width: 280,
      height: MediaQuery.of(context).size.height,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
        boxShadow: [BoxShadow(color: colors.first.withOpacity(0.3), blurRadius: 20, spreadRadius: 5, offset: const Offset(5, 0))],
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

            GestureDetector(onTap: onDashboard,   child: _navItem(Icons.dashboard_outlined, 'Dashboard', false)),
            const SizedBox(height: 16),
            GestureDetector(onTap: onAssessments, child: _navItem(Icons.assessment_outlined, 'Assessments', false)),
            const SizedBox(height: 16),
            GestureDetector(onTap: onProfiles,    child: _navItem(Icons.people_outlined, 'Profiles', false)),
            const SizedBox(height: 16),
            GestureDetector(onTap: onReports,     child: _navItem(Icons.analytics_outlined, 'Reports', true)),

            const Spacer(),
            _userInfo(username, role),
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
          Icon(Icons.settings, color: Colors.white.withOpacity(0.8), size: 16),
        ],
      ),
    );
  }
}