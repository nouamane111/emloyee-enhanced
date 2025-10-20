// lib/screens/edit_profile_sheet.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// Bottom sheet to edit a profile using NAMES (not IDs)
/// - Supervisor & National Supervisor edited via typeahead by NAME
/// - Payload sends: supervisor_name, national_supervisor_name (backend resolves to IDs)
/// - No channel manager field is shown or sent.
class EditProfileSheet extends StatefulWidget {
  final String baseUrl;
  final int profileId;
  final String currentUserRole;     // to decide who can edit role/position
  final String currentUserPosition;

  const EditProfileSheet({
    super.key,
    required this.baseUrl,
    required this.profileId,
    required this.currentUserRole,
    required this.currentUserPosition,
  });

  @override
  State<EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<EditProfileSheet> {
  final _formKey = GlobalKey<FormState>();

  bool _loading = true;
  bool _saving = false;
  String? _loadError;

  // canonical maps (keys are canonical; labels are pretty)
  static const kPositions = <String, String>{
    'channel manager': 'Channel Manager',
    'national supervisor': 'National Supervisor',
    'supervisor': 'Supervisor',
    'sales expert': 'Sales Expert',
  };
  static const kRoles = <String, String>{
    'SFP': 'SFP',
    'CE': 'CE',
    'CC': 'CC',
  };

  // helpers
  String canonLower(String? s) => (s ?? '').trim().toLowerCase();
  String canonUpper(String? s) => (s ?? '').trim().toUpperCase();

  String? safeDropdownValue(
    String? v,
    List<DropdownMenuItem<String>> items, {
    bool toLower = false,
    bool toUpper = false,
  }) {
    if (v == null) return null;
    final needle = toLower ? canonLower(v) : toUpper ? canonUpper(v) : v;
    final match = items.where((it) => (it.value ?? '') == needle).toList();
    return match.length == 1 ? match.first.value : null;
  }

  bool get _canEditPosition => widget.currentUserRole.toLowerCase() == 'admin';

  // controllers
  final _nameCtl = TextEditingController();
  final _phoneCtl = TextEditingController();
  final _emailCtl = TextEditingController();
  final _subroleCtl = TextEditingController();
  final _zoneCtl = TextEditingController();
  final _dateJoinedCtl = TextEditingController();
  final _supervisorNameCtl = TextEditingController();
  final _nationalSupervisorNameCtl = TextEditingController();

  // dropdown values (canonicalized)
  String _role = '';       // 'SFP' | 'CE' | 'CC'
  String _position = '';   // 'channel manager' | 'national supervisor' | 'supervisor' | 'sales expert'

  // typeahead
  List<Map<String, dynamic>> _supSuggestions = [];
  List<Map<String, dynamic>> _nsSuggestions = [];
  bool _searchingSup = false;
  bool _searchingNS = false;

  // original snapshot for diff
  Map<String, dynamic> _original = {};

  @override
  void initState() {
    super.initState();
    _fetchProfile();
  }

  @override
  void dispose() {
    _nameCtl.dispose();
    _phoneCtl.dispose();
    _emailCtl.dispose();
    _subroleCtl.dispose();
    _zoneCtl.dispose();
    _dateJoinedCtl.dispose();
    _supervisorNameCtl.dispose();
    _nationalSupervisorNameCtl.dispose();
    super.dispose();
  }

  Future<void> _fetchProfile() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });

    try {
      final uri = Uri.parse('${widget.baseUrl}/profile_get')
          .replace(queryParameters: {'id': widget.profileId.toString()});
      final r = await http.get(uri, headers: {'Content-Type': 'application/json'});

      if (r.statusCode != 200) {
        setState(() {
          _loadError = 'HTTP ${r.statusCode}';
          _loading = false;
        });
        return;
      }

      final decoded = jsonDecode(r.body) as Map<String, dynamic>;
      final p = (decoded['profile'] ?? {}) as Map<String, dynamic>;
      _original = Map<String, dynamic>.from(p);

      // text fields
      _nameCtl.text = (p['full_name'] ?? '').toString();
      _phoneCtl.text = (p['phone'] ?? '').toString();
      _emailCtl.text = (p['email'] ?? '').toString();
      _subroleCtl.text = (p['subrole'] ?? '').toString();
      _zoneCtl.text = (p['zone'] ?? '').toString();
      _dateJoinedCtl.text = (p['date_joined'] ?? '').toString();

      // dropdowns (normalize to canonical)
      _role = canonUpper(p['role']);            // 'SFP'/'CE'/'CC'
      _position = canonLower(p['position']);    // lowercase canonical

      // names for hierarchy
      _supervisorNameCtl.text = (p['supervisor_name'] ?? '').toString();
      _nationalSupervisorNameCtl.text = (p['national_supervisor_name'] ?? '').toString();

      setState(() => _loading = false);
    } catch (e) {
      setState(() {
        _loadError = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _searchSupervisors(String q) async {
    final query = q.trim();
    if (query.isEmpty) {
      setState(() => _supSuggestions = []);
      return;
    }
    setState(() => _searchingSup = true);
    try {
      final params = <String, String>{
        'username': 'x', // not used when position != all; dummy to satisfy API
        'position': 'supervisor',
        'role': _role,           // SFP/CE/CC
        'query': query,
        'limit': '15',
      };
      final uri = Uri.parse('${widget.baseUrl}/search_profiles').replace(queryParameters: params);
      final r = await http.get(uri, headers: {'Content-Type': 'application/json'});
      if (r.statusCode == 200) {
        final arr = jsonDecode(r.body);
        if (arr is List) {
          setState(() => _supSuggestions = arr
              .cast<Map<String, dynamic>>()
              .where((m) => canonLower(m['position']) == 'supervisor')
              .toList());
        } else {
          setState(() => _supSuggestions = []);
        }
      } else {
        setState(() => _supSuggestions = []);
      }
    } catch (_) {
      setState(() => _supSuggestions = []);
    } finally {
      if (mounted) setState(() => _searchingSup = false);
    }
  }

  Future<void> _searchNationalSupervisors(String q) async {
    final query = q.trim();
    if (query.isEmpty) {
      setState(() => _nsSuggestions = []);
      return;
    }
    setState(() => _searchingNS = true);
    try {
      final params = <String, String>{
        'username': 'x',
        'position': 'national supervisor',
        'role': _role,
        'query': query,
        'limit': '15',
      };
      final uri = Uri.parse('${widget.baseUrl}/search_profiles').replace(queryParameters: params);
      final r = await http.get(uri, headers: {'Content-Type': 'application/json'});
      if (r.statusCode == 200) {
        final arr = jsonDecode(r.body);
        if (arr is List) {
          setState(() => _nsSuggestions = arr
              .cast<Map<String, dynamic>>()
              .where((m) => canonLower(m['position']) == 'national supervisor')
              .toList());
        } else {
          setState(() => _nsSuggestions = []);
        }
      } else {
        setState(() => _nsSuggestions = []);
      }
    } catch (_) {
      setState(() => _nsSuggestions = []);
    } finally {
      if (mounted) setState(() => _searchingNS = false);
    }
  }

  Map<String, dynamic> _collectPayload() {
    return <String, dynamic>{
      'id': widget.profileId,
      'full_name': _nameCtl.text.trim(),
      'phone': _phoneCtl.text.trim(),
      'email': _emailCtl.text.trim(),
      'role': _role.trim(),                 // 'SFP'/'CE'/'CC'
      'subrole': _subroleCtl.text.trim(),
      'position': _position.trim(),         // canonical lowercase
      'zone': _zoneCtl.text.trim(),
      'date_joined': _dateJoinedCtl.text.trim(),
      'supervisor_name': _supervisorNameCtl.text.trim().isEmpty ? null : _supervisorNameCtl.text.trim(),
      'national_supervisor_name': _nationalSupervisorNameCtl.text.trim().isEmpty ? null : _nationalSupervisorNameCtl.text.trim(),
    };
  }

  Map<String, dynamic> _diffPayload(Map<String, dynamic> newPayload) {
    final diff = <String, dynamic>{'id': widget.profileId};
    // helpers for name-keys (since _original may not have *_name)
    String origSupName() =>
        (_original['supervisor_name'] ?? _original['supervisor_full_name'] ?? '').toString();
    String origNsName() =>
        (_original['national_supervisor_name'] ?? _original['national_supervisor_full_name'] ?? '').toString();

    void addIfChanged(String key, dynamic newVal, dynamic oldVal) {
      if ('${newVal ?? ''}' != '${oldVal ?? ''}') diff[key] = newVal;
    }

    addIfChanged('full_name', _collectPayload()['full_name'], _original['full_name']);
    addIfChanged('phone', _collectPayload()['phone'], _original['phone']);
    addIfChanged('email', _collectPayload()['email'], _original['email']);
    addIfChanged('role', _collectPayload()['role'], canonUpper(_original['role']));
    addIfChanged('subrole', _collectPayload()['subrole'], _original['subrole']);
    addIfChanged('position', _collectPayload()['position'], canonLower(_original['position']));
    addIfChanged('zone', _collectPayload()['zone'], _original['zone']);
    addIfChanged('date_joined', _collectPayload()['date_joined'], _original['date_joined']);

    // names
    addIfChanged('supervisor_name', _collectPayload()['supervisor_name'], origSupName());
    addIfChanged('national_supervisor_name', _collectPayload()['national_supervisor_name'], origNsName());

    return diff;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final payload = _collectPayload();
    final diff = _diffPayload(payload);

    if (diff.keys.length <= 1) {
      if (mounted) Navigator.of(context).pop({'updated': false});
      return;
    }

    setState(() => _saving = true);
    try {
      final uri = Uri.parse('${widget.baseUrl}/profile_update');
      final r = await http.put(uri,
          headers: {'Content-Type': 'application/json'}, body: jsonEncode(diff));

      if (r.statusCode == 200) {
        if (mounted) Navigator.of(context).pop({'updated': true});
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Save failed (HTTP ${r.statusCode})')));
          setState(() => _saving = false);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Save error: $e')));
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final positionItems = kPositions.keys
        .toSet()
        .map((key) => DropdownMenuItem<String>(
              value: key, // lowercase canonical
              child: Text(kPositions[key]!),
            ))
        .toList(growable: false);

    final roleItems = kRoles.keys
        .toSet()
        .map((key) => DropdownMenuItem<String>(
              value: key, // UPPER canonical
              child: Text(kRoles[key]!),
            ))
        .toList(growable: false);

    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return SafeArea(
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.only(bottom: bottomInset),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.88,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Edit Profile'),
              automaticallyImplyLeading: false,
              actions: [
                TextButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Save', style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
            body: _loading
                ? const Center(child: CircularProgressIndicator())
                : _loadError != null
                    ? Center(child: Text(_loadError!, style: const TextStyle(color: Colors.red)))
                    : SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            children: [
                              TextFormField(
                                controller: _nameCtl,
                                decoration: const InputDecoration(labelText: 'Full name'),
                                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                              ),
                              const SizedBox(height: 12),

                              // ROLE (canonical UPPER)
                              DropdownButtonFormField<String>(
                                value: safeDropdownValue(_role, roleItems, toUpper: true),
                                decoration: const InputDecoration(labelText: 'Department (role)'),
                                items: roleItems,
                                onChanged: _canEditPosition
                                    ? (v) => setState(() {
                                          _role = (v ?? '');
                                          _supSuggestions = [];
                                          _nsSuggestions = [];
                                        })
                                    : null,
                              ),
                              const SizedBox(height: 12),

                              // POSITION (canonical lower)
                              DropdownButtonFormField<String>(
                                value: safeDropdownValue(_position, positionItems, toLower: true),
                                decoration: const InputDecoration(labelText: 'Position'),
                                items: positionItems,
                                onChanged: _canEditPosition
                                    ? (v) => setState(() => _position = (v ?? ''))
                                    : null,
                              ),
                              const SizedBox(height: 12),

                              TextFormField(
                                controller: _subroleCtl,
                                decoration: const InputDecoration(labelText: 'Subrole (e.g., Direct/Indirect/LAMP)'),
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _phoneCtl,
                                decoration: const InputDecoration(labelText: 'Phone'),
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _emailCtl,
                                decoration: const InputDecoration(labelText: 'Email'),
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _zoneCtl,
                                decoration: const InputDecoration(labelText: 'Zone'),
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _dateJoinedCtl,
                                decoration: const InputDecoration(labelText: 'Date joined (YYYY-MM-DD)'),
                              ),

                              const SizedBox(height: 20),

                              // National Supervisor (NAME)
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Text('National Supervisor (by name)',
                                    style: TextStyle(color: Colors.grey[700])),
                              ),
                              const SizedBox(height: 6),
                              Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  TextFormField(
                                    controller: _nationalSupervisorNameCtl,
                                    decoration: InputDecoration(
                                      hintText: _searchingNS ? 'Searching…' : 'Type a name…',
                                      prefixIcon: const Icon(Icons.badge),
                                      border: const OutlineInputBorder(),
                                    ),
                                    onChanged: (v) => _searchNationalSupervisors(v),
                                  ),
                                  if (_nsSuggestions.isNotEmpty)
                                    Positioned(
                                      left: 0,
                                      right: 0,
                                      top: 56,
                                      child: Material(
                                        elevation: 4,
                                        borderRadius: BorderRadius.circular(8),
                                        child: ConstrainedBox(
                                          constraints: const BoxConstraints(maxHeight: 240),
                                          child: ListView.separated(
                                            padding: EdgeInsets.zero,
                                            shrinkWrap: true,
                                            itemCount: _nsSuggestions.length,
                                            separatorBuilder: (context, index) => const Divider(height: 1),
                                            itemBuilder: (_, i) {
                                              final s = _nsSuggestions[i];
                                              final name = (s['full_name'] ?? '').toString();
                                              return ListTile(
                                                dense: true,
                                                leading: const Icon(Icons.person_outline),
                                                title: Text(name.isEmpty ? '(no name)' : name),
                                                subtitle: Text((s['position'] ?? '').toString()),
                                                onTap: () {
                                                  FocusScope.of(context).unfocus();
                                                  setState(() {
                                                    _nationalSupervisorNameCtl.text = name;
                                                    _nsSuggestions = [];
                                                  });
                                                },
                                              );
                                            },
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),

                              const SizedBox(height: 16),

                              // Supervisor (NAME)
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Text('Supervisor (by name)', style: TextStyle(color: Colors.grey[700])),
                              ),
                              const SizedBox(height: 6),
                              Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  TextFormField(
                                    controller: _supervisorNameCtl,
                                    decoration: InputDecoration(
                                      hintText: _searchingSup ? 'Searching…' : 'Type a name…',
                                      prefixIcon: const Icon(Icons.person_search),
                                      border: const OutlineInputBorder(),
                                    ),
                                    onChanged: (v) => _searchSupervisors(v),
                                  ),
                                  if (_supSuggestions.isNotEmpty)
                                    Positioned(
                                      left: 0,
                                      right: 0,
                                      top: 56,
                                      child: Material(
                                        elevation: 4,
                                        borderRadius: BorderRadius.circular(8),
                                        child: ConstrainedBox(
                                          constraints: const BoxConstraints(maxHeight: 240),
                                          child: ListView.separated(
                                            padding: EdgeInsets.zero,
                                            shrinkWrap: true,
                                            itemCount: _supSuggestions.length,
                                            separatorBuilder: (context, index) => const Divider(height: 1),
                                            itemBuilder: (_, i) {
                                              final s = _supSuggestions[i];
                                              final name = (s['full_name'] ?? '').toString();
                                              return ListTile(
                                                dense: true,
                                                leading: const Icon(Icons.person_outline),
                                                title: Text(name.isEmpty ? '(no name)' : name),
                                                subtitle: Text((s['position'] ?? '').toString()),
                                                onTap: () {
                                                  FocusScope.of(context).unfocus();
                                                  setState(() {
                                                    _supervisorNameCtl.text = name;
                                                    _supSuggestions = [];
                                                  });
                                                },
                                              );
                                            },
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),

                              const SizedBox(height: 32),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: _saving ? null : () => Navigator.of(context).pop({'updated': false}),
                                      child: const Text('Cancel'),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: ElevatedButton(
                                      onPressed: _saving ? null : _save,
                                      child: _saving
                                          ? const SizedBox(
                                              height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                          : const Text('Save changes'),
                                    ),
                                  ),
                                ],
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
}