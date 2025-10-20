// lib/screens/profiles_screen.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'home.dart';
import 'assessment_category.dart';
import 'add_profile.dart';
import 'ProfileDetailScreen.dart';
import 'edit_profile_sheet.dart';

// ---------------------------- VISUAL CONSTANTS ----------------------------
const _bg = Color(0xFFF6F8FB);
const _text = Color(0xFF0F172A);
const _muted = Color(0xFF64748B);
const _primary = Color(0xFF2563EB);
const _primarySoft = Color(0xFFEFF6FF);

const _cardRadius = 14.0;
final _cardShadow = [
  BoxShadow(color: Color(0x1F000000), blurRadius: 18, offset: Offset(0, 8)),
];

class ProfilesScreen extends StatefulWidget {
  final String role;
  final String subrole;
  final String username;
  final String position;

  final String? nationalSupervisorId;
  final String? supervisorId;

  const ProfilesScreen({
    super.key,
    required this.role,
    required this.subrole,
    required this.username,
    required this.position,
    this.nationalSupervisorId,
    this.supervisorId,
  });

  @override
  State<ProfilesScreen> createState() => _ProfilesScreenState();
}

class _ProfilesScreenState extends State<ProfilesScreen> with TickerProviderStateMixin {
  // ---- Config ----
  static const String baseUrl = 'http://localhost:5000';

  // ---- Data ----
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _listCtl = ScrollController();

  List<Map<String, dynamic>> profiles = [];
  bool isLoading = true;
  String? loadError;

  // ---- Pagination (if you want to add infinite scroll later) ----
  int total = 0;
  int limit = 100;
  int offset = 0;
  bool paging = false;

  // ---- Debounce for server search ----
  Timer? _debounce;

  // ---- Typeahead (optional overlay using /search_profiles) ----
  List<Map<String, dynamic>> _suggestions = [];
  bool _searching = false;

  // ---- Gradient header + Sidebar like ReportsScreen ----
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
    _fetchVisibleProfiles(reset: true);

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
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _listCtl.dispose();
    _gradientController.dispose();
    super.dispose();
  }

  // ---------------------------- BACKEND CALLS ----------------------------
  /// Pulls the visible profiles using the backend hierarchy (NO frontend filtering).
  Future<void> _fetchVisibleProfiles({required bool reset}) async {
    if (!mounted) return;

    setState(() {
      if (reset) {
        isLoading = true;
        offset = 0;
        profiles = [];
      } else {
        paging = true;
      }
      loadError = null;
    });

    final isAdmin = widget.role.toLowerCase() == 'admin' || widget.position.toLowerCase() == 'all';

    final params = <String, String>{
      'username': widget.username,
      'role': isAdmin ? '' : widget.role.toUpperCase(),          // '', 'SFP', 'CE', 'CC'
      'position': isAdmin ? 'all' : widget.position.toLowerCase(),
      'q': _searchController.text.trim(),
      'limit': limit.toString(),
      'offset': offset.toString(),
      'order': 'position',
    };

    try {
      final uri = Uri.parse('$baseUrl/profiles_visible').replace(queryParameters: params);
      final r = await http.get(uri, headers: {'Content-Type': 'application/json'});

      if (r.statusCode == 200) {
        final json = jsonDecode(r.body) as Map<String, dynamic>;
        final list = (json['profiles'] as List?)?.cast<Map<String, dynamic>>() ?? <Map<String, dynamic>>[];
        final newTotal = (json['total'] ?? list.length) as int;

        setState(() {
          if (reset) {
            profiles = list;
          } else {
            profiles.addAll(list);
          }
          total = newTotal;
          isLoading = false;
          paging = false;
          offset = profiles.length;
        });
      } else {
        setState(() {
          isLoading = false;
          paging = false;
          loadError = 'HTTP ${r.statusCode}';
        });
        _toast('Failed to load profiles: HTTP ${r.statusCode}');
      }
    } catch (e) {
      setState(() {
        isLoading = false;
        paging = false;
        loadError = e.toString();
      });
      _toast('Failed to load profiles: $e');
    }
  }

  /// Debounced server-side search; updates the list (no client filtering).
  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      _fetchVisibleProfiles(reset: true);
      _searchTypeahead(_searchController.text); // keep overlay suggestions in sync (optional)
    });
  }

  /// Typeahead overlay using your existing /search_profiles logic
  Future<void> _searchTypeahead(String q) async {
    if (!mounted) return;
    final query = q.trim();
    if (query.isEmpty) {
      setState(() => _suggestions = []);
      return;
    }

    setState(() => _searching = true);
    try {
      final params = <String, String>{
        'username': widget.username,
        'position': widget.position.toLowerCase(),
        'role': widget.role.toUpperCase(),
        'query': query,
        'limit': '15',
      };
      final uri = Uri.parse('$baseUrl/search_profiles').replace(queryParameters: params);
      final r = await http.get(uri, headers: {'Content-Type': 'application/json'});

      if (r.statusCode == 200) {
        final decoded = jsonDecode(r.body);
        if (decoded is List) {
          setState(() => _suggestions = decoded.cast<Map<String, dynamic>>());
        } else {
          setState(() => _suggestions = []);
        }
      } else {
        setState(() => _suggestions = []);
      }
    } catch (_) {
      setState(() => _suggestions = []);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  // ---------------------------- NAV ----------------------------
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
    Navigator.push(
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

  void _goAddProfile() {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => AddProfileScreen(
        role: widget.role,
        subrole: widget.subrole,
        position: widget.position,
        username: widget.username,
        nationalSupervisorId: widget.nationalSupervisorId,
        supervisorId: widget.supervisorId,
      ),
    ),
  ).then((_) {
    // Refresh after returning from add
    _fetchVisibleProfiles(reset: true);
  });
}


  // ---------------------------- UI HELPERS ----------------------------
  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  int _positionRank(dynamic posRaw) {
    const order = ['channel manager', 'national supervisor', 'supervisor', 'sales expert'];
    final pos = (posRaw ?? '').toString().toLowerCase();
    final idx = order.indexOf(pos);
    return idx >= 0 ? idx : order.length + 1;
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    if (parts.isEmpty) return 'U';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return (parts[0][0] + parts.last[0]).toUpperCase();
  }

  BoxDecoration _panel() => BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_cardRadius),
        boxShadow: _cardShadow,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
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
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [BoxShadow(color: const Color(0x0F000000), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: child,
      );

  List<Color> _lerp3(List<Color> a, List<Color> b, double t) => [
        Color.lerp(a[0], b[0], t) ?? a[0],
        Color.lerp(a[1], b[1], t) ?? a[1],
        Color.lerp(a[2], b[2], t) ?? a[2],
      ];

  // ---------------------------- BUILD ----------------------------
  @override
  Widget build(BuildContext context) {
    final colors = _lerp3(
      gradientSets[_gNow],
      gradientSets[_gNext],
      _gradientAnimation.value,
    );
    final isNarrow = MediaQuery.of(context).size.width < 1000;

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
                right: 20,
                top: 20,
                bottom: 20,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top bar (menu chip + title + refresh / add button)
                  Row(
                    children: [
                      _AnimatedChipButton(
                        colors: colors,
                        icon: _isSidebarVisible ? Icons.close : Icons.menu,
                        onTap: () => setState(() => _isSidebarVisible = !_isSidebarVisible),
                      ),
                      const SizedBox(width: 20),
                      Icon(Icons.people_alt_outlined, color: colors[0], size: 20),
                      const SizedBox(width: 8),
                      Text('Profiles', style: TextStyle(color: colors[0], fontSize: 16)),
                      const Spacer(),
                      if (widget.role.toLowerCase() == 'admin')
                        _GradientActionBtn(
                          colors: [colors[1], colors[2]],
                          icon: Icons.person_add,
                          label: 'Add',
                          onTap: _goAddProfile,
                        ),
                      const SizedBox(width: 8),
                      _GradientActionBtn(
                        colors: [colors[1], colors[2]],
                        icon: Icons.refresh,
                        label: 'Refresh',
                        onTap: () => _fetchVisibleProfiles(reset: true),
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
                      'Team Directory',
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
                    'Search, view and manage people',
                    style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                  ),

                  const SizedBox(height: 16),

                  // Search + filters pill
                  _filtersBar(colors),

                  const SizedBox(height: 12),

                  // Error banner
                  if (loadError != null)
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      padding: const EdgeInsets.all(12),
                      child: Text(loadError!, style: const TextStyle(color: Colors.red)),
                    ),

                  const SizedBox(height: 12),

                  // List panel
                  Expanded(
                    child: Container(
                      decoration: _panel(),
                      padding: const EdgeInsets.all(12),
                      child: isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : profiles.isEmpty
                              ? _empty('No profiles', subtitle: 'Try a different search')
                              : _profilesList(),
                    ),
                  ),

                  if (paging)
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                ],
              ),
            ),

            // Sidebar (static on wide, overlay on narrow)
            if (_isSidebarVisible && !isNarrow)
              Positioned(
                left: 0, top: 0, bottom: 0,
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
      ),
    );
  }

  // ---------------------------- UI SECTIONS ----------------------------
  Widget _filtersBar(List<Color> colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.start,
        children: [
          // Search with typeahead (fixed width so overlay aligns)
          SizedBox(
            width: 420,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: const Color(0xFFE5E7EB)),
                boxShadow: [BoxShadow(color: const Color(0x0F000000), blurRadius: 12, offset: const Offset(0, 6))],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      hintText: _searching ? 'Searching…' : 'Search by name, role, position, subrole…',
                      prefixIcon: const Icon(Icons.search, color: _muted),
                    ),
                    onChanged: (v) {
                      _onSearchChanged(v);
                      _searchTypeahead(v);
                    },
                  ),
                  if (_suggestions.isNotEmpty)
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 52,
                      child: Material(
                        elevation: 6,
                        borderRadius: BorderRadius.circular(12),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 300),
                          child: ListView.separated(
                            padding: EdgeInsets.zero,
                            shrinkWrap: true,
                            itemCount: _suggestions.length,
                            separatorBuilder: (context, index) => const Divider(height: 1),
                            itemBuilder: (context, i) {
                              final s = _suggestions[i];
                              final name = (s['full_name'] ?? '').toString();
                              final role = (s['role'] ?? s['category'] ?? '').toString();
                              final pos  = (s['position'] ?? '').toString();
                              final id   = (s['id'] ?? '').toString();

                              return ListTile(
                                dense: true,
                                leading: const Icon(Icons.person),
                                title: Text(name.isEmpty ? '(no name)' : name),
                                subtitle: Text([role, pos].where((e) => e.isNotEmpty).join(' • ')),
                                onTap: () {
                                  FocusScope.of(context).unfocus();
                                  setState(() => _suggestions = []);
                                  final pid = int.tryParse(id) ?? 0;
                                  if (pid <= 0) return;
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => ProfileDetailScreen(
                                        profileId: pid,
                                        fullName: name,
                                      ),
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // Role pill (read-only display of current scope — optional)
          _pillWrap(
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.badge_outlined, size: 16, color: _muted),
                  const SizedBox(width: 8),
                  Text(
                    widget.role.toUpperCase(),
                    style: const TextStyle(color: _text, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),

          _pillWrap(
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.work_outline, size: 16, color: _muted),
                  const SizedBox(width: 8),
                  Text(
                    widget.position,
                    style: const TextStyle(color: _text, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _profilesList() {
    return RefreshIndicator(
      onRefresh: () => _fetchVisibleProfiles(reset: true),
      child: ListView.builder(
        controller: _listCtl,
        itemCount: profiles.length,
        itemBuilder: (context, index) {
          final p = profiles[index];
          final fullName = (p['full_name'] ?? '').toString();
          final position = (p['position'] ?? '').toString();
          final subrole  = (p['subrole'] ?? '').toString();
          final role     = (p['role'] ?? '').toString();
          final zone     = (p['zone'] ?? '').toString();
          final id = p['id'] is int ? p['id'] as int : int.tryParse('${p['id']}') ?? 0;

          return Container(
            margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            decoration: _card(),
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Avatar
                CircleAvatar(
                  radius: 22,
                  backgroundColor: _primarySoft,
                  child: Text(
                    _initials(fullName),
                    style: const TextStyle(color: _primary, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 12),

                // Main info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Name + actions
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              fullName.isEmpty ? '(No name)' : fullName,
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: _text),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Tooltip(
                            message: 'View',
                            child: IconButton(
                              icon: const Icon(Icons.visibility, color: Color(0xFF3B82F6)),
                              onPressed: id <= 0
                                  ? null
                                  : () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => ProfileDetailScreen(
                                            profileId: id,
                                            fullName: fullName,
                                          ),
                                        ),
                                      );
                                    },
                            ),
                          ),
                          Tooltip(
                            message: 'Edit',
                            child: IconButton(
                              icon: const Icon(Icons.edit, color: Color(0xFFF59E0B)),
                              onPressed: id <= 0
                                  ? null
                                  : () async {
                                      FocusScope.of(context).unfocus();
                                      final res = await showModalBottomSheet<Map<String, dynamic>>(
                                        context: context,
                                        isScrollControlled: true,
                                        backgroundColor: Colors.transparent,
                                        builder: (_) {
                                          return ClipRRect(
                                            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                                            child: EditProfileSheet(
                                              baseUrl: baseUrl,
                                              profileId: id,
                                              currentUserRole: widget.role,
                                              currentUserPosition: widget.position,
                                            ),
                                          );
                                        },
                                      );
                                      if (res != null && (res['updated'] == true)) {
                                        _fetchVisibleProfiles(reset: true);
                                        _toast('Profile updated');
                                      }
                                    },
                            ),
                          ),
                          Tooltip(
                            message: 'Delete',
                            child: IconButton(
                              icon: const Icon(Icons.delete, color: Color(0xFFEF4444)),
                              onPressed: () => _toast('Delete not implemented yet.'),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 6),

                      // Chips
                      Wrap(
                        spacing: 8,
                        runSpacing: -6,
                        children: [
                          if (position.isNotEmpty)
                            _chip(position, const Color(0xFF2c5364)),
                          if (subrole.isNotEmpty)
                            _chip(subrole, const Color(0xFF203a43)),
                          if (zone.isNotEmpty)
                            _chip('Zone: $zone', const Color(0xFF0f2027)),
                        ],
                      ),

                      const SizedBox(height: 6),
                      Text('Department: $role', style: const TextStyle(color: _muted, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
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
}

// ---------------------------- Sidebar + Buttons ----------------------------
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
        borderRadius: BorderRadius.circular(10),
        boxShadow: [BoxShadow(color: colors.first.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, color: Colors.white),
        label: Text(label, style: const TextStyle(color: Colors.white)),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
            GestureDetector(onTap: onProfiles,    child: _navItem(Icons.people_outlined, 'Profiles', true)),
            const SizedBox(height: 16),
            GestureDetector(onTap: onReports,     child: _navItem(Icons.analytics_outlined, 'Reports', false)),

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
          Text(
            title,
            style: TextStyle(
              color: active ? Colors.white : Colors.white.withOpacity(0.7),
              fontSize: 16,
              fontWeight: active ? FontWeight.w600 : FontWeight.w400,
              letterSpacing: 0.5,
            ),
          ),
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
              Text(
                username,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
              Text(
                role,
                style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 10),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ]),
          ),
          Icon(Icons.settings, color: Colors.white.withOpacity(0.6), size: 16),
        ],
      ),
    );
  }
}

// ---------------------------- Helpers ----------------------------
// Split flat color list into triplets
extension on List<Color> {
  List<List<Color>> slices(int size) {
    final out = <List<Color>>[];
    for (var i = 0; i < length; i += size) {
      if (i + size <= length) out.add(sublist(i, i + size));
    }
    return out;
  }
}