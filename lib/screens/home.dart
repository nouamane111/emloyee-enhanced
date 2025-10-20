import 'package:flutter/material.dart';
import 'dart:math';
import 'assessment_category.dart';
import 'Profiles.dart';
import 'ReportsScreen.dart';

class homeScreen extends StatefulWidget {
  final String role;
  final String subrole;
  final String username;
  final String position;
  
  final String? nationalSupervisorId;
  final String? supervisorId;
  //final int? profileId;
  //final String? fullname;


  const homeScreen({
    super.key,
    required this.role,
    required this.subrole,
    required this.username,
    required this.position,
   
    this.nationalSupervisorId,
    this.supervisorId,
    //required this.profileId,
    //required this.fullname,
  });
  


  @override
  State<homeScreen> createState() => _homeScreenState();
}

class _homeScreenState extends State<homeScreen> with TickerProviderStateMixin {
  late AnimationController _gradientController;
  late AnimationController _cardController;
  late AnimationController _headerController;
  
  late Animation<double> _gradientAnimation;
  late Animation<double> _cardStaggerAnimation;
  late Animation<double> _headerAnimation;

  // Smoothened gradient colors
  final List<List<Color>> gradientSets = [
    [Color(0xFF1e3a8a), Color(0xFF3730a3), Color(0xFF4338ca)], // Professional blues
    [Color(0xFF0f172a), Color(0xFF1e293b), Color(0xFF334155)], // Elegant grays
    [Color(0xFF1a202c), Color(0xFF2d3748), Color(0xFF4a5568)], // Sophisticated darks
    [Color(0xFF2563eb), Color(0xFF3b82f6), Color(0xFF60a5fa)], // Modern blues
  ];

  int currentGradientIndex = 0;
  int nextGradientIndex = 1;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
  }

  void _initializeAnimations() {
    // Super fast gradient animation
    _gradientController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500), // Super fast: 2.5 seconds
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

    // Card stagger animation
    _cardController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _cardStaggerAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _cardController, curve: Curves.elasticOut),
    );

    // Header typing animation
    _headerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _headerAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _headerController, curve: Curves.easeOut),
    );

    // Start animations
    _gradientController.forward();
    Future.delayed(const Duration(milliseconds: 300), () {
      _headerController.forward();
    });
    Future.delayed(const Duration(milliseconds: 600), () {
      _cardController.forward();
    });
  }

  @override
  void dispose() {
    _gradientController.dispose();
    _cardController.dispose();
    _headerController.dispose();
    super.dispose();
  }

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
          Icon(
            icon,
            color: isActive ? Colors.white : Colors.white.withOpacity(0.7),
            size: 22,
          ),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: AnimatedBuilder(
        animation: _gradientAnimation,
        builder: (context, child) {
          // Interpolate gradient colors
          final colors = List.generate(3, (i) {
            return Color.lerp(
              gradientSets[currentGradientIndex][i],
              gradientSets[nextGradientIndex][i],
              _gradientAnimation.value,
            )!;
          });

          return Row(
            children: [
              // Clean Sidebar with only Dashboard and Settings
              Container(
                width: 280,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: colors,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    transform: GradientRotation(_gradientAnimation.value * 0.15), // Slightly faster rotation
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
                    padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20), // Reduced vertical padding
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Bigger Static Philip Morris Logo
                        Container(
                          padding: const EdgeInsets.all(20), // Reduced padding
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white.withOpacity(0.2)),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.asset('assets/logo.png', width: 90), // Logo size
                          ),
                        ),
                        
                        const SizedBox(height: 24), // Reduced spacing
                        
                        // Enhanced Philip Morris International title - smaller as requested
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ShaderMask(
                              shaderCallback: (bounds) => LinearGradient(
                                colors: [Colors.white, Colors.white.withOpacity(0.9)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ).createShader(bounds),
                              child: const Text(
                                'PHILIP MORRIS',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16, // Size
                                  letterSpacing: 2.2,
                                ),
                              ),
                            ),
                            const SizedBox(height: 4), // Reduced spacing
                            ShaderMask(
                              shaderCallback: (bounds) => LinearGradient(
                                colors: [Colors.white.withOpacity(0.85), Colors.white.withOpacity(0.65)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ).createShader(bounds),
                              child: const Text(
                                'INTERNATIONAL',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w400,
                                  fontSize: 12, // Size
                                  letterSpacing: 1.8,
                                ),
                              ),
                            ),
                          ],
                        ),
                        
                        const SizedBox(height: 36), // Reduced spacing
                        
                        // Clean Navigation - Only Dashboard and Settings
                        _buildNavItem(Icons.dashboard_outlined, 'Dashboard', true),
                        const SizedBox(height: 16), // Reduced spacing
                        
                        const Spacer(),
                        
                        // User info section with settings icon - Fixed overflow
                        Container(
                          margin: const EdgeInsets.only(bottom: 30), // Increased bottom margin to prevent overflow
                          padding: const EdgeInsets.all(10), // Reduced padding
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white.withOpacity(0.2)),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 16, // Slightly smaller
                                backgroundColor: Colors.white.withOpacity(0.2),
                                child: Text(
                                  widget.username.isNotEmpty ? widget.username[0].toUpperCase() : 'U',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12, // Smaller font
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8), // Reduced spacing
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
                                        fontSize: 12, // Smaller font
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                    ),
                                    Text(
                                      widget.role,
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.7),
                                        fontSize: 10, // Smaller font
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

              // Main Content Area
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(32.0), // Reduced padding to prevent card overflow
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Animated Header with restored user info
                      AnimatedBuilder(
                        animation: _headerAnimation,
                        builder: (context, child) {
                          return Opacity(
                            opacity: _headerAnimation.value,
                            child: Transform.translate(
                              offset: Offset(0, 20 * (1 - _headerAnimation.value)),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        ShaderMask(
                                          shaderCallback: (bounds) => LinearGradient(
                                            colors: [
                                              colors[0],
                                              colors[1],
                                            ],
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                          ).createShader(bounds),
                                          child: Text(
                                            'Welcome, ${widget.username}',
                                            style: const TextStyle(
                                              fontSize: 28,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white,
                                              letterSpacing: 0.5,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          '${widget.position} - ${widget.role} - ${widget.subrole}',
                                          style: TextStyle(
                                            color: Colors.grey[600],
                                            fontSize: 16,
                                            fontWeight: FontWeight.w400,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  
                                  // Enhanced logout button
                                  Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12),
                                      gradient: LinearGradient(
                                        colors: [colors[0], colors[1]],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: colors[0].withOpacity(0.3),
                                          blurRadius: 15,
                                          spreadRadius: 2,
                                          offset: const Offset(0, 5),
                                        ),
                                      ],
                                    ),
                                    child: ElevatedButton.icon(
                                      onPressed: () => Navigator.pushReplacementNamed(context, '/'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.transparent,
                                        shadowColor: Colors.transparent,
                                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                      ),
                                      icon: const Icon(Icons.logout, color: Colors.white, size: 20),
                                      label: const Text(
                                        'Logout',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),

                      const SizedBox(height: 40), // Reduced spacing

                      // Dashboard Cards with gradient-matched colors - Fixed overflow
                      Expanded(
                        child: AnimatedBuilder(
                          animation: _cardStaggerAnimation,
                          builder: (context, child) {
                            return LayoutBuilder(
                              builder: (context, constraints) {
                                // Calculate responsive card sizing to prevent overflow
                                double availableWidth = constraints.maxWidth;
                                double cardSpacing = 20;
                                double cardWidth = (availableWidth - (2 * cardSpacing)) / 3;
                                double cardHeight = cardWidth * 0.8; // Maintain aspect ratio
                                
                                return GridView.count(
                                  crossAxisCount: 3,
                                  crossAxisSpacing: cardSpacing,
                                  mainAxisSpacing: cardSpacing,
                                  childAspectRatio: cardWidth / cardHeight,
                                  children: [
                                    // Assessments Card
                                    Transform.scale(
                                      scale: _cardStaggerAnimation.value,
                                      child: _buildDashboardCard(
                                        'Assessments',
                                        'Manage and review assessment templates',
                                        Icons.assessment_outlined,
                                        colors[0], // First gradient color
                                        () {
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
                                        },
                                      ),
                                    ),
                                    // Profiles Card
                                    Transform.scale(
                                      scale: _cardStaggerAnimation.value,
                                      child: _buildDashboardCard(
                                        'Profiles',
                                        'View and manage user profiles',
                                        Icons.people_outlined,
                                        colors[1], // Second gradient color
                                        () {
                                          Navigator.push(
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
                                        },
                                      ),
                                    ),
                                    // Reports Card
                                    // Reports Card
                        Transform.scale(
                        scale: _cardStaggerAnimation.value,
                          child: _buildDashboardCard(
                            'Reports',
                        'Generate and view detailed reports',
                            Icons.analytics_outlined,
                            colors[2], // Third gradient color
                            () {
                          

Navigator.push(
  context,
  MaterialPageRoute(
    builder: (context) => ReportsScreen(
      role: widget.role,
      username: widget.username,
      subrole: widget.subrole,
      position: widget.position,
                  
    ),
  ),
);
                                        },
                                      ),
                                    ),


                                  ],
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildDashboardCard(String title, String description, IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20), // Reduced padding to fit better
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.15),
              blurRadius: 20,
              spreadRadius: 2,
              offset: const Offset(0, 8),
            ),
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              spreadRadius: 1,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10), // Reduced padding
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [color, color.withOpacity(0.7)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: Colors.white,
                size: 24, // Slightly smaller icon
              ),
            ),
            const SizedBox(height: 12), // Reduced spacing
            Text(
              title,
              style: TextStyle(
                fontSize: 18, // Slightly smaller font
                fontWeight: FontWeight.bold,
                color: color,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 6), // Reduced spacing
            Expanded(
              child: Text(
                description,
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 13, // Slightly smaller font
                  height: 1.3,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
