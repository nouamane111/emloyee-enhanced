import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class ApiHelper {
  // Base URL for your backend
  static const String baseUrl = 'http://localhost:5000';
  
  /// Get headers with JWT token
  static Future<Map<String, String>> getHeaders() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? token = prefs.getString('jwt_token');
    
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',  // Add JWT if exists
    };
  }
  
/// Save JWT token after login
static Future<void> saveToken(String token) async {
  SharedPreferences prefs = await SharedPreferences.getInstance();
  await prefs.setString('jwt_token', token);
}

/// Save user information after login
static Future<void> saveUserInfo({
  required String username,
  required String role,
  required String subrole,
  required String position,
  String? channelManagerId,
  String? nationalSupervisorId,
  String? supervisorId,
}) async {
  SharedPreferences prefs = await SharedPreferences.getInstance();

  await prefs.setString('username', username);
  await prefs.setString('role', role);
  await prefs.setString('subrole', subrole);
  await prefs.setString('position', position);

  if (channelManagerId != null) {
    await prefs.setString('channel_manager_id', channelManagerId);
  }

  if (nationalSupervisorId != null) {
    await prefs.setString('national_supervisor_id', nationalSupervisorId);
  }

  if (supervisorId != null) {
    await prefs.setString('supervisor_id', supervisorId);
  }
}

/// Get saved JWT token
static Future<String?> getToken() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getString('jwt_token');
  }
  
  /// Clear token (logout)
  static Future<void> clearToken() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove('jwt_token');
  }
  
  /// Check if user is logged in
  static Future<bool> isLoggedIn() async {
    String? token = await getToken();
    return token != null;
  }
  
  /// POST request with automatic JWT
  static Future<http.Response> post(String endpoint, Map<String, dynamic> body) async {
    final headers = await getHeaders();
    return await http.post(
      Uri.parse('$baseUrl$endpoint'),
      headers: headers,
      body: jsonEncode(body),
    );
  }
  /// PUT request with automatic JWT
static Future<http.Response> put(String endpoint, Map<String, dynamic> body) async {
  final headers = await getHeaders();
  return await http.put(
    Uri.parse('$baseUrl$endpoint'),
    headers: headers,
    body: jsonEncode(body),
  );
}
  
  /// GET request with automatic JWT
  static Future<http.Response> get(String endpoint) async {
    final headers = await getHeaders();
    return await http.get(
      Uri.parse('$baseUrl$endpoint'),
      headers: headers,
    );
  }
}