import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

class ProfileDetailScreen extends StatefulWidget {
  final int profileId;
  final String fullName;
  final String? role;
  final String? subrole;
  final String? position;
  final String? email;
  final String? phone;

  /// Only two parent-wired actions:
  final void Function(Map<String, dynamic> preselectProfile)? onStartAssessment; // -> AssessmentCategoryScreen
  final void Function({
    required int profileId,
    required String fullName,
    String? role,
    String? subrole,
    String? position,
  })? onOpenReports; // -> ReportsScreen

  const ProfileDetailScreen({
    super.key,
    required this.profileId,
    required this.fullName,
    this.role,
    this.subrole,
    this.position,
    this.email,
    this.phone,
    this.onStartAssessment,
    this.onOpenReports,
  });

  @override
  State<ProfileDetailScreen> createState() => _ProfileDetailScreenState();
}

class _ProfileDetailScreenState extends State<ProfileDetailScreen>
    with TickerProviderStateMixin {
  double? allTimeGpa;
  double? last3Gpa;
  List<Map<String, dynamic>> categoryBreakdown = [];
  Map<String, dynamic>? hierarchy; // optional

  bool isLoading = true;
  late final AnimationController _anim;
  late final Animation<double> _fade;

  static const String _endpoint = 'http://localhost:5000/get_profile_details';

  String getPerformanceLevel(double? gpa) {
    if (gpa == null) return 'N/A';
    if (gpa >= 2.55) return 'Accelerate';
    if (gpa >= 2.10) return 'Advanced';
    return 'Inadequate';
  }

  Color perfColor(String level) {
    switch (level) {
      case 'Accelerate': return const Color(0xFF16A34A);
      case 'Advanced':   return const Color(0xFFF59E0B);
      case 'Inadequate': return const Color(0xFFEF4444);
      default:           return Colors.grey;
    }
  }

  Color _gpaColor(double? gpa) => perfColor(getPerformanceLevel(gpa));

  Future<void> _fetch() async {
    try {
      final resp = await http.post(
        Uri.parse(_endpoint),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'profile_id': widget.profileId}),
      );
      if (!mounted) return;

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        setState(() {
          allTimeGpa = data['all_time_gpa'] == null ? null : double.tryParse('${data['all_time_gpa']}');
          last3Gpa   = data['last_3_gpa']   == null ? null : double.tryParse('${data['last_3_gpa']}');

          final cb = data['category_breakdown'];
          categoryBreakdown = (cb is List)
              ? cb.map((e) => Map<String, dynamic>.from(e as Map)).toList().cast<Map<String, dynamic>>()
              : <Map<String, dynamic>>[];

          hierarchy = (data['hierarchy'] is Map)
              ? Map<String, dynamic>.from(data['hierarchy'])
              : null;

          isLoading = false;
        });
        _anim.forward();
      } else {
        setState(() => isLoading = false);
        _toast('Couldn’t load fresh data (placeholders shown)', isWarn: true);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => isLoading = false);
      _toast('Offline / server unavailable (placeholders shown)', isWarn: true);
    }
  }

  void _toast(String msg, {bool isWarn = false}) {
    final bg = isWarn ? Colors.orange[700] : Colors.teal[600];
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: bg,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 450));
    _fade = CurvedAnimation(parent: _anim, curve: Curves.easeInOut);
    _fetch();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  BoxDecoration _cardDeco() => BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withOpacity(0.15)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
      );

  Widget _chip(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
      );

  void _copyToClipboard(String text, String toast) async {
    await Clipboard.setData(ClipboardData(text: text));
    _toast(toast);
  }

  Widget _identityHeader() {
    final level = getPerformanceLevel(allTimeGpa);
    final lvlColor = perfColor(level);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDeco(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(widget.fullName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Wrap(runSpacing: 6, spacing: 8, children: [
                  if (widget.role?.isNotEmpty == true) _chip(widget.role!),
                  if (widget.subrole?.isNotEmpty == true) _chip(widget.subrole!),
                  if (widget.position?.isNotEmpty == true) _chip(widget.position!),
                ]),
              ]),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: lvlColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: lvlColor.withOpacity(0.4)),
              ),
              child: Row(children: [
                Icon(Icons.verified, size: 16, color: lvlColor),
                const SizedBox(width: 6),
                Text(level, style: TextStyle(fontWeight: FontWeight.w600, color: lvlColor)),
              ]),
            ),
          ]),
          const SizedBox(height: 12),
          Wrap(spacing: 12, runSpacing: 4, children: [
            if (widget.email?.isNotEmpty == true)
              TextButton.icon(
                onPressed: () => _copyToClipboard(widget.email!, 'Email copied'),
                icon: const Icon(Icons.email_outlined),
                label: Text(widget.email!, overflow: TextOverflow.ellipsis),
              ),
            if (widget.phone?.isNotEmpty == true)
              TextButton.icon(
                onPressed: () => _copyToClipboard(widget.phone!, 'Phone copied'),
                icon: const Icon(Icons.phone_outlined),
                label: Text(widget.phone!, overflow: TextOverflow.ellipsis),
              ),
          ]),
        ],
      ),
    );
  }

  Widget _gpaCard(String title, double? gpa, IconData icon) {
    final color = _gpaColor(gpa);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withOpacity(0.10), color.withOpacity(0.05)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.20)),
        boxShadow: [BoxShadow(color: color.withOpacity(0.08), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: color.withOpacity(0.2), borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey[700])),
          ),
        ]),
        const SizedBox(height: 10),
        Text(gpa?.toStringAsFixed(2) ?? 'N/A', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: color)),
      ]),
    );
  }

  Widget _categoryTile(Map<String, dynamic> item, int index) {
    final scoreRaw = item['average_score'];
    final score = (scoreRaw == null) ? null : double.tryParse(scoreRaw.toString());
    final color = _gpaColor(score);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: _cardDeco(),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        leading: Container(
          width: 40, height: 40,
          decoration: BoxDecoration(color: color.withOpacity(0.10), borderRadius: BorderRadius.circular(10)),
          child: Center(child: Text('${index + 1}', style: TextStyle(color: color, fontWeight: FontWeight.w700))),
        ),
        title: Text('${item['category'] ?? '—'}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
        subtitle: (item['questions_count'] != null)
            ? Text('${item['questions_count']} questions', style: TextStyle(color: Colors.grey[600], fontSize: 12))
            : null,
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(color: color.withOpacity(0.10), borderRadius: BorderRadius.circular(20)),
          child: Text(score?.toStringAsFixed(2) ?? 'N/A',
              style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 14)),
        ),
      ),
    );
  }

  Widget _quickActions() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: _cardDeco(),
      child: Wrap(
        spacing: 8, runSpacing: 8,
        children: [
          FilledButton.icon(
            onPressed: _handleStartAssessmentTap,
            icon: const Icon(Icons.play_circle_outline),
            label: const Text('Start assessment'),
          ),
          FilledButton.icon(
            onPressed: _handleOpenReportsTap,
            icon: const Icon(Icons.bar_chart_outlined),
            label: const Text('Open reports'),
          ),
          OutlinedButton.icon(
            onPressed: () { setState(() => isLoading = true); _fetch(); },
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh'),
          ),
        ],
      ),
    );
  }

  Widget _hierarchyStrip() {
    if (hierarchy == null) return const SizedBox.shrink();
    final cm = (hierarchy!['channel_manager_name'] ?? '').toString();
    final ns = (hierarchy!['national_supervisor_name'] ?? '').toString();
    final sp = (hierarchy!['supervisor_name'] ?? '').toString();

    final items = <Widget>[];
    if (cm.isNotEmpty) items.add(_rolePill('Channel Manager', cm));
    if (ns.isNotEmpty) items.add(_rolePill('National Supervisor', ns));
    if (sp.isNotEmpty) items.add(_rolePill('Supervisor', sp));
    if (items.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDeco(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.account_tree_outlined, color: Colors.teal[700]),
          const SizedBox(width: 8),
          const Text('Hierarchy', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: items),
      ]),
    );
  }

  Widget _rolePill(String title, String name) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.teal.withOpacity(0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.teal.withOpacity(0.25)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.person_outline, size: 16),
        const SizedBox(width: 6),
        Text('$title: ', style: const TextStyle(fontWeight: FontWeight.w600)),
        Text(name),
      ]),
    );
  }

  // ---- Wrappers: always do something (toast if parent didn't wire) ----
  void _handleStartAssessmentTap() {
    if (widget.onStartAssessment == null) {
      _toast('Start assessment action not wired by parent', isWarn: true);
      return;
    }
    final payload = {
      'id': widget.profileId,
      'full_name': widget.fullName,
      'role': widget.role,
      'subrole': widget.subrole,
      'position': widget.position,
      'email': widget.email,
      'phone': widget.phone,
    };
    widget.onStartAssessment!(payload);
  }

  void _handleOpenReportsTap() {
    if (widget.onOpenReports == null) {
      _toast('Open reports action not wired by parent', isWarn: true);
      return;
    }
    widget.onOpenReports!(
      profileId: widget.profileId,
      fullName: widget.fullName,
      role: widget.role,
      subrole: widget.subrole,
      position: widget.position,
    );
  }

  @override
  Widget build(BuildContext context) {
    final subtitle = [
      if (widget.role?.isNotEmpty == true) widget.role!,
      if (widget.subrole?.isNotEmpty == true) widget.subrole!,
      if (widget.position?.isNotEmpty == true) widget.position!,
    ].join(' • ');

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        elevation: 0, backgroundColor: Colors.white, foregroundColor: Colors.grey[800],
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.fullName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          if (subtitle.isNotEmpty) Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        ]),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: () { setState(() => isLoading = true); _fetch(); }),
        ],
      ),
      body: isLoading
          ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Colors.teal[600]!)),
              const SizedBox(height: 12),
              Text('Loading profile…', style: TextStyle(color: Colors.grey[600])),
            ]))
          : FadeTransition(
              opacity: _fade,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _identityHeader(),
                  const SizedBox(height: 12),
                  _quickActions(),
                  const SizedBox(height: 12),
                  _hierarchyStrip(),
                  const SizedBox(height: 12),

                  Row(children: [
                    Expanded(child: _gpaCard('All-Time GPA', allTimeGpa, Icons.timeline)),
                    const SizedBox(width: 12),
                    Expanded(child: _gpaCard('Recent GPA (Last 3)', last3Gpa, Icons.trending_up)),
                  ]),
                  const SizedBox(height: 16),

                  Row(children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: Colors.teal.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                      child: Icon(Icons.category, color: Colors.teal[700], size: 20),
                    ),
                    const SizedBox(width: 10),
                    const Text('Category Breakdown', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  ]),
                  const SizedBox(height: 10),
                  if (categoryBreakdown.isEmpty)
                    Container(
                      width: double.infinity, padding: const EdgeInsets.all(36), decoration: _cardDeco(),
                      child: Column(children: [
                        Icon(Icons.inbox_outlined, size: 44, color: Colors.grey[400]),
                        const SizedBox(height: 10),
                        Text('No category data available', style: TextStyle(color: Colors.grey[600], fontWeight: FontWeight.w500)),
                      ]),
                    )
                  else
                    ListView.builder(
                      itemCount: categoryBreakdown.length,
                      shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
                      itemBuilder: (context, i) => _categoryTile(categoryBreakdown[i], i),
                    ),
                  const SizedBox(height: 20),
                ]),
              ),
            ),
    );
  }
}

