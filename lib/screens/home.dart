import 'package:flutter/material.dart';
import 'dart:math';
import 'dart:ui';
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

  const homeScreen({
    super.key,
    required this.role,
    required this.subrole,
    required this.username,
    required this.position,
    this.nationalSupervisorId,
    this.supervisorId,
  });

  @override
  State<homeScreen> createState() => _homeScreenState();
}

class _homeScreenState extends State<homeScreen> with TickerProviderStateMixin {
  late AnimationController _gradientController;
  late AnimationController _cardController;
  late AnimationController _headerController;
  late AnimationController _chatBubbleController;
  
  late Animation<double> _gradientAnimation;
  late Animation<double> _cardStaggerAnimation;
  late Animation<double> _headerAnimation;
  late Animation<double> _chatBubbleAnimation;

  bool _showChat = false;
  bool _showWelcomeMessage = false;

  final List<List<Color>> gradientSets = [
    [Color(0xFF003DA5), Color(0xFF005091), Color(0xFF74C8E8)],
    [Color(0xFF005091), Color(0xFF003DA5), Color(0xFF74C8E8)],
    [Color(0xFF1e3a8a), Color(0xFF3730a3), Color(0xFF4338ca)],
    [Color(0xFF0f172a), Color(0xFF1e293b), Color(0xFF334155)],
  ];

  int currentGradientIndex = 0;
  int nextGradientIndex = 1;

