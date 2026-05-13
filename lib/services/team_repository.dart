import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

import '../models/team.dart';

class TeamRepository {
  TeamRepository({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              // ad-hoc 코드사이닝(`-`)에서는 macOS Data Protection Keychain 접근에 필요한
              // keychain-access-groups entitlement 매칭이 실패해 -34018 errSecMissingEntitlement
              // 가 발생함. legacy file-based keychain을 사용하면 entitlement 없이 동작.
              mOptions: MacOsOptions(usesDataProtectionKeychain: false),
            );

  static const _teamsKey = 'asc_teams_v1';
  static const _p8Prefix = 'asc_team_p8_';

  final FlutterSecureStorage _storage;
  final _uuid = const Uuid();

  Future<List<Team>> loadAll() async {
    final raw = await _storage.read(key: _teamsKey);
    if (raw == null || raw.isEmpty) return const [];
    return Team.decodeList(raw);
  }

  Future<Team> upsert({
    String? id,
    required String name,
    required String issuerId,
    required String keyId,
    required String p8Pem,
  }) async {
    final teams = await loadAll();
    final resolvedId = id ?? _uuid.v4();
    final updated = Team(
      id: resolvedId,
      name: name,
      issuerId: issuerId,
      keyId: keyId,
    );

    final next = [
      for (final t in teams)
        if (t.id != resolvedId) t,
      updated,
    ];

    await _storage.write(key: _teamsKey, value: Team.encodeList(next));
    await _storage.write(key: '$_p8Prefix$resolvedId', value: p8Pem);
    return updated;
  }

  Future<void> delete(String id) async {
    final teams = await loadAll();
    final next = teams.where((t) => t.id != id).toList(growable: false);
    await _storage.write(key: _teamsKey, value: Team.encodeList(next));
    await _storage.delete(key: '$_p8Prefix$id');
  }

  Future<String?> readP8(String id) =>
      _storage.read(key: '$_p8Prefix$id');
}
