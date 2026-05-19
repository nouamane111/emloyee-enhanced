import 'dart:ui';
import 'package:flutter/material.dart';
import 'assessment_list.dart';
import 'Profiles.dart';
import 'home.dart';
import 'ReportsScreen.dart';

class AssessmentCategoryScreen extends StatefulWidget {
  final String role;
  final String subrole;
  final String username;
  final String position;

  final String? nationalSupervisorId;
  final String? supervisorId;

  const AssessmentCategoryScreen({
    super.key,
    required this.role,
    required this.subrole,
    required this.username,
    required this.position,
    this.nationalSupervisorId,
    this.supervisorId,
  });

  @override
  State<AssessmentCategoryScreen> createState() =>
      _AssessmentCategoryScreenState();
}

class _AssessmentCategoryScreenState extends State<AssessmentCategoryScreen>
    with TickerProviderStateMixin {
  String? selectedCategory;
  String? selectedSubCategory;
  bool _isSidebarVisible = false;

  late AnimationController _gradientController;
  late AnimationController _cardController;
  late AnimationController _headerController;
  late AnimationController _sidebarController;

  late Animation<double> _gradientAnimation;
  late Animation<double> _cardStaggerAnimation;
  late Animation<double> _headerAnimation;
  late Animation<double> _sidebarAnimation;

  final List<List<Color>> gradientSets = const [
    [Color(0xFF003DA5), Color(0xFF005091), Color(0xFF74C8E8)],
    [Color(0xFF005091), Color(0xFF003DA5), Color(0xFF74C8E8)],
    [Color(0xFF1e3a8a), Color(0xFF3730a3), Color(0xFF4338ca)],
    [Color(0xFF0f172a), Color(0xFF1e293b), Color(0xFF334155)],
  ];

  int currentGradientIndex = 0;
  int nextGradientIndex = 1;

  final Map<String, List<String>> categoryMap = const {
    'SFP': ['LAMP', 'Direct retail', 'Indirect retail'],
    'CE': ['Brand representatives', 'Supervisor'],
    'CC': ['Sales representatives', 'Promoters'],
  };

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
  }

  void _initializeAnimations() {
    _gradientController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          setState(() {
            currentGradientIndex = nextGradientIndex;
            nextGradientIndex = (nextGradientIndex + 1) % gradientSets.length;
            _gradientController.forward(from: 0);
          });
        }
      });

    _gradientAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _gradientController, curve: Curves.easeInOut),
    );

    _sidebarController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _sidebarAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _sidebarController, curve: Curves.easeInOut),
    );

    _cardController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _cardStaggerAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _cardController, curve: Curves.easeOutBack),
    );

    _headerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _headerAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _headerController, curve: Curves.easeOut),
    );

    _gradientController.forward();

    Future.delayed(const Duration(milliseconds: 250), () {
      if (mounted) _headerController.forward();
    });

    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) _cardController.forward();
    });
  }

  @override
  void dispose() {
    _gradientController.dispose();
    _cardController.dispose();
    _headerController.dispose();
    _sidebarController.dispose();
    super.dispose();
  }

  void _toggleSidebar() {
    setState(() => _isSidebarVisible = !_isSidebarVisible);

    if (_isSidebarVisible) {
      _sidebarController.forward();
    } else {
      _sidebarController.reverse();
    }
  }

  String? _normalizeSfpSubrole(String? sub) {
    final s = (sub ?? '').toLowerCase().trim();

    if (s.isEmpty) return null;
    if (s == 'lamp') return 'LAMP';
    if (s == 'direct' || s == 'direct retail' || s == 'direct_retail') {
      return 'Direct retail';
    }
    if (s == 'indirect' || s == 'indirect retail' || s == 'indirect_retail') {
      return 'Indirect retail';
    }

    return null;
  }

  List<String> _getAllowedSubcategoriesFor(String category) {
    final cat = category.toUpperCase().trim();
    final userRole = widget.role.toUpperCase().trim();
    final userPos = widget.position.toLowerCase().trim();
    final userSub = widget.subrole;

    final all = categoryMap[cat] ?? const <String>[];

    if (userRole == 'ADMIN') return all;

    if (cat == 'SFP') {
      if (userPos == 'national supervisor' || userPos == 'supervisor') {
        final only = _normalizeSfpSubrole(userSub);
        return only != null ? [only] : all;
      }

      return all;
    }

    if (cat == 'CE') {
      if (userPos == 'channel manager') {
        return const ['Supervisor', 'Brand representatives'];
      }

      if (userPos == 'supervisor') {
        return const ['Brand representatives'];
      }

      return all;
    }

    return all;
  }

  List<String> _getAllowedCategories() {
    final userRole = widget.role.toUpperCase();

    if (userRole == 'ADMIN') {
      return const ['SFP', 'CE', 'CC'];
    }

    return [userRole];
  }

  void goToAssessmentListScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AssessmentListScreen(
          role: widget.role,
          subrole: widget.subrole,
          username: widget.username,
          position: widget.position,
          nationalSupervisorId: widget.nationalSupervisorId,
          supervisorId: widget.supervisorId,
          selectedCategory: selectedCategory ?? '',
          selectedSubCategory: selectedSubCategory ?? '',
        ),
      ),
    );
  }

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

  void navigateToAssessment() {}

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
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => ReportsScreen(
          username: widget.username,
          role: widget.role,
          subrole: widget.subrole,
          position: widget.position,
        ),
      ),
    );
  }

  IconData _iconForOption(String title) {
    switch (title.toUpperCase()) {
      case 'SFP':
        return Icons.storefront_rounded;
      case 'CE':
        return Icons.workspace_premium_rounded;
      case 'CC':
        return Icons.groups_rounded;
      case 'LAMP':
        return Icons.lightbulb_rounded;
      case 'DIRECT RETAIL':
        return Icons.point_of_sale_rounded;
      case 'INDIRECT RETAIL':
        return Icons.hub_rounded;
      case 'BRAND REPRESENTATIVES':
        return Icons.record_voice_over_rounded;
      case 'SUPERVISOR':
        return Icons.supervisor_account_rounded;
      case 'SALES REPRESENTATIVES':
        return Icons.badge_rounded;
      case 'PROMOTERS':
        return Icons.campaign_rounded;
      default:
        return Icons.assessment_rounded;
    }
  }

  String _descriptionForOption(String title) {
    switch (title.toUpperCase()) {
      case 'SFP':
        return 'Sales Force Platform assessment paths';
      case 'CE':
        return 'Commercial Excellence assessment paths';
      case 'CC':
        return 'Consumer Channel assessment paths';
      case 'LAMP':
        return 'LAMP-specific field assessment templates';
      case 'DIRECT RETAIL':
        return 'Direct retail assessment templates';
      case 'INDIRECT RETAIL':
        return 'Indirect retail assessment templates';
      case 'BRAND REPRESENTATIVES':
        return 'Brand representative evaluation flows';
      case 'SUPERVISOR':
        return 'Supervisor assessment templates';
      case 'SALES REPRESENTATIVES':
        return 'Sales representative evaluation flows';
      case 'PROMOTERS':
        return 'Promoter assessment templates';
      default:
        return 'Open available assessments';
    }
  }

  Widget _buildNavItem(IconData icon, String title, bool isActive) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: isActive ? Colors.white.withOpacity(0.18) : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        border: isActive
            ? Border.all(color: Colors.white.withOpacity(0.35))
            : null,
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: isActive ? Colors.white : Colors.white.withOpacity(0.72),
            size: 22,
          ),
          const SizedBox(width: 16),
          Text(
            title,
            style: TextStyle(
              color: isActive ? Colors.white : Colors.white.withOpacity(0.72),
              fontSize: 16,
              fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlassOptionCard(
    String title,
    VoidCallback onTap,
    List<Color> colors, {
    bool enabled = true,
  }) {
    final accent = colors[0];

    return AnimatedBuilder(
      animation: _cardStaggerAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _cardStaggerAnimation.value.clamp(0.0, 1.0),
          child: Opacity(
            opacity: _cardStaggerAnimation.value.clamp(0.0, 1.0),
            child: child,
          ),
        );
      },
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: MouseRegion(
          cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Container(
                width: 300,
                height: 210,
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  gradient: LinearGradient(
                    colors: [
                      Colors.white.withOpacity(enabled ? 0.78 : 0.35),
                      Colors.white.withOpacity(enabled ? 0.52 : 0.22),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border.all(
                    color: Colors.white.withOpacity(enabled ? 0.82 : 0.40),
                    width: 1.3,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: accent.withOpacity(enabled ? 0.16 : 0.05),
                      blurRadius: 30,
                      spreadRadius: 2,
                      offset: const Offset(0, 14),
                    ),
                    BoxShadow(
                      color: Colors.black.withOpacity(0.06),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 50,
                      width: 50,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            colors[0].withOpacity(0.95),
                            colors[2].withOpacity(0.90),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: colors[0].withOpacity(0.30),
                            blurRadius: 18,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Icon(
                        _iconForOption(title),
                        color: Colors.white,
                        size: 25,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF0F172A),
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: Text(
                        _descriptionForOption(title),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: const Color(0xFF334155).withOpacity(0.80),
                          fontSize: 13,
                          height: 1.35,
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
    );
  }

  Widget _buildSidebar(List<Color> colors) {
    return Transform.translate(
      offset: Offset(-280 * (1 - _sidebarAnimation.value), 0),
      child: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            width: 280,
            height: MediaQuery.of(context).size.height,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  colors[0].withOpacity(0.85),
                  colors[1].withOpacity(0.75),
                  colors[2].withOpacity(0.65),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border(
                right: BorderSide(
                  color: Colors.white.withOpacity(0.20),
                  width: 1,
                ),
              ),
              boxShadow: [
                BoxShadow(
                  color: colors[0].withOpacity(0.30),
                  blurRadius: 30,
                  spreadRadius: 5,
                  offset: const Offset(5, 0),
                ),
              ],
            ),
            child: SafeArea(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.30),
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.10),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.asset('assets/logo.png', width: 110),
                      ),
                    ),
                    const SizedBox(height: 32),
                    const Text(
                      'PHILIP MORRIS',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 17,
                        letterSpacing: 2.4,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'INTERNATIONAL',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.82),
                        fontSize: 13,
                        letterSpacing: 2.0,
                      ),
                    ),
                    const SizedBox(height: 42),
                    GestureDetector(
                      onTap: navigateToDashboard,
                      child: _buildNavItem(
                        Icons.dashboard_outlined,
                        'Dashboard',
                        false,
                      ),
                    ),
                    const SizedBox(height: 16),
                    GestureDetector(
                      onTap: navigateToAssessment,
                      child: _buildNavItem(
                        Icons.assessment_outlined,
                        'Assessments',
                        true,
                      ),
                    ),
                    const SizedBox(height: 16),
                    GestureDetector(
                      onTap: navigateToProfiles,
                      child: _buildNavItem(
                        Icons.people_outlined,
                        'Profiles',
                        false,
                      ),
                    ),
                    const SizedBox(height: 16),
                    GestureDetector(
                      onTap: navigateToReports,
                      child: _buildNavItem(
                        Icons.analytics_outlined,
                        'Reports',
                        false,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      margin: const EdgeInsets.only(bottom: 30),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.14),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.26),
                        ),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 18,
                            backgroundColor: Colors.white.withOpacity(0.26),
                            child: Text(
                              widget.username.isNotEmpty
                                  ? widget.username[0].toUpperCase()
                                  : 'U',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  widget.username,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                                Text(
                                  widget.role,
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.78),
                                    fontSize: 11,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMainContent(List<Color> colors) {
    final allowedCategories = _getAllowedCategories();
    final subcategories = selectedCategory != null
        ? _getAllowedSubcategoriesFor(selectedCategory!)
        : <String>[];

    final currentTitle = selectedCategory == null
        ? 'Select Assessment Category'
        : '$selectedCategory Assessment Paths';

    final currentSubtitle = selectedCategory == null
        ? 'Choose the assessment universe available for your role.'
        : 'Choose a subcategory to view templates and assessment history.';

    return Padding(
      padding: EdgeInsets.only(
        left: _isSidebarVisible ? 312 : 32,
        right: 32,
        top: 30,
        bottom: 30,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.70),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.80),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: colors[0].withOpacity(0.12),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: IconButton(
                      onPressed: _toggleSidebar,
                      icon: Icon(
                        _isSidebarVisible ? Icons.close : Icons.menu,
                        color: colors[0],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 18),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.72),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: Colors.white.withOpacity(0.82)),
                  boxShadow: [
                    BoxShadow(
                      color: colors[0].withOpacity(0.08),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.security_rounded,
                      color: colors[0],
                      size: 17,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${widget.position} • ${widget.role}',
                      style: const TextStyle(
                        color: Color(0xFF0F172A),
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: navigateToDashboard,
                icon: Icon(Icons.arrow_back_rounded, color: colors[0]),
                label: const Text('Dashboard'),
                style: TextButton.styleFrom(
                  foregroundColor: colors[0],
                ),
              ),
            ],
          ),
          const SizedBox(height: 42),
          AnimatedBuilder(
            animation: _headerAnimation,
            builder: (context, child) {
              return Opacity(
                opacity: _headerAnimation.value,
                child: Transform.translate(
                  offset: Offset(0, 20 * (1 - _headerAnimation.value)),
                  child: child,
                ),
              );
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  currentTitle,
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 38,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.6,
                  ),
                ),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Text(
                    currentSubtitle,
                    style: const TextStyle(
                      color: Color(0xFF475569),
                      fontSize: 16,
                      height: 1.55,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 42),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (selectedCategory == null) ...[
                    _sectionLabel(
                      'Available categories',
                      'Pick the assessment domain you want to open.',
                    ),
                    const SizedBox(height: 24),
                  Center(
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 26,
                      runSpacing: 26,
                      children: allowedCategories.map((category) {
                        return _buildGlassOptionCard(
                          category,
                          () {
                            setState(() {
                              selectedCategory = category;
                            });
                          },
                          colors,
                        );
                      }).toList(),
                    ),
                      ),
                  ],
                  if (selectedCategory != null && subcategories.isNotEmpty) ...[
                    Row(
                      children: [
                        _glassIconButton(
                          icon: Icons.arrow_back_rounded,
                          colors: colors,
                          onTap: () {
                            setState(() {
                              selectedCategory = null;
                              selectedSubCategory = null;
                            });
                          },
                        ),
                        const SizedBox(width: 14),
                        _sectionLabel(
                          '$selectedCategory subcategories',
                          'Choose the exact field path for this assessment.',
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                          Center(
                            child: Wrap(
                              alignment: WrapAlignment.center,
                              spacing: 26,
                              runSpacing: 26,
                              children: subcategories.map((subcategory) {
                        return _buildGlassOptionCard(
                          subcategory,
                          () {
                            setState(() {
                              selectedSubCategory = subcategory;
                            });
                            goToAssessmentListScreen();
                          },
                          colors,
                        );
                      }).toList(),
                    ),
                          ),
                  ],
                  if (selectedCategory != null && subcategories.isEmpty) ...[
                    Row(
                      children: [
                        _glassIconButton(
                          icon: Icons.arrow_back_rounded,
                          colors: colors,
                          onTap: () {
                            setState(() {
                              selectedCategory = null;
                            });
                          },
                        ),
                        const SizedBox(width: 14),
                        _sectionLabel(
                          'Proceed to $selectedCategory',
                          'Open the available assessments for this category.',
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                        child: ElevatedButton.icon(
                          onPressed: goToAssessmentListScreen,
                          icon: const Icon(Icons.open_in_new_rounded),
                          label: const Text('View Assessments'),
                          style: ElevatedButton.styleFrom(
                            foregroundColor: Colors.white,
                            backgroundColor: colors[0],
                            padding: const EdgeInsets.symmetric(
                              horizontal: 28,
                              vertical: 18,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Color(0xFF0F172A),
            fontSize: 19,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          subtitle,
          style: const TextStyle(
            color: Color(0xFF64748B),
            fontSize: 13,
          ),
        ),
      ],
    );
  }

  Widget _glassIconButton({
    required IconData icon,
    required List<Color> colors,
    required VoidCallback onTap,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(15),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.72),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: Colors.white.withOpacity(0.82)),
            boxShadow: [
              BoxShadow(
                color: colors[0].withOpacity(0.12),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: IconButton(
            onPressed: onTap,
            icon: Icon(icon, color: colors[0]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedBuilder(
        animation: _gradientAnimation,
        builder: (context, child) {
          final colors = List.generate(3, (i) {
            return Color.lerp(
              gradientSets[currentGradientIndex][i],
              gradientSets[nextGradientIndex][i],
              _gradientAnimation.value,
            )!;
          });

          return Stack(
            children: [
              Positioned.fill(
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Color(0xFFEFF6FF),
                        Color(0xFFF8FAFC),
                        Color(0xFFFFFFFF),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(-0.76, -0.72),
                      radius: 1.15,
                      colors: [
                        const Color(0xFF74C8E8).withOpacity(0.20),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(0.88, -0.55),
                      radius: 1.2,
                      colors: [
                        colors[0].withOpacity(0.10),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              _buildMainContent(colors),
              AnimatedBuilder(
                animation: _sidebarAnimation,
                builder: (context, child) => _buildSidebar(colors),
              ),
              if (_isSidebarVisible)
                GestureDetector(
                  onTap: _toggleSidebar,
                  child: Container(
                    color: Colors.black.withOpacity(0.18),
                    margin: const EdgeInsets.only(left: 280),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}