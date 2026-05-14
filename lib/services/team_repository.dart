import 'dart:convert';
import 'dart:io';

import 'package:uuid/uuid.dart';

import '../models/team.dart';

/// 팀 메타데이터(name, issuerId, keyId) + .p8 PEM 본문을 단일 JSON 파일로 저장.
///
/// 저장 위치: `~/Library/Application Support/asc_toolkit/teams.json`
/// - 디렉토리는 chmod 700, 파일은 chmod 600 (현재 macOS 사용자만 읽기 가능)
/// - fastlane이 `AuthKey_*.p8`을 사용자 머신에 평문으로 두는 것과 동등한 수준
/// - macOS Keychain을 쓰지 않으므로 ad-hoc 코드사이닝 환경에서 발생하던
///   매 실행 시 "키체인 액세스 허용" 다이얼로그 반복 문제가 사라짐
class TeamRepository {
  TeamRepository({Directory? baseDir}) : _customBaseDir = baseDir;

  static const _appDirName = 'asc_toolkit';
  static const _teamsFileName = 'teams.json';

  final Directory? _customBaseDir;
  final _uuid = const Uuid();

  // ---- Storage location ----

  Future<Directory> _baseDir() async {
    final custom = _customBaseDir;
    if (custom != null) {
      if (!await custom.exists()) {
        await custom.create(recursive: true);
      }
      return custom;
    }
    final home = Platform.environment['HOME'];
    if (home == null || home.isEmpty) {
      throw StateError('HOME 환경변수를 찾을 수 없습니다.');
    }
    final dir =
        Directory('$home/Library/Application Support/$_appDirName');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
      await Process.run('chmod', ['700', dir.path]);
    }
    return dir;
  }

  Future<File> _file() async {
    final dir = await _baseDir();
    return File('${dir.path}/$_teamsFileName');
  }

  // ---- Internal record ----

  Future<_TeamRecord> _readAll() async {
    final file = await _file();
    if (!await file.exists()) return _TeamRecord.empty();
    final raw = await file.readAsString();
    if (raw.isEmpty) return _TeamRecord.empty();
    return _TeamRecord.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> _writeAll(_TeamRecord record) async {
    final file = await _file();
    await file.writeAsString(jsonEncode(record.toJson()), flush: true);
    await Process.run('chmod', ['600', file.path]);
  }

  // ---- Public CRUD ----

  Future<List<Team>> loadAll() async {
    final record = await _readAll();
    return record.teams;
  }

  Future<Team> upsert({
    String? id,
    required String name,
    required String issuerId,
    required String keyId,
    required String p8Pem,
  }) async {
    final record = await _readAll();
    final resolvedId = id ?? _uuid.v4();
    final updated = Team(
      id: resolvedId,
      name: name,
      issuerId: issuerId,
      keyId: keyId,
    );
    final nextTeams = [
      for (final t in record.teams)
        if (t.id != resolvedId) t,
      updated,
    ];
    final nextP8s = Map<String, String>.from(record.p8Pems)
      ..[resolvedId] = p8Pem;
    await _writeAll(_TeamRecord(teams: nextTeams, p8Pems: nextP8s));
    return updated;
  }

  Future<void> delete(String id) async {
    final record = await _readAll();
    final nextTeams =
        record.teams.where((t) => t.id != id).toList(growable: false);
    final nextP8s = Map<String, String>.from(record.p8Pems)..remove(id);
    await _writeAll(_TeamRecord(teams: nextTeams, p8Pems: nextP8s));
  }

  Future<String?> readP8(String id) async {
    final record = await _readAll();
    return record.p8Pems[id];
  }
}

class _TeamRecord {
  _TeamRecord({required this.teams, required this.p8Pems});

  factory _TeamRecord.empty() =>
      const _TeamRecord._(teams: [], p8Pems: {});

  const _TeamRecord._({required this.teams, required this.p8Pems});

  final List<Team> teams;
  final Map<String, String> p8Pems;

  Map<String, dynamic> toJson() => {
        'version': 1,
        'teams': teams.map((t) => t.toJson()).toList(),
        'p8': p8Pems,
      };

  factory _TeamRecord.fromJson(Map<String, dynamic> json) {
    final teamList = (json['teams'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(Team.fromJson)
        .toList(growable: false);
    final p8Raw = json['p8'] as Map<String, dynamic>? ?? const {};
    final p8 = p8Raw.map((k, v) => MapEntry(k, v as String));
    return _TeamRecord(teams: teamList, p8Pems: p8);
  }
}
