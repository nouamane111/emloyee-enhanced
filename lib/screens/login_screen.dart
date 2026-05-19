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
      begin: const Offset(0, 0.035),
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
    final size = MediaQuery.of(context).size;
    final isCompact = size.width < 920;

    return Scaffold(
      backgroundColor: const Color(0xFF001529),
      body: Stack(
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
                    const Color(0xFF003DA5).withOpacity(0.30),
                    const Color(0xFF005091).withOpacity(0.22),
                    const Color(0xFF001529).withOpacity(0.35),
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
                    const Color(0xFF74C8E8).withOpacity(0.10),
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
                  horizontal: isCompact ? 20 : 56,
                  vertical: 28,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1360),
                  child: isCompact
                      ? Column(
                          children: [
                            _buildBrandPanel(compact: true),
                            const SizedBox(height: 28),
                            _buildLoginCard(compact: true),
                          ],
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              flex: 6,
                              child: _buildBrandPanel(),
                            ),
                            const SizedBox(width: 130),
                            Expanded(
                              flex: 5,
                              child: Transform.translate(
                                offset: const Offset(105, 0),
                                child: Align(
                                  alignment: Alignment.centerRight,
                                  child: _buildLoginCard(),
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
      ),
    );
  }

  Widget _buildBrandPanel({bool compact = false}) {
    return FadeTransition(
      opacity: _cardOpacity,
      child: SlideTransition(
        position: _cardOffset,
        child: Padding(
          padding: EdgeInsets.only(top: compact ? 0 : 120),
          child: Column(
            crossAxisAlignment:
                compact ? CrossAxisAlignment.center : CrossAxisAlignment.start,
            children: [
              Text(
                'PMI LEAP',
                textAlign: compact ? TextAlign.center : TextAlign.left,
                style: TextStyle(
                  color: const Color(0xFF74C8E8),
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                  fontSize: compact ? 26 : 32,
                ),
              ),
              const SizedBox(height: 34),
              Text(
                'Performance intelligence,\ncrafted for field\nexcellence.',
                textAlign: compact ? TextAlign.center : TextAlign.left,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: compact ? 34 : 54,
                  height: 1.02,
                  letterSpacing: -1.4,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 22),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: compact ? 500 : 620),
                child: Text(
                  'An internal workspace for assessments, profiles, and performance analytics.',
                  textAlign: compact ? TextAlign.center : TextAlign.left,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.74),
                    fontSize: compact ? 14 : 16,
                    height: 1.6,
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

  Widget _buildLoginCard({bool compact = false}) {
    return FadeTransition(
      opacity: _cardOpacity,
      child: SlideTransition(
        position: _cardOffset,
        child: _ProfessionalGlassCard(
          compact: compact,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Welcome back',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.8,
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
              const SizedBox(height: 34),

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
                key: ValueKey(_obscurePassword),
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

              const SizedBox(height: 26),

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

  const _ProfessionalGlassCard({
    required this.child,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    const double radius = 40;

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          width: compact ? double.infinity : 500,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: const Color(0xFF74C8E8).withOpacity(0.18),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.36),
                blurRadius: 46,
                offset: const Offset(0, 22),
              ),
              BoxShadow(
                color: const Color(0xFF74C8E8).withOpacity(0.10),
                blurRadius: 60,
                offset: const Offset(0, 0),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(radius - 2),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 42,
                vertical: 44,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(radius - 2),
                color: const Color(0xFF003DA5).withOpacity(0.22),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withOpacity(0.08),
                    const Color(0xFF005091).withOpacity(0.24),
                    Colors.black.withOpacity(0.10),
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
                              color: const Color(0xFF74C8E8).withOpacity(0.22),
                              width: 1,
                            ),
                            left: BorderSide(
                              color: Colors.white.withOpacity(0.10),
                              width: 1,
                            ),
                            right: BorderSide(
                              color: Colors.white.withOpacity(0.04),
                              width: 1,
                            ),
                            bottom: BorderSide(
                              color: Colors.black.withOpacity(0.12),
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
                        height: 155,
                        width: 155,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF74C8E8).withOpacity(0.10),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: -45,
                    left: -35,
                    child: IgnorePointer(
                      child: Container(
                        height: 120,
                        width: 240,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          color: Colors.white.withOpacity(0.03),
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

class _GlassTextField extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      obscureText: obscureText,
      enableSuggestions: !obscureText,
      autocorrect: !obscureText,
      textInputAction: textInputAction,
      onSubmitted: onSubmitted,
      cursorColor: const Color(0xFF74C8E8),
      style: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w500,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
          color: Colors.white.withOpacity(0.48),
          fontWeight: FontWeight.w500,
        ),
        prefixIcon: Icon(
          icon,
          color: const Color(0xFF74C8E8).withOpacity(0.75),
          size: 21,
        ),
        suffixIcon: suffix,
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