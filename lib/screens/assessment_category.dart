import 'package:flutter/material.dart';
import 'assessment_list.dart';
import 'Profiles.dart';
import 'home.dart';

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
  State<AssessmentCategoryScreen> createState() => _AssessmentCategoryScreenState();
}

class _AssessmentCategoryScreenState extends State<AssessmentCategoryScreen> with TickerProviderStateMixin {
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

  // Same gradient sets you used across the app
  final List<List<Color>> gradientSets = const [
    [Color(0xFF1e3a8a), Color(0xFF3730a3), Color(0xFF4338ca)],
    [Color(0xFF0f172a), Color(0xFF1e293b), Color(0xFF334155)],
    [Color(0xFF1a202c), Color(0xFF2d3748), Color(0xFF4a5568)],
    [Color(0xFF2563eb), Color(0xFF3b82f6), Color(0xFF60a5fa)],
  ];

  int currentGradientIndex = 0;
  int nextGradientIndex = 1;

  // Base maps (full set); we will filter from these by rules
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
      duration: const Duration(milliseconds: 1500),
    );
    _cardStaggerAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _cardController, curve: Curves.elasticOut),
    );

    _headerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _headerAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _headerController, curve: Curves.easeOut),
    );

    _gradientController.forward();
    Future.delayed(const Duration(milliseconds: 300), () => _headerController.forward());
    Future.delayed(const Duration(milliseconds: 600), () => _cardController.forward());
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

  // ---------- NEW HELPERS (rules you requested) ----------

  // Normalize SFP subrole labels coming from the user profile to our display names
  String? _normalizeSfpSubrole(String? sub) {
    final s = (sub ?? '').toLowerCase().trim();
    if (s.isEmpty) return null;
    if (s == 'lamp') return 'LAMP';
    if (s == 'direct' || s == 'direct retail' || s == 'direct_retail') return 'Direct retail';
    if (s == 'indirect' || s == 'indirect retail' || s == 'indirect_retail') return 'Indirect retail';
    return null; // unknown -> show all SFP subcats
  }

  // Which subcategories are allowed for the current user when a category is selected
  List<String> _getAllowedSubcategoriesFor(String category) {
    final cat = category.toUpperCase().trim();
    final userRole = widget.role.toUpperCase().trim();
    final userPos  = widget.position.toLowerCase().trim();
    final userSub  = widget.subrole; // keep original, normalize only for SFP

    // Pull the full list
    final all = categoryMap[cat] ?? const <String>[];

    // Admin: everything
    if (userRole == 'ADMIN') return all;

    // SFP rules
    if (cat == 'SFP') {
      if (userPos == 'national supervisor' || userPos == 'supervisor') {
        final only = _normalizeSfpSubrole(userSub);
        return only != null ? [only] : all;
      }
      // channel manager or others in SFP -> all 3
      return all;
    }

    // CE rules
    if (cat == 'CE') {
      if (userPos == 'channel manager') {
        // CM in CE can access both Supervisor & Brand representatives
        return const ['Supervisor', 'Brand representatives'];
      }
      if (userPos == 'supervisor') {
        // Supervisor in CE -> Brand representatives only
        return const ['Brand representatives'];
      }
      return all;
    }

    // CC: no filters
    return all;
  }

  // Categories visible to the user (Admin: all; others: only their role)
  List<String> _getAllowedCategories() {
    final userRole = widget.role.toUpperCase();
    if (userRole == 'ADMIN') {
      return const ['SFP', 'CE', 'CC'];
    } else {
      return [userRole]; // only their own field
    }
  }

  // ---------- Navigation ----------

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

  void navigateToAssessment() {/* already here */}

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

  // ---------- UI helpers ----------

  Widget _buildNavItem(IconData icon, String title, bool isActive) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: isActive ? Colors.white.withOpacity(0.15) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: isActive ? Border.all(color: Colors.white.withOpacity(0.3)) : null,
      ),
      child: Row(
        children: [
          Icon(icon, color: isActive ? Colors.white : Colors.white.withOpacity(0.7), size: 22),
          const SizedBox(width: 16),
          Text(
            title,
            style: TextStyle(
              color: isActive ? Colors.white : Colors.white.withOpacity(0.7),
              fontSize: 16,
              fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOptionBox(String title, VoidCallback onTap, {bool enabled = true}) {
    return AnimatedBuilder(
      animation: _cardStaggerAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _cardStaggerAnimation.value,
          child: GestureDetector(
            onTap: enabled ? onTap : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
              width: 180,
              height: 140,
              decoration: BoxDecoration(
                gradient: enabled
                    ? LinearGradient(
                        colors: [
                          gradientSets[currentGradientIndex][0],
                          gradientSets[currentGradientIndex][1],
                          gradientSets[currentGradientIndex][2],
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : const LinearGradient(
                        colors: [Colors.grey, Colors.grey],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: enabled ? Colors.white : Colors.black38,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final allowedCategories = _getAllowedCategories();
    final subcategories = selectedCategory != null
        ? _getAllowedSubcategoriesFor(selectedCategory!)
        : <String>[];

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
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
              // Main content
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
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [colors[0], colors[1]],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: colors[0].withOpacity(0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: IconButton(
                            onPressed: _toggleSidebar,
                            icon: Icon(_isSidebarVisible ? Icons.close : Icons.menu, color: Colors.white),
                          ),
                        ),
                        const SizedBox(width: 20),
                        Image.asset('assets/logo.png', height: 36),
                        const SizedBox(width: 16),
                        ShaderMask(
                          shaderCallback: (bounds) => LinearGradient(
                            colors: [colors[0], colors[1]],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ).createShader(bounds),
                          child: const Text(
                            'Assessment Categories',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 40),

                    // Header
                    AnimatedBuilder(
                      animation: _headerAnimation,
                      builder: (context, child) {
                        return Opacity(
                          opacity: _headerAnimation.value,
                          child: Transform.translate(
                            offset: Offset(0, 20 * (1 - _headerAnimation.value)),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ShaderMask(
                                  shaderCallback: (bounds) => LinearGradient(
                                    colors: [colors[0], colors[1]],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ).createShader(bounds),
                                  child: const Text(
                                    'Select Assessment Category',
                                    style: TextStyle(
                                      fontSize: 32,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Choose from your available assessment categories',
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 16,
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),

                    const SizedBox(height: 40),

                    // Categories & Subcategories
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (selectedCategory == null) ...[
                              Text(
                                'Available Categories',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w600,
                                  color: colors[0],
                                ),
                              ),
                              const SizedBox(height: 24),
                              Center(
                                child: Wrap(
                                  spacing: 20,
                                  runSpacing: 20,
                                  children: allowedCategories.map((category) {
                                    return _buildOptionBox(category, () {
                                      setState(() {
                                        selectedCategory = category;
                                      });
                                    });
                                  }).toList(),
                                ),
                              ),
                            ],

                            if (selectedCategory != null && subcategories.isNotEmpty) ...[
                              Row(
                                children: [
                                  IconButton(
                                    onPressed: () {
                                      setState(() {
                                        selectedCategory = null;
                                        selectedSubCategory = null;
                                      });
                                    },
                                    icon: Icon(Icons.arrow_back, color: colors[0]),
                                  ),
                                  Text(
                                    '$selectedCategory Subcategories',
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w600,
                                      color: colors[0],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 24),
                              Center(
                                child: Wrap(
                                  spacing: 20,
                                  runSpacing: 20,
                                  children: subcategories.map((subcategory) {
                                    return _buildOptionBox(subcategory, () {
                                      setState(() {
                                        selectedSubCategory = subcategory;
                                      });
                                      goToAssessmentListScreen();
                                    });
                                  }).toList(),
                                ),
                              ),
                            ],

                            if (selectedCategory != null && subcategories.isEmpty) ...[
                              Row(
                                children: [
                                  IconButton(
                                    onPressed: () {
                                      setState(() {
                                        selectedCategory = null;
                                      });
                                    },
                                    icon: Icon(Icons.arrow_back, color: colors[0]),
                                  ),
                                  Text(
                                    'Proceeding to $selectedCategory Assessments',
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w600,
                                      color: colors[0],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 24),
                              Center(
                                child: ElevatedButton(
                                  onPressed: goToAssessmentListScreen,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: colors[0],
                                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: const Text(
                                    'View Assessments',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
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
              ),

              // Sidebar
              AnimatedBuilder(
                animation: _sidebarAnimation,
                builder: (context, child) {
                  return Transform.translate(
                    offset: Offset(-280 * (1 - _sidebarAnimation.value), 0),
                    child: Container(
                      width: 280,
                      height: MediaQuery.of(context).size.height,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: colors,
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          transform: GradientRotation(_gradientAnimation.value * 0.15),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: colors[0].withOpacity(0.3),
                            blurRadius: 20,
                            spreadRadius: 5,
                            offset: const Offset(5, 0),
                          ),
                        ],
                      ),
                      child: SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
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
                              const Text(
                                'PHILIP MORRIS',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                  letterSpacing: 2.2,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'INTERNATIONAL',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.85),
                                  fontSize: 12,
                                  letterSpacing: 1.8,
                                ),
                              ),
                              const SizedBox(height: 36),
                              GestureDetector(
                                onTap: navigateToDashboard,
                                child: _buildNavItem(Icons.dashboard_outlined, 'Dashboard', false),
                              ),
                              const SizedBox(height: 16),
                              GestureDetector(
                                onTap: navigateToAssessment,
                                child: _buildNavItem(Icons.assessment_outlined, 'Assessments', true),
                              ),
                              const SizedBox(height: 16),
                              GestureDetector(
                                onTap: navigateToProfiles,
                                child: _buildNavItem(Icons.people_outlined, 'Profiles', false),
                              ),
                              const SizedBox(height: 16),
                              GestureDetector(
                                onTap: navigateToReports,
                                child: _buildNavItem(Icons.analytics_outlined, 'Reports', false),
                              ),
                              const Spacer(),
                              Container(
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
                                        widget.username.isNotEmpty ? widget.username[0].toUpperCase() : 'U',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            widget.username,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w600,
                                              fontSize: 12,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                            maxLines: 1,
                                          ),
                                          Text(
                                            widget.role,
                                            style: TextStyle(
                                              color: Colors.white.withOpacity(0.7),
                                              fontSize: 10,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                            maxLines: 1,
                                          ),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      onPressed: () {},
                                      icon: Icon(Icons.settings, color: Colors.white.withOpacity(0.9), size: 16),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),

              if (_isSidebarVisible)
                GestureDetector(
                  onTap: _toggleSidebar,
                  child: Container(
                    color: Colors.black.withOpacity(0.3),
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