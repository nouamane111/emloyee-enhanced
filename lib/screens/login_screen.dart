import 'dart:convert';
import 'dart:ui';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart';
import 'home.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with TickerProviderStateMixin {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final FocusNode _passwordFocus = FocusNode();
  bool isLoading = false;
  bool isDarkMode = false;

  late AnimationController _logoController;
  late AnimationController _gradientController;
  late AnimationController _cardController;
  late Animation<double> _cardOpacity;
  late Animation<Offset> _cardOffset;

  double posX = 100;
  double posY = 100;
  double dx = 1.8;
  double dy = 1.5;
  double logoSize = 120;

  List<List<Color>> gradientColors = [
    [Color(0xFF0f2027), Color(0xFF203a43), Color(0xFF2c5364)],
    [Color(0xFF355C7D), Color(0xFF6C5B7B), Color(0xFFC06C84)],
    [Color(0xFF1c1c1c), Color(0xFF4b6cb7), Color(0xFF182848)],
    [Color(0xFF3a6186), Color(0xFF89253e), Color(0xFF2b5876)],
  ];

  int currentGradientIndex = 0;
  int nextGradientIndex = 1;
  late Animation<double> _gradientAnimation;

  void _login() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    setState(() => isLoading = true);

    try {
      final url = Uri.parse('http://localhost:5000/login');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': username, 'password': password}),
      );

      setState(() => isLoading = false);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final role = data['role'].toString();
        final subrole = data['subrole'].toString();
        final username = data['username'].toString();
        final position = data['position'].toString();
        final channelManagerId = data['channel_manager_id']?.toString();
        final nationalSupervisorId = data['national_supervisor_id']?.toString();
        final supervisorId = data['supervisor_id']?.toString();

        if (role.isEmpty || subrole.isEmpty || username.isEmpty) {
          throw Exception('Missing role/subrole/username in response');
        }

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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid credentials')),
        );
      }
    } catch (e) {
      setState(() => isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  @override
  void initState() {
    super.initState();

    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 16),
    )..addListener(_moveLogo)
      ..repeat();

    _gradientController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          setState(() {
            currentGradientIndex = nextGradientIndex;
            nextGradientIndex = (nextGradientIndex + 1) % gradientColors.length;
            _gradientController.forward(from: 0);
          });
        }
      });

    _gradientAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _gradientController, curve: Curves.linear),
    );

    _gradientController.forward();

    _cardController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _cardOpacity = Tween<double>(begin: 0, end: 1).animate(_cardController);
    _cardOffset = Tween<Offset>(begin: const Offset(0, 0.2), end: Offset.zero).animate(
      CurvedAnimation(parent: _cardController, curve: Curves.easeOut),
    );

    _cardController.forward();
  }

  void _moveLogo() {
    final screen = MediaQuery.of(context).size;

    setState(() {
      if (posX + logoSize >= screen.width || posX <= 0) dx = -dx;
      if (posY + logoSize >= screen.height || posY <= 0) dy = -dy;
      posX += dx;
      posY += dy;
    });
  }

  @override
  void dispose() {
    _logoController.dispose();
    _gradientController.dispose();
    _cardController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedBuilder(
        animation: _gradientAnimation,
        builder: (context, child) {
          final colors = List.generate(3, (i) {
            return Color.lerp(
              gradientColors[currentGradientIndex][i],
              gradientColors[nextGradientIndex][i],
              _gradientAnimation.value,
            )!;
          });

          return Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: colors,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
              Positioned(
                left: posX,
                top: posY,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                    child: Opacity(
                      opacity: 0.18,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: Image.asset('assets/logo.png', width: logoSize),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 40,
                right: 20,
                child: IconButton(
                  icon: Icon(isDarkMode ? Icons.wb_sunny : Icons.dark_mode, color: Colors.white),
                  onPressed: () => setState(() => isDarkMode = !isDarkMode),
                ),
              ),
              Center(
                child: SlideTransition(
                  position: _cardOffset,
                  child: FadeTransition(
                    opacity: _cardOpacity,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(25),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                        child: Container(
                          width: 460,
                          padding: const EdgeInsets.all(30),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(25),
                            border: Border.all(color: Colors.white24),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'PMI Login',
                                style: TextStyle(
                                  fontSize: 28,
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 10),
                              const Text(
                                'Shaping the Future, Together',
                                style: TextStyle(color: Colors.white60, fontSize: 13),
                              ),
                              const SizedBox(height: 25),
                              TextField(
                                controller: _usernameController,
                                style: const TextStyle(color: Colors.white),
                                onSubmitted: (_) => _login(),
                                decoration: _inputDecoration('Username'),
                              ),
                              const SizedBox(height: 14),
                              RawKeyboardListener(
                                focusNode: _passwordFocus,
                                onKey: (event) {
                                  if (event.isKeyPressed(LogicalKeyboardKey.enter)) {
                                    _login();
                                  }
                                },
                                child: TextField(
                                  controller: _passwordController,
                                  obscureText: true,
                                  style: const TextStyle(color: Colors.white),
                                  decoration: _inputDecoration('Password'),
                                ),
                              ),
                              const SizedBox(height: 25),
                              ElevatedButton(
                                onPressed: isLoading ? null : _login,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF00AAFF),
                                  shadowColor: Colors.transparent,
                                  minimumSize: const Size.fromHeight(50),
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: isLoading
                                    ? const CircularProgressIndicator(color: Colors.white)
                                    : const Text(
                                        'Login',
                                        style: TextStyle(
                                          fontSize: 16,
                                          color: Colors.black,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                              ),
                              const SizedBox(height: 15),
                              const Text(
                                'Forgot your password?',
                                style: TextStyle(color: Colors.white54, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
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

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      filled: true,
      fillColor: Colors.white10,
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.white60),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
    );
  }
}