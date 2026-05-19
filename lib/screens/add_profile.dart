// lib/screens/add_profile.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'api_helper.dart';
import 'home.dart';
import 'profiles.dart';
import 'assessment_category.dart';
import 'package:intl/intl.dart';

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

class AddProfileScreen extends StatefulWidget {
  final String role;
  final String subrole;
  final String username;
  final String position;
  final String? nationalSupervisorId;
  final String? supervisorId;

  const AddProfileScreen({
    super.key,
    required this.role,
    required this.subrole,
    required this.username,
    required this.position,
    this.nationalSupervisorId,
    this.supervisorId,
  });

  @override
  State<AddProfileScreen> createState() => _AddProfileScreenState();
}

class _AddProfileScreenState extends State<AddProfileScreen>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();

  // Controllers
  final TextEditingController _fullNameController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _dateJoinedController = TextEditingController();
  final TextEditingController _supervisorNameController = TextEditingController();
  final TextEditingController _nationalSupervisorNameController = TextEditingController();
  final TextEditingController _zoneController = TextEditingController();

  // State
  String? selectedRole;
  String? selectedSubrole;
  String? selectedPosition;

  // ---- Helpers ----
  bool _isOneOf(String? value, List<String> options) {
    final v = (value ?? '').trim().toLowerCase();
    for (final o in options) {
      if (v == o.toLowerCase()) return true;
    }
    return false;
  }

  // SFP positions that need BOTH supervisor & national supervisor names
  bool get _sfpNeedsBothSupers =>
      selectedRole == 'SFP' &&
      _isOneOf(selectedPosition, [
        'Sales expert',
        'Brand ambassador',
        'Brand representative',
        'Brand representatives',
      ]);

  // ====== ACCOUNT RULES ======
  // - Admin => requires account
  // - CE + Supervisor => requires account
  // - CE + Brand representatives => NO account
  // - SFP + (Sales expert | Brand ambassador | Brand representative[s]) => NO account
  // - Other SFP positions => requires account
  bool get requiresAccount {
    final role = (selectedRole ?? '').trim();
    final pos = (selectedPosition ?? '').trim().toLowerCase();

    if (role == 'Admin') return true;

    if (role == 'CE') {
      if (pos == 'supervisor') return true;
      if (pos == 'brand representatives') return false;
    }

    if (role == 'SFP') {
      if (pos == 'sales expert' ||
          pos == 'brand ambassador' ||
          pos == 'brand representative' ||
          pos == 'brand representatives') {
        return false;
      }
      return true;
    }
    return false;
  }

  // Visibility rules
  bool get showSupervisorField =>
      _sfpNeedsBothSupers ||
      (selectedRole == 'CE' && _isOneOf(selectedPosition, ['Brand representatives']));

  // CE Brand reps: NO national supervisor (per your last change)
  bool get showNationalField =>
      selectedRole == 'SFP' &&
      (_sfpNeedsBothSupers || _isOneOf(selectedPosition, ['Supervisor']));

  List<String> getRoleOptions() => ['Admin', 'SFP', 'CC', 'CE'];

  List<String> getSubroleOptions() {
    if (selectedRole == 'Admin') return ['ALL'];
    if (selectedRole == 'SFP') return ['Indirect retail', 'Direct retail', 'LAMP'];
    if (selectedRole == 'CC') return ['Sales representatives', 'Promoters'];
    if (selectedRole == 'CE') return ['Brand representatives', 'Supervisor'];
    return ['none'];
  }

  List<String> getPositionOptions() {
    if (selectedRole == 'Admin') return ['ALL'];
    if (selectedRole == 'SFP') {
      return [
        'Sales expert',
        'Supervisor',
        'National supervisor',
        'Channel manager',
        'Brand representatives',
        'Brand ambassador',
      ];
    }
    if (selectedRole == 'CC') return ['Sales representatives', 'Promoters'];
    if (selectedRole == 'CE') return ['Brand representatives', 'Supervisor'];
    return [];
  }

  // ---------------- NAV ----------------
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

  // ---------------- DATE PICKER ----------------
  Future<void> selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      _dateJoinedController.text = DateFormat('yyyy-MM-dd').format(picked);
    }
  }

  // ---------------- SUBMIT ----------------
Future<void> submitProfile() async {
  if (!_formKey.currentState!.validate()) return;

  // Extra validation aligned with rules
  if (selectedRole == 'SFP') {
    if (_sfpNeedsBothSupers) {
      if (_supervisorNameController.text.isEmpty ||
          _nationalSupervisorNameController.text.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'This position requires Supervisor and National supervisor names.',
            ),
          ),
        );
        return;
      }
    } else if (_isOneOf(selectedPosition, ['Supervisor'])) {
      if (_nationalSupervisorNameController.text.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Supervisor requires National supervisor name.'),
          ),
        );
        return;
      }
    }
  }

  // CE Brand representatives require Supervisor name
  if (selectedRole == 'CE' &&
      _isOneOf(selectedPosition, ['Brand representatives'])) {
    if (_supervisorNameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('CE Brand representatives require a Supervisor name.'),
        ),
      );
      return;
    }
  }

  final body = {
    'role': selectedRole,
    'subrole': selectedSubrole,
    'position': selectedPosition,
    'full_name': _fullNameController.text.trim(),
    'username': requiresAccount ? _usernameController.text.trim() : null,
    'password': requiresAccount ? _passwordController.text.trim() : null,
    'supervisor_name':
        showSupervisorField ? _supervisorNameController.text.trim() : null,
    'national_supervisor_name': showNationalField
        ? _nationalSupervisorNameController.text.trim()
        : null,
    'date_joined':
        _dateJoinedController.text.isNotEmpty ? _dateJoinedController.text : null,
    'zone': _zoneController.text.trim(),
  };

  try {
    final response = await ApiHelper.post('/add_profile', body);

    if (!mounted) return;

    if (response.statusCode == 401) {
      await ApiHelper.clearToken();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Session expired. Please log in again.'),
        ),
      );
      return;
    }

    if (response.statusCode == 200) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile added successfully!')),
      );

      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to add profile: ${response.body}')),
      );
    }
  } catch (e) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Connection error: $e')),
    );
  }
}

  // ---------------- INPUTS ----------------
  InputDecoration _dec(String label, {Widget? suffixIcon}) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: _muted),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: _primary),
        ),
        suffixIcon: suffixIcon,
      );

  Widget _text(String label, TextEditingController c,
      {bool isPassword = false, String? Function(String?)? validator}) {
    return TextFormField(
      controller: c,
      obscureText: isPassword,
      decoration: _dec(label),
      validator: validator ?? (v) => (v == null || v.isEmpty) ? 'Required' : null,
    );
  }

  BoxDecoration _card() => BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_cardRadius),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [BoxShadow(color: const Color(0x0D2563EB), blurRadius: 12, offset: const Offset(0, 6))],
      );

  Widget _sectionTitle(IconData icon, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: _primarySoft,
            ),
            child: Icon(icon, size: 16, color: _primary),
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 16,
              color: Color(0xFF0F172A),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------- GRADIENT HEADER / SIDEBAR (match Profiles) ----------------
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
    _fullNameController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _dateJoinedController.dispose();
    _supervisorNameController.dispose();
    _nationalSupervisorNameController.dispose();
    _zoneController.dispose();
    _gradientController.dispose();
    super.dispose();
  }

  List<Color> _lerp3(List<Color> a, List<Color> b, double t) => [
        Color.lerp(a[0], b[0], t) ?? a[0],
        Color.lerp(a[1], b[1], t) ?? a[1],
        Color.lerp(a[2], b[2], t) ?? a[2],
      ];

  BoxDecoration _panel() => BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_cardRadius),
        boxShadow: _cardShadow,
        gradient: const LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [Color(0xFFFFFFFF), Color(0xFFF9FBFF)],
        ),
      );

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
                right: 20, top: 20, bottom: 20,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top bar
                  Row(
                    children: [
                      _AnimatedChipButton(
                        colors: colors,
                        icon: _isSidebarVisible ? Icons.close : Icons.menu,
                        onTap: () => setState(() => _isSidebarVisible = !_isSidebarVisible),
                      ),
                      const SizedBox(width: 20),
                      Icon(Icons.person_add_alt_1_outlined, color: colors[0], size: 20),
                      const SizedBox(width: 8),
                      Text('Add Profile', style: TextStyle(color: colors[0], fontSize: 16)),
                      const Spacer(),
                      _GradientActionBtn(
                        colors: [colors[1], colors[2]],
                        icon: Icons.check,
                        label: 'Submit',
                        onTap: submitProfile,
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
                      'Create a new member',
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
                    'Follow hierarchy and account rules',
                    style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                  ),

                  const SizedBox(height: 20),

                  // Content panel (form)
                  Expanded(
                    child: Container(
                      decoration: _panel(),
                      padding: const EdgeInsets.all(16),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 820),
                          child: Form(
                            key: _formKey,
                            child: ListView(
                              children: [
                                // -------- Identity --------
                                Container(
                                  decoration: _card(),
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      _sectionTitle(Icons.person_outline, 'Identity'),
                                      _text('Full Name', _fullNameController),
                                      const SizedBox(height: 12),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: DropdownButtonFormField<String>(
                                              decoration: _dec('Role'),
                                              value: selectedRole,
                                              items: getRoleOptions()
                                                  .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                                                  .toList(),
                                              onChanged: (v) => setState(() {
                                                selectedRole = v;
                                                selectedSubrole = null;
                                                selectedPosition = null;
                                              }),
                                              validator: (v) => v == null ? 'Please select a role' : null,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: DropdownButtonFormField<String>(
                                              decoration: _dec('Subrole'),
                                              value: selectedSubrole,
                                              items: getSubroleOptions()
                                                  .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                                                  .toList(),
                                              onChanged: (v) => setState(() => selectedSubrole = v),
                                              validator: (v) => v == null ? 'Please select a subrole' : null,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      DropdownButtonFormField<String>(
                                        decoration: _dec('Position'),
                                        value: selectedPosition,
                                        items: getPositionOptions()
                                            .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                                            .toList(),
                                        onChanged: (v) => setState(() => selectedPosition = v),
                                        validator: (v) => v == null ? 'Please select a position' : null,
                                      ),
                                    ],
                                  ),
                                ),

                                const SizedBox(height: 16),

                                // -------- Organization --------
                                Container(
                                  decoration: _card(),
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      _sectionTitle(Icons.apartment_outlined, 'Organization'),
                                      TextFormField(
                                        controller: _zoneController,
                                        decoration: _dec('Zone'),
                                        validator: (v) => (v == null || v.isEmpty) ? 'Zone is required' : null,
                                      ),
                                      const SizedBox(height: 12),
                                      TextFormField(
                                        controller: _dateJoinedController,
                                        readOnly: true,
                                        onTap: selectDate,
                                        decoration: _dec('Date Joined (optional)', suffixIcon: const Icon(Icons.calendar_today)),
                                      ),
                                      if (showSupervisorField) ...[
                                        const SizedBox(height: 12),
                                        _text("Supervisor's Name", _supervisorNameController),
                                      ],
                                      if (showNationalField) ...[
                                        const SizedBox(height: 12),
                                        _text("National Supervisor's Name", _nationalSupervisorNameController),
                                      ],
                                    ],
                                  ),
                                ),

                                const SizedBox(height: 16),

                                // -------- Account (conditional) --------
                                Container(
                                  decoration: _card(),
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          _sectionTitle(Icons.lock_outline, 'Account'),
                                          const Spacer(),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                            decoration: BoxDecoration(
                                              color: requiresAccount ? _primarySoft : Colors.grey.shade200,
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              requiresAccount ? 'Required' : 'Not required',
                                              style: TextStyle(
                                                color: requiresAccount ? _primary : Colors.grey.shade700,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      if (requiresAccount) ...[
                                        _text('Username', _usernameController, validator: (v) {
                                          if (!requiresAccount) return null;
                                          return (v == null || v.isEmpty) ? 'Required' : null;
                                        }),
                                        const SizedBox(height: 12),
                                        _text('Password', _passwordController, isPassword: true, validator: (v) {
                                          if (!requiresAccount) return null;
                                          return (v == null || v.isEmpty) ? 'Required' : null;
                                        }),
                                      ] else
                                        const Text(
                                          'Based on the selected Role/Position, an account is not required.',
                                          style: TextStyle(color: _muted, fontSize: 12),
                                        ),
                                    ],
                                  ),
                                ),

                                const SizedBox(height: 20),

                                // -------- Submit --------
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    onPressed: submitProfile,
                                    icon: const Icon(Icons.check_circle_outline),
                                    label: const Text('Submit Profile', style: TextStyle(fontWeight: FontWeight.bold)),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: _primary,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 16),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      shadowColor: _primary.withOpacity(0.25),
                                      elevation: 3,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Sidebar (same look as Profiles screen)
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
            GestureDetector(onTap: onProfiles,    child: _navItem(Icons.people_outlined, 'Profiles', false)),
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