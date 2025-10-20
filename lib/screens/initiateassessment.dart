import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_typeahead/flutter_typeahead.dart';

class InitiateAssessmentScreen extends StatefulWidget {
  final Map<String, dynamic> template;
  final String templateName;
  final String username;
  final String role;        // user’s field (e.g., SFP, CE, CC)
  final String subrole;
  final String position;    // user’s position (all | channel manager | national supervisor | supervisor)
  final String? channelManagerId;
  final String? nationalSupervisorId;
  final String? supervisorId;

  const InitiateAssessmentScreen({
    super.key,
    required this.template,
    required this.templateName,
    required this.username,
    required this.role,
    required this.subrole,
    required this.position,
    this.channelManagerId,
    this.nationalSupervisorId,
    this.supervisorId,
  });

  @override
  State<InitiateAssessmentScreen> createState() => _InitiateAssessmentScreenState();
}

class _InitiateAssessmentScreenState extends State<InitiateAssessmentScreen>
    with TickerProviderStateMixin {
  final TextEditingController assesseeNameController = TextEditingController();

  // Selected profile info (locked after choosing a suggestion)
  String? selectedRole;
  String? selectedSubrole;
  String? selectedPosition;

  // Answers & comments keyed by question_id
  final Map<int, String> answers = {};
  final Map<int, String> comments = {};

  // For “complete all” logic
  final Set<int> requiredQuestionIds = <int>{};
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _questionKeys = {}; // to scroll to first missing

  // Animated gradient
  late AnimationController _gradientController;
  late Animation<double> _gradientAnimation;

  final List<List<Color>> gradientSets = const [
    [Color(0xFF1e3a8a), Color(0xFF3730a3), Color(0xFF4338ca)],
    [Color(0xFF0f172a), Color(0xFF1e293b), Color(0xFF334155)],
    [Color(0xFF1a202c), Color(0xFF2d3748), Color(0xFF4a5568)],
    [Color(0xFF2563eb), Color(0xFF3b82f6), Color(0xFF60a5fa)],
  ];

  int currentGradientIndex = 0;
  int nextGradientIndex = 1;

  List<Map<String, dynamic>> get categories {
    final templateData = widget.template['categories'] ??
        widget.template['template']?['categories'] ??
        [];
    return List<Map<String, dynamic>>.from(templateData);
  }

  bool get isProfileSelected =>
      selectedRole != null &&
      selectedSubrole != null &&
      selectedPosition != null &&
      assesseeNameController.text.trim().isNotEmpty;

  int get totalRequired => requiredQuestionIds.length;
  int get totalAnswered =>
      answers.entries.where((e) => requiredQuestionIds.contains(e.key) && _isValidAnswer(e.value)).length;

  bool get allRequiredAnswered =>
      totalRequired > 0 &&
      totalAnswered == totalRequired;

  bool _isValidAnswer(String? v) =>
      v == 'Oui' || v == 'Non' || v == 'Partiellement' || v == 'N/A';

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _buildRequiredIdsAndKeys();

    // If the user clears the name, reset selection & answers
    assesseeNameController.addListener(() {
      if (assesseeNameController.text.trim().isEmpty && isProfileSelected) {
        setState(() {
          selectedRole = null;
          selectedSubrole = null;
          selectedPosition = null;
          answers.clear();
          comments.clear();
        });
      }
    });
  }

  void _buildRequiredIdsAndKeys() {
    requiredQuestionIds.clear();
    _questionKeys.clear();

    for (final cat in categories) {
      final qs = List<Map<String, dynamic>>.from(cat['questions'] ?? []);
      for (final q in qs) {
        final qid = (q['id'] as num).toInt();
        requiredQuestionIds.add(qid);
        _questionKeys[qid] = GlobalKey();
      }
    }
    setState(() {});
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

    _gradientAnimation =
        Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(
      parent: _gradientController,
      curve: Curves.easeInOut,
    ));

    _gradientController.forward();
  }

  @override
  void dispose() {
    _gradientController.dispose();
    assesseeNameController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Widget buildAnswerOptions(int questionId) {
    const options = ['Oui', 'Non', 'Partiellement', 'N/A'];
    return Wrap(
      spacing: 10,
      children: options.map((opt) {
        final isSelected = answers[questionId] == opt;
        return ChoiceChip(
          label: Text(opt),
          selected: isSelected,
          onSelected: isProfileSelected
              ? (_) => setState(() => answers[questionId] = opt)
              : null,
          selectedColor: Colors.blue.shade100,
          labelStyle: TextStyle(
            color: isSelected ? Colors.blue.shade900 : Colors.black,
          ),
        );
      }).toList(),
    );
  }

  Future<void> handleSubmit() async {
    if (!isProfileSelected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select a profile (name, role, subrole, position) before submitting.")),
      );
      return;
    }
    if (!allRequiredAnswered) {
      _focusFirstMissing();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Please answer all questions ($totalAnswered/$totalRequired) before submitting.")),
      );
      return;
    }

    final payload = {
      'assessor_username': widget.username,
      'assessed_name': assesseeNameController.text.trim(),
      'template_name': widget.templateName,
      'answers': answers.entries.map((entry) => {
        'question_id': entry.key,
        'answer': entry.value,
        'comment': comments[entry.key] ?? '',
      }).toList(),
    };

    final response = await http.post(
      Uri.parse('http://localhost:5000/submit_assessment'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );

    if (response.statusCode == 200) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Assessment submitted successfully!")),
      );
      if (mounted) Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to submit assessment: ${response.body}")),
      );
    }
  }

  void _focusFirstMissing() {
    for (final qid in requiredQuestionIds) {
      if (!_isValidAnswer(answers[qid])) {
        final key = _questionKeys[qid];
        if (key != null && key.currentContext != null) {
          Scrollable.ensureVisible(
            key.currentContext!,
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeInOut,
            alignment: 0.1,
          );
        }
        break;
      }
    }
  }

  Widget buildReadOnlyField(String label, String? value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        TextField(
          controller: TextEditingController(text: value ?? ''),
          readOnly: true,
          decoration: InputDecoration(
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            fillColor: const Color(0xFFF8FAFC),
            filled: true,
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _gradientSubmitButton(List<Color> colors) {
    final enabled = isProfileSelected && allRequiredAnswered;

    if (!enabled) {
      return SizedBox(
        width: 220,
        child: ElevatedButton.icon(
          onPressed: () {
            if (!isProfileSelected) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Please select and lock the profile first.")),
              );
              return;
            }
            _focusFirstMissing();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("Please answer all questions ($totalAnswered/$totalRequired) before submitting.")),
            );
          },
          icon: const Icon(Icons.send),
          label: const Text(
            "Submit Assessment",
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            backgroundColor: Colors.grey.shade400,
            foregroundColor: Colors.white,
          ),
        ),
      );
    }

    return SizedBox(
      width: 220,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [colors[0], colors[1]]),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: colors[0].withOpacity(0.25),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ElevatedButton.icon(
          onPressed: handleSubmit,
          icon: const Icon(Icons.send, color: Colors.white),
          label: const Text(
            "Submit Assessment",
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white),
          ),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            foregroundColor: Colors.white,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _gradientAnimation,
      builder: (context, child) {
        final colors = List.generate(3, (i) {
          return Color.lerp(
            gradientSets[currentGradientIndex][i],
            gradientSets[nextGradientIndex][i],
            _gradientAnimation.value,
          )!;
        });

        return Scaffold(
          backgroundColor: const Color(0xFFF8FAFC),
          appBar: AppBar(
            elevation: 0,
            backgroundColor: Colors.transparent,
            leading: Container(
              margin: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: colors[0].withOpacity(0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: Icon(Icons.arrow_back_ios_new, color: colors[0]),
              ),
            ),
            title: ShaderMask(
              shaderCallback: (bounds) => LinearGradient(
                colors: [colors[0], colors[1]],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ).createShader(bounds),
              child: const Text(
                'Initiate Assessment',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            centerTitle: true,
          ),
          body: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header card
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [colors[0].withOpacity(0.1), colors[1].withOpacity(0.05)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: colors[0].withOpacity(0.2)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [colors[0], colors[1]],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(Icons.person_search, color: Colors.white, size: 24),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Select Assessed Person',
                                          style: TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.w700,
                                            color: colors[0],
                                            letterSpacing: 0.5,
                                          )),
                                      const SizedBox(height: 4),
                                      Text('Search and lock profile before answering',
                                          style: TextStyle(fontSize: 14, color: Colors.grey[600])),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),

                            // TypeAhead Profile Search — now passes username + position
                            TypeAheadFormField(
                              textFieldConfiguration: TextFieldConfiguration(
                                controller: assesseeNameController,
                                decoration: const InputDecoration(
                                  labelText: "Full Name",
                                  border: OutlineInputBorder(),
                                ),
                              ),
                              suggestionsCallback: (pattern) async {
                                if (pattern.trim().isEmpty) return [];
                                final uri = Uri.parse('http://localhost:5000/search_profiles').replace(
                                  queryParameters: {
                                    'query': pattern,
                                    'username': widget.username,
                                    'position': widget.position,  // <-- pass logged-in position
                                    // optionally force field: 'role': widget.role,
                                  },
                                );
                                final response = await http.get(uri);
                                if (response.statusCode == 200) {
                                  final List<dynamic> suggestions = json.decode(response.body);
                                  return suggestions;
                                } else {
                                  return [];
                                }
                              },
                              itemBuilder: (context, suggestion) {
                                return ListTile(title: Text(suggestion['full_name']));
                              },
                              onSuggestionSelected: (suggestion) {
                                assesseeNameController.text = suggestion['full_name'];
                                setState(() {
                                  selectedRole = suggestion['role'];
                                  selectedSubrole = suggestion['subrole'];
                                  selectedPosition = (suggestion['position'] ?? '')
                                      .toString()
                                      .split(' ')
                                      .map((w) => w.isEmpty ? w : (w[0].toUpperCase() + w.substring(1).toLowerCase()))
                                      .join(' ');
                                });
                              },
                            ),

                            const SizedBox(height: 16),
                            buildReadOnlyField("Role", selectedRole),
                            buildReadOnlyField("Subrole", selectedSubrole),
                            buildReadOnlyField("Position", selectedPosition),
                          ],
                        ),
                      ),

                      const SizedBox(height: 32),

                      // Questions
                      IgnorePointer(
                        ignoring: !isProfileSelected,
                        child: Opacity(
                          opacity: isProfileSelected ? 1.0 : 0.4,
                          child: Column(
                            children: categories.map((cat) {
                              final categoryTitle = cat['title'] ?? '';
                              final categoryDesc = cat['description'] ?? '';
                              final questions = List<Map<String, dynamic>>.from(cat['questions'] ?? []);

                              return Container(
                                margin: const EdgeInsets.symmetric(vertical: 12),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: colors[0].withOpacity(0.08),
                                      blurRadius: 20,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(categoryTitle, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                    if (categoryDesc.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4, bottom: 10),
                                        child: Text(categoryDesc, style: const TextStyle(color: Colors.black54)),
                                      ),
                                    ...questions.map((q) {
                                      final int qId = (q['id'] as num).toInt();
                                      return Container(
                                        key: _questionKeys[qId],
                                        margin: const EdgeInsets.only(bottom: 10),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            const SizedBox(height: 12),
                                            Text(q['question_text'], style: const TextStyle(fontSize: 16)),
                                            const SizedBox(height: 6),
                                            buildAnswerOptions(qId),
                                            const SizedBox(height: 6),
                                            TextField(
                                              enabled: isProfileSelected,
                                              onChanged: (val) => comments[qId] = val,
                                              decoration: const InputDecoration(
                                                labelText: "Comment",
                                                border: OutlineInputBorder(),
                                                prefixIcon: Icon(Icons.comment),
                                              ),
                                            ),
                                            const SizedBox(height: 14),
                                            const Divider(),
                                          ],
                                        ),
                                      );
                                    }).toList(),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Footer: progress + submit
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Row(
                  children: [
                    // Progress chip
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: (allRequiredAnswered ? Colors.green : Colors.orange).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: (allRequiredAnswered ? Colors.green : Colors.orange).withOpacity(0.4)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(allRequiredAnswered ? Icons.check_circle : Icons.hourglass_bottom,
                              size: 18, color: allRequiredAnswered ? Colors.green : Colors.orange),
                          const SizedBox(width: 8),
                          Text("$totalAnswered / $totalRequired answered",
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: allRequiredAnswered ? Colors.green : Colors.orange,
                              )),
                        ],
                      ),
                    ),
                    const Spacer(),
                    _gradientSubmitButton(colors),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}