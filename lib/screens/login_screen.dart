// lib/screens/login_screen.dart

import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'home.dart';
import 'api_helper.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  final FocusNode _usernameFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();

  bool isLoading = false;
  bool _obscurePassword = true;

  late AnimationController _cardController;
  late Animation<double> _cardOpacity;
  late Animation<Offset> _cardOffset;

  double _responsiveValue({
    required double width,
    required double small,
    required double medium,
    required double large,
  }) {
    if (width < 900) return small;
    if (width < 1250) return medium;
    return large;
  }

  void _login() async {
    final usernameInput = _usernameController.text.trim();
    final password = _passwordController.text;

    if (usernameInput.isEmpty || password.isEmpty) {
      _showMessage('Please enter your username and password');
      return;
    }

    setState(() => isLoading = true);

    try {
      final url = Uri.parse('http://localhost:5000/login');

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': usernameInput,
          'password': password,
        }),
      );

      if (!mounted) return;
      setState(() => isLoading = false);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        final token = data['access_token'] ?? data['token'] ?? data['jwt'];

        if (token != null && token.toString().isNotEmpty) {
          await ApiHelper.saveToken(token.toString());
        }

        final role = data['role']?.toString() ?? '';
        final subrole = data['subrole']?.toString() ?? '';
        final username = data['username']?.toString() ?? '';
        final position = data['position']?.toString() ?? '';

        final channelManagerId = data['channel_manager_id']?.toString();
        final nationalSupervisorId =
            data['national_supervisor_id']?.toString();
        final supervisorId = data['supervisor_id']?.toString();

        if (role.isEmpty || subrole.isEmpty || username.isEmpty) {
          throw Exception('Missing role/subrole/username in response');
        }

        await ApiHelper.saveUserInfo(
          username: username,
          role: role,
          subrole: subrole,
          position: position,
          channelManagerId: channelManagerId,
          nationalSupervisorId: nationalSupervisorId,
          supervisorId: supervisorId,
        );

        if (!mounted) return;

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => homeScreen(
              role: role,
              subrole: subrole,
              username: username,
              position: position,
              nationalSupervisorId: nationalSupervisorId,
              supervisorId: supervisorId,
            ),
          ),
        );
      } else {
        _showMessage('Invalid credentials');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => isLoading = false);
      _showMessage('Connection error. Please check the backend server.');
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        elevation: 0,
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF003DA5).withOpacity(0.95),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: const Color(0xFF74C8E8).withOpacity(0.20),
          ),
        ),
        content: Text(
          message,
          style: const TextStyle(color: Colors.white),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();

    _cardController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );

    _cardOpacity = CurvedAnimation(
      parent: _cardController,
      curve: Curves.easeOut,
    );

    _cardOffset = Tween<Offset>(
      begin: const Offset(0, 0.025),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _cardController,
        curve: Curves.easeOutCubic,
      ),
    );

    _cardController.forward();
  }

  @override
  void dispose() {
    _cardController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _usernameFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF001529),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final height = constraints.maxHeight;

          final isCompact = width < 920;
          final isShort = height < 720;

          final horizontalPadding = _responsiveValue(
            width: width,
            small: 20,
            medium: 38,
            large: 56,
          );

          final verticalPadding = isShort ? 18.0 : 28.0;

          return Stack(
            children: [
              Positioned.fill(
                child: Image.asset(
                  'assets/login.png',
                  fit: BoxFit.cover,
                ),
              ),

              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        const Color(0xFF003DA5).withOpacity(0.24),
                        const Color(0xFF005091).withOpacity(0.18),
                        const Color(0xFF001529).withOpacity(0.32),
                      ],
                    ),
                  ),
                ),
              ),

              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(-0.60, -0.40),
                      radius: 0.95,
                      colors: [
                        const Color(0xFF74C8E8).withOpacity(0.09),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),

              SafeArea(
                child: Center(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.symmetric(
                      horizontal: horizontalPadding,
                      vertical: verticalPadding,
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: isCompact ? 620 : 1220,
                        minHeight: isCompact ? 0 : height - 80,
                      ),
                      child: isCompact
                          ? Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                _buildBrandPanel(
                                  compact: true,
                                  screenWidth: width,
                                  screenHeight: height,
                                ),
                                SizedBox(height: isShort ? 20 : 28),
                                _buildLoginCard(
                                  compact: true,
                                  screenWidth: width,
                                  screenHeight: height,
                                ),
                              ],
                            )
                          : Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  flex: width < 1150 ? 5 : 6,
                                  child: _buildBrandPanel(
                                    screenWidth: width,
                                    screenHeight: height,
                                  ),
                                ),
                                SizedBox(
                                  width: _responsiveValue(
                                    width: width,
                                    small: 28,
                                    medium: 48,
                                    large: 72,
                                  ),
                                ),
                            Expanded(
                              flex: width < 1150 ? 5 : 5,
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: Transform.translate(
                                  offset: Offset(
                                    width < 1150 ? 15 : 35, // move right depending on screen size
                                    0,
                                  ),
                                  child: _buildLoginCard(
                                    screenWidth: width,
                                    screenHeight: height,
                                  ),
                                ),
                              ),
                            ),
                              ],
                            ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildBrandPanel({
    bool compact = false,
    required double screenWidth,
    required double screenHeight,
  }) {
    final isShort = screenHeight < 720;

    final topPadding = compact
        ? 0.0
        : _responsiveValue(
            width: screenWidth,
            small: 40,
            medium: 58,
            large: 78,
          );

    final titleSize = compact
        ? 26.0
        : _responsiveValue(
            width: screenWidth,
            small: 28,
            medium: 30,
            large: 32,
          );

    final headlineSize = compact
        ? 34.0
        : _responsiveValue(
            width: screenWidth,
            small: 38,
            medium: 46,
            large: 52,
          );

    return FadeTransition(
      opacity: _cardOpacity,
      child: SlideTransition(
        position: _cardOffset,
        child: Padding(
          padding: EdgeInsets.only(top: isShort ? 20 : topPadding),
          child: Column(
            crossAxisAlignment:
                compact ? CrossAxisAlignment.center : CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'PMI LEAP',
                textAlign: compact ? TextAlign.center : TextAlign.left,
                style: TextStyle(
                  color: const Color(0xFF74C8E8),
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                  fontSize: titleSize,
                ),
              ),
              SizedBox(height: isShort ? 22 : 30),
              Text(
                'Performance intelligence,\ncrafted for field\nexcellence.',
                textAlign: compact ? TextAlign.center : TextAlign.left,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: headlineSize,
                  height: 1.04,
                  letterSpacing: -1.1,
                  fontWeight: FontWeight.w900,
                ),
              ),
              SizedBox(height: isShort ? 16 : 22),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: compact ? 500 : 590),
                child: Text(
                  'An internal workspace for assessments, profiles, and performance analytics.',
                  textAlign: compact ? TextAlign.center : TextAlign.left,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.74),
                    fontSize: compact ? 14 : 16,
                    height: 1.55,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoginCard({
    bool compact = false,
    required double screenWidth,
    required double screenHeight,
  }) {
    return FadeTransition(
      opacity: _cardOpacity,
      child: SlideTransition(
        position: _cardOffset,
        child: _ProfessionalGlassCard(
          compact: compact,
          screenWidth: screenWidth,
          screenHeight: screenHeight,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Welcome back',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: compact ? 30 : 32,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.7,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Sign in to continue to your LEAP dashboard',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.66),
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
              SizedBox(height: screenHeight < 720 ? 24 : 32),

              _GlassTextField(
                controller: _usernameController,
                focusNode: _usernameFocus,
                hint: 'Username',
                icon: Icons.person_rounded,
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => _passwordFocus.requestFocus(),
              ),

              const SizedBox(height: 16),

              _GlassTextField(
                controller: _passwordController,
                focusNode: _passwordFocus,
                hint: 'Password',
                icon: Icons.lock_rounded,
                obscureText: _obscurePassword,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _login(),
                suffix: IconButton(
                  splashRadius: 20,
                  tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_rounded
                        : Icons.visibility_off_rounded,
                    color: Colors.white.withOpacity(0.72),
                    size: 22,
                  ),
                  onPressed: () {
                    setState(() {
                      _obscurePassword = !_obscurePassword;
                    });
                  },
                ),
              ),

              SizedBox(height: screenHeight < 720 ? 22 : 26),

              _LoginButton(
                isLoading: isLoading,
                onPressed: _login,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ==================== GLASS CARD ====================

class _ProfessionalGlassCard extends StatelessWidget {
  final Widget child;
  final bool compact;
  final double screenWidth;
  final double screenHeight;

  const _ProfessionalGlassCard({
    required this.child,
    required this.screenWidth,
    required this.screenHeight,
    this.compact = false,
  });

  double _cardWidth() {
    if (compact) return double.infinity;

    if (screenWidth < 1050) return 410;
    if (screenWidth < 1250) return 440;
    if (screenWidth < 1450) return 470;
    return 500;
  }

  EdgeInsets _cardPadding() {
    if (compact) {
      return const EdgeInsets.symmetric(horizontal: 30, vertical: 36);
    }

    if (screenHeight < 720) {
      return const EdgeInsets.symmetric(horizontal: 34, vertical: 34);
    }

    if (screenWidth < 1200) {
      return const EdgeInsets.symmetric(horizontal: 36, vertical: 40);
    }

    return const EdgeInsets.symmetric(horizontal: 42, vertical: 44);
  }

  @override
  Widget build(BuildContext context) {
    const double radius = 38;

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          width: _cardWidth(),
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: const Color(0xFF74C8E8).withOpacity(0.17),
              width: 1.1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.32),
                blurRadius: 42,
                offset: const Offset(0, 20),
              ),
              BoxShadow(
                color: const Color(0xFF74C8E8).withOpacity(0.09),
                blurRadius: 54,
                offset: const Offset(0, 0),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(radius - 2),
            child: Container(
              padding: _cardPadding(),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(radius - 2),
                color: const Color(0xFF003DA5).withOpacity(0.18),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withOpacity(0.07),
                    const Color(0xFF005091).withOpacity(0.20),
                    Colors.black.withOpacity(0.09),
                  ],
                ),
              ),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(radius - 8),
                          border: Border(
                            top: BorderSide(
                              color: const Color(0xFF74C8E8).withOpacity(0.20),
                              width: 1,
                            ),
                            left: BorderSide(
                              color: Colors.white.withOpacity(0.08),
                              width: 1,
                            ),
                            right: BorderSide(
                              color: Colors.white.withOpacity(0.03),
                              width: 1,
                            ),
                            bottom: BorderSide(
                              color: Colors.black.withOpacity(0.10),
                              width: 1,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: -60,
                    right: -45,
                    child: IgnorePointer(
                      child: Container(
                        height: 145,
                        width: 145,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF74C8E8).withOpacity(0.08),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: -45,
                    left: -35,
                    child: IgnorePointer(
                      child: Container(
                        height: 110,
                        width: 230,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          color: Colors.white.withOpacity(0.025),
                        ),
                      ),
                    ),
                  ),
                  child,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ==================== GLASS TEXT FIELD ====================

class _GlassTextField extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;
  final IconData icon;
  final Widget? suffix;
  final bool obscureText;
  final TextInputAction textInputAction;
  final Function(String)? onSubmitted;

  const _GlassTextField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.hint,
    required this.icon,
    this.suffix,
    this.obscureText = false,
    this.textInputAction = TextInputAction.next,
    this.onSubmitted,
  });

  @override
  State<_GlassTextField> createState() => _GlassTextFieldState();
}

class _GlassTextFieldState extends State<_GlassTextField> {
  @override
  Widget build(BuildContext context) {
    return TextField(
      key: ValueKey('${widget.hint}_${widget.obscureText}'),
      controller: widget.controller,
      focusNode: widget.focusNode,
      obscureText: widget.obscureText,
      enableSuggestions: !widget.obscureText,
      autocorrect: !widget.obscureText,
      textInputAction: widget.textInputAction,
      onSubmitted: widget.onSubmitted,
      cursorColor: const Color(0xFF74C8E8),
      style: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w500,
      ),
      decoration: InputDecoration(
        hintText: widget.hint,
        hintStyle: TextStyle(
          color: Colors.white.withOpacity(0.48),
          fontWeight: FontWeight.w500,
        ),
        prefixIcon: Icon(
          widget.icon,
          color: const Color(0xFF74C8E8).withOpacity(0.75),
          size: 21,
        ),
        suffixIcon: widget.suffix,
        filled: true,
        fillColor: Colors.black.withOpacity(0.20),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 19,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(
            color: const Color(0xFF74C8E8).withOpacity(0.16),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(
            color: const Color(0xFF74C8E8).withOpacity(0.85),
            width: 1.6,
          ),
        ),
      ),
    );
  }
}

// ==================== LOGIN BUTTON ====================

class _LoginButton extends StatefulWidget {
  final bool isLoading;
  final VoidCallback onPressed;

  const _LoginButton({
    required this.isLoading,
    required this.onPressed,
  });

  @override
  State<_LoginButton> createState() => _LoginButtonState();
}

class _LoginButtonState extends State<_LoginButton> {
  bool _hovering = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final scale = widget.isLoading
        ? 1.0
        : _pressed
            ? 0.985
            : _hovering
                ? 1.01
                : 1.0;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() {
        _hovering = false;
        _pressed = false;
      }),
      child: GestureDetector(
        onTapDown:
            widget.isLoading ? null : (_) => setState(() => _pressed = true),
        onTapCancel:
            widget.isLoading ? null : () => setState(() => _pressed = false),
        onTapUp: widget.isLoading
            ? null
            : (_) {
                setState(() => _pressed = false);
                widget.onPressed();
              },
        child: AnimatedScale(
          scale: scale,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          child: Container(
            width: double.infinity,
            height: 60,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: _hovering
                    ? [
                        const Color(0xFF005091).withOpacity(0.95),
                        const Color(0xFF003DA5).withOpacity(0.92),
                        const Color(0xFF74C8E8).withOpacity(0.88),
                      ]
                    : [
                        const Color(0xFF005091).withOpacity(0.88),
                        const Color(0xFF003DA5).withOpacity(0.85),
                        const Color(0xFF74C8E8).withOpacity(0.78),
                      ],
              ),
              border: Border.all(
                color: const Color(0xFF74C8E8)
                    .withOpacity(_hovering ? 0.45 : 0.32),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.28),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
                BoxShadow(
                  color: const Color(0xFF74C8E8)
                      .withOpacity(_hovering ? 0.24 : 0.14),
                  blurRadius: 20,
                  offset: const Offset(0, 0),
                ),
              ],
            ),
            child: Center(
              child: widget.isLoading
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: Colors.white,
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Sign in',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.2,
                            shadows: [
                              Shadow(
                                color: Colors.black45,
                                blurRadius: 4,
                                offset: Offset(0, 1),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Icon(
                          Icons.arrow_forward_rounded,
                          color: Colors.white.withOpacity(0.92),
                          size: 20,
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}