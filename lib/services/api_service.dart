import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/user_model.dart';

class ApiService {
  static Future<String?> fetchUserFullName(String uuid) async {
    final url = Uri.parse(
      'http://192.168.110.7/iam/cip3/?c=UserController&m=getUserByUUID&uuid=$uuid',
    );

    try {
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data != null && data['user'] != null) {
          final user = UserModel.fromJson(data['user']);
          return user.fullname;
        }
      }
    } catch (e) {
      print('❌ API call error: $e');
    }
    return null;
  }
}