  final List<ChatMessage> _messages = [];

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() => _showWelcomeMessage = true);
        _chatBubbleController.forward();
        
        Future.delayed(const Duration(seconds: 5), () {
          if (mounted && !_showChat) {
            _chatBubbleController.reverse();
            setState(() => _showWelcomeMessage = false);
          }
        });
      }
    });
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

    _chatBubbleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _chatBubbleAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _chatBubbleController, curve: Curves.easeOut),
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
    _chatBubbleController.dispose();
    super.dispose();
  }

  void _toggleChat() {
    setState(() {
      _showChat = !_showChat;
      _showWelcomeMessage = false;
    });

    if (_showChat && _messages.isEmpty) {
      Future.delayed(const Duration(milliseconds: 300), () {
        _addAIMessage(
          "Hi ${widget.username}! 👋\n\nI'm Philip, your PMI LEAP AI Assistant. I can help you with:\n\n• Team performance reports\n• Individual assessments\n• Profile management\n• Assessment insights\n\nWhat would you like to know?"
        );
      });
    }
  }

  void _addAIMessage(String text) {
    setState(() {
      _messages.add(ChatMessage(
        text: text,
        isUser: false,
        timestamp: DateTime.now(),
      ));
    });
  }

  void _addUserMessage(String text) {
    setState(() {
      _messages.add(ChatMessage(
        text: text,
        isUser: true,
        timestamp: DateTime.now(),
      ));
    });

    Future.delayed(const Duration(milliseconds: 800), () {
      _handleAIResponse(text);
    });
  }

  void _handleAIResponse(String userMessage) {
    String response = "";
    final msg = userMessage.toLowerCase();

    if (msg.contains('report') || msg.contains('team')) {
      response = "📊 I can show you the latest team reports!\n\nYour team has completed 16 assessments with an average score of 2.74/3 (91.3%).\n\nWould you like to:\n• View detailed team analytics\n• Check individual performance\n• See trending categories";
    } else if (msg.contains('individual') || msg.contains('specific') || msg.contains('nouhaila')) {
      response = "👤 Looking up individual performance...\n\nNouhaila Elhamrity:\n• Total assessments: 16\n• Average score: 2.74/3 (91.3%)\n• Best category: Test Guidé (2.90/3)\n• Latest assessment: SE Indirect HOW (2.38/3)\n\nWould you like to see the full timeline?";
    } else if (msg.contains('assessment') || msg.contains('evaluate')) {
      response = "📝 Assessment Tools Available:\n\n• Create new assessment\n• View templates (47 available)\n• Recent assessments\n• Assessment history\n\nWhich would you like to access?";
    } else if (msg.contains('help') || msg.contains('hi') || msg.contains('hello')) {
      response = "I'm here to help! You can ask me about:\n\n• Team performance reports\n• Individual assessments (try: 'Show Nouhaila's performance')\n• Assessment templates\n• Profile management\n\nJust ask me anything!";
    } else {
      response = "I understand you're asking about '${userMessage}'.\n\nLet me help you navigate to the right section. You can:\n\n• Ask about team reports\n• Check individual performance\n• Manage assessments\n• View profiles\n\nWhat would you like to do?";
    }

    _addAIMessage(response);
  }

  Widget _buildNavItem(IconData icon, String title, bool isActive) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: isActive ? Colors.white.withOpacity(0.2) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: isActive ? Border.all(color: Colors.white.withOpacity(0.4)) : null,
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: isActive ? Colors.white : Colors.white.withOpacity(0.8),
            size: 22,
          ),
          const SizedBox(width: 16),
          Text(
            title,
            style: TextStyle(
              color: isActive ? Colors.white : Colors.white.withOpacity(0.8),
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
      body: Stack(
        children: [
          // Animated Gradient Background
// Static Background Image - NO BLUR
Positioned.fill(
  child: Image.asset(
    'assets/background.png',
    fit: BoxFit.cover,
  ),
),

          AnimatedBuilder(
            animation: _gradientAnimation,
            builder: (context, child) {
              final colors = List.generate(3, (i) {
                return Color.lerp(
                  gradientSets[currentGradientIndex][i],
                  gradientSets[nextGradientIndex][i],
                  _gradientAnimation.value,
                )!;
              });

              return Row(
                children: [
                  // Glassmorphic Sidebar
                  ClipRRect(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Container(
                        width: 280,
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
                              color: Colors.white.withOpacity(0.2),
                              width: 1,
                            ),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: colors[0].withOpacity(0.3),
                              blurRadius: 30,
                              spreadRadius: 5,
                              offset: const Offset(5, 0),
                            ),
                          ],
                        ),
                        child: SafeArea(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Logo Container
                                Container(
                                  padding: const EdgeInsets.all(24),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(24),
                                    border: Border.all(color: Colors.white.withOpacity(0.3), width: 2),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.1),
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
                                
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    ShaderMask(
                                      shaderCallback: (bounds) => LinearGradient(
                                        colors: [Colors.white, Colors.white.withOpacity(0.95)],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ).createShader(bounds),
                                      child: const Text(
                                        'PHILIP MORRIS',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w900,
                                          fontSize: 17,
                                          letterSpacing: 2.5,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    ShaderMask(
                                      shaderCallback: (bounds) => LinearGradient(
                                        colors: [Colors.white.withOpacity(0.9), Colors.white.withOpacity(0.7)],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ).createShader(bounds),
                                      child: const Text(
                                        'INTERNATIONAL',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w400,
                                          fontSize: 13,
                                          letterSpacing: 2.0,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                
                                const SizedBox(height: 40),
                                
                                _buildNavItem(Icons.dashboard_outlined, 'Dashboard', true),
                                
                                const Spacer(),
                                
                                Container(
                                  margin: const EdgeInsets.only(bottom: 30),
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
                                        child: Text(
                                          widget.username.isNotEmpty ? widget.username[0].toUpperCase() : 'U',
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
                                                fontWeight: FontWeight.w600,
                                                fontSize: 13,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                              maxLines: 1,
                                            ),
                                            Text(
                                              widget.role,
                                              style: TextStyle(
                                                color: Colors.white.withOpacity(0.8),
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

                  // Main Content Area
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(32.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
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
                                            // WHITE TEXT - NO GRADIENT
                                            Text(
                                              'Welcome, ${widget.username}',
                                              style: const TextStyle(
                                                fontSize: 32,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.white,
                                                letterSpacing: 0.5,
                                                shadows: [
                                                  Shadow(
                                                    color: Colors.black26,
                                                    offset: Offset(0, 2),
                                                    blurRadius: 4,
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                              '${widget.position} - ${widget.role} - ${widget.subrole}',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 16,
                                                fontWeight: FontWeight.w400,
                                                shadows: [
                                                  Shadow(
                                                    color: Colors.black26,
                                                    offset: Offset(0, 1),
                                                    blurRadius: 2,
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      
                                      Container(
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(12),
                                          color: Colors.white.withOpacity(0.2),
                                          border: Border.all(color: Colors.white.withOpacity(0.4)),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withOpacity(0.2),
                                              blurRadius: 15,
                                              offset: const Offset(0, 5),
                                            ),
                                          ],
                                        ),
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(12),
                                          child: BackdropFilter(
                                            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
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
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),

                          const SizedBox(height: 40),

                          Expanded(
                            child: AnimatedBuilder(
                              animation: _cardStaggerAnimation,
                              builder: (context, child) {
                                return LayoutBuilder(
                                  builder: (context, constraints) {
                                    double availableWidth = constraints.maxWidth;
                                    double cardSpacing = 20;
                                    double cardWidth = (availableWidth - (2 * cardSpacing)) / 3;
                                    double cardHeight = cardWidth * 0.8;
                                    
                                    return GridView.count(
                                      crossAxisCount: 3,
                                      crossAxisSpacing: cardSpacing,
                                      mainAxisSpacing: cardSpacing,
                                      childAspectRatio: cardWidth / cardHeight,
                                      children: [
                                        Transform.scale(
                                          scale: _cardStaggerAnimation.value,
                                          child: _buildGlassmorphicCard(
                                            'Assessments',
                                            'Manage and review assessment templates',
                                            Icons.assessment_outlined,
                                            colors[0],
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
                                        Transform.scale(
                                          scale: _cardStaggerAnimation.value,
                                          child: _buildGlassmorphicCard(
                                            'Profiles',
                                            'View and manage user profiles',
                                            Icons.people_outlined,
                                            colors[1],
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
                                        Transform.scale(
                                          scale: _cardStaggerAnimation.value,
                                          child: _buildGlassmorphicCard(
                                            'Reports',
                                            'Generate and view detailed reports',
                                            Icons.analytics_outlined,
                                            colors[2],
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

          // AI Chat Interface
          if (_showChat)
            Positioned(
              right: 24,
              bottom: 100,
              child: _buildChatWindow(),
            ),

          // Welcome bubble
          if (_showWelcomeMessage && !_showChat)
            Positioned(
              right: 100,
              bottom: 100,
              child: ScaleTransition(
                scale: _chatBubbleAnimation,
                child: _buildWelcomeBubble(),
              ),
            ),

          // Floating AI button
          Positioned(
            right: 24,
            bottom: 24,
            child: _buildFloatingAIButton(),
          ),
        ],
      ),
    );
  }

  // GLASSMORPHIC CARD
  Widget _buildGlassmorphicCard(String title, String description, IconData icon, Color accentColor, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.white.withOpacity(0.25),
                  Colors.white.withOpacity(0.15),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Colors.white.withOpacity(0.4),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: accentColor.withOpacity(0.3),
                  blurRadius: 20,
                  spreadRadius: 2,
                  offset: const Offset(0, 8),
                ),
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [accentColor, accentColor.withOpacity(0.7)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: accentColor.withOpacity(0.4),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(
                    icon,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 0.5,
                    shadows: [
                      Shadow(
                        color: Colors.black26,
                        offset: Offset(0, 2),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: Text(
                    description,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 14,
                      height: 1.4,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWelcomeBubble() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 280),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.4)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF003DA5).withOpacity(0.3),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF003DA5), Color(0xFF74C8E8)],
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.smart_toy, color: Colors.white, size: 16),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Philip - AI Assistant',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'Hi! Need help with reports or assessments? Just ask me! 💬',
                style: TextStyle(fontSize: 13, height: 1.4, color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFloatingAIButton() {
    return GestureDetector(
      onTap: _toggleChat,
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF003DA5), Color(0xFF74C8E8)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF003DA5).withOpacity(0.4),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Icon(
          _showChat ? Icons.close : Icons.smart_toy,
          color: Colors.white,
          size: 28,
        ),
      ),
    );
  }

  Widget _buildChatWindow() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          width: 380,
          height: 550,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.3)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            children: [
              // Chat header
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF003DA5), Color(0xFF005091)],
                  ),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.smart_toy, color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 12),
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Philip - AI Assistant',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          'Always here to help',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Messages
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _messages.length,
                  itemBuilder: (context, index) {
                    return _buildChatBubble(_messages[index]);
                  },
                ),
              ),

              // Input
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  border: Border(top: BorderSide(color: Colors.white.withOpacity(0.2))),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Ask Philip anything...',
                          hintStyle: TextStyle(color: Colors.white.withOpacity(0.6)),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Colors.white),
                          ),
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.1),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                        onSubmitted: (text) {
                          if (text.trim().isNotEmpty) {
                            _addUserMessage(text);
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF003DA5), Color(0xFF74C8E8)],
                        ),
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        onPressed: () {},
                        icon: const Icon(Icons.send, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChatBubble(ChatMessage message) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: message.isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!message.isUser)
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF003DA5), Color(0xFF74C8E8)],
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.smart_toy, color: Colors.white, size: 16),
            ),
          const SizedBox(width: 8),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: message.isUser 
                    ? const Color(0xFF003DA5) 
                    : Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withOpacity(0.3)),
              ),
              child: Text(
                message.text,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;

  ChatMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
  });
}