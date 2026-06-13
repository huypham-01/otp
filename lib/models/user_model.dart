class UserModel {
  final String uuid;
  final String username;
  final String? fullname;
  final String? email;
  final String? departmentId;
  final String? verify;

  UserModel({
    required this.uuid,
    required this.username,
    this.fullname,
    this.email,
    this.departmentId,
    this.verify,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      uuid: json['uuid'] as String,
      username: json['username'] as String,
      fullname: json['fullname'] as String?,
      email: json['email'] as String?,
      departmentId: json['department_id'] as String?,
      verify: json['verify'] as String?,
    );
  }
}
