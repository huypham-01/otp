class AppUpdateModel {
  final String key;
  final String version;
  final String url;
  final String? description;

  const AppUpdateModel({
    required this.key,
    required this.version,
    required this.url,
    this.description,
  });

  factory AppUpdateModel.fromJson(Map<String, dynamic> json) {
    return AppUpdateModel(
      key: json['key'] as String? ?? '',
      version: json['version'] as String? ?? '',
      url: json['url'] as String? ?? '',
      description: json['description'] as String?,
    );
  }
}
