import 'dart:convert';

class Team {
  Team({
    required this.id,
    required this.name,
    required this.issuerId,
    required this.keyId,
  });

  final String id;
  final String name;
  final String issuerId;
  final String keyId;

  Team copyWith({String? name, String? issuerId, String? keyId}) => Team(
        id: id,
        name: name ?? this.name,
        issuerId: issuerId ?? this.issuerId,
        keyId: keyId ?? this.keyId,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'issuerId': issuerId,
        'keyId': keyId,
      };

  factory Team.fromJson(Map<String, dynamic> json) => Team(
        id: json['id'] as String,
        name: json['name'] as String,
        issuerId: json['issuerId'] as String,
        keyId: json['keyId'] as String,
      );

  static String encodeList(List<Team> teams) =>
      jsonEncode(teams.map((t) => t.toJson()).toList());

  static List<Team> decodeList(String raw) {
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => Team.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }
}
