import 'dart:io';

import 'package:flutter/material.dart';

import '../models/app_summary.dart';
import '../models/team.dart';
import '../services/asc_api_client.dart';
import '../services/team_repository.dart';
import 'app_detail_screen.dart';

class AppsScreen extends StatefulWidget {
  const AppsScreen({
    super.key,
    required this.team,
    required this.repository,
  });

  final Team team;
  final TeamRepository repository;

  @override
  State<AppsScreen> createState() => _AppsScreenState();
}

class _AppsScreenState extends State<AppsScreen> {
  late final AscApiClient _client =
      AscApiClient(repository: widget.repository);
  late Future<List<AppSummary>> _future;

  @override
  void initState() {
    super.initState();
    _future = _client.fetchApps(widget.team);
  }

  void _reload() {
    setState(() {
      _future = _client.fetchApps(widget.team);
    });
  }

  Future<void> _openNewAppGuide() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('신규 앱 생성'),
        content: const SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '앱 자체 생성은 App Store Connect 웹에서 진행해 주세요. '
                '이 도구는 이미 만들어진 앱의 메타데이터·스크린샷 일괄 작업에 집중합니다.',
              ),
              SizedBox(height: 12),
              Text(
                '준비물',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 4),
              Text(
                '• Apple Developer Portal 에서 사전 등록된 Bundle ID\n'
                '• 사내에서 결정된 앱 이름 · SKU · primary locale\n'
                '• App Manager 이상 권한',
              ),
              SizedBox(height: 12),
              Text(
                '아래 "App Store Connect 열기" 로 이동해서 신규 앱을 만든 뒤, '
                '이 화면에서 "새로고침" 을 누르면 목록에 추가됩니다.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('닫기'),
          ),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.of(ctx).pop();
              _reload();
            },
            icon: const Icon(Icons.refresh),
            label: const Text('새로고침'),
          ),
          FilledButton.icon(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await _openAscWebApps();
            },
            icon: const Icon(Icons.open_in_new),
            label: const Text('App Store Connect 열기'),
          ),
        ],
      ),
    );
  }

  Future<void> _openAscWebApps() async {
    // macOS: 외부 브라우저로 열기. url_launcher 의존성 없이 시스템 'open' 사용.
    try {
      await Process.run('open', ['https://appstoreconnect.apple.com/apps']);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('브라우저 열기 실패: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.team.name} · 앱 목록'),
        actions: [
          IconButton(
            tooltip: '신규 앱 생성 안내',
            onPressed: _openNewAppGuide,
            icon: const Icon(Icons.add),
          ),
          IconButton(
            tooltip: '새로고침',
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<List<AppSummary>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _ErrorView(error: snapshot.error!, onRetry: _reload);
          }
          final apps = snapshot.data ?? const [];
          if (apps.isEmpty) {
            return const Center(child: Text('등록된 앱이 없습니다.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: apps.length,
            separatorBuilder: (_, _) => const Divider(height: 0),
            itemBuilder: (context, i) {
              final app = apps[i];
              return ListTile(
                title: Text(app.name),
                subtitle: Text(
                  '${app.bundleId}\nSKU: ${app.sku} · ${app.primaryLocale}',
                ),
                isThreeLine: true,
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => AppDetailScreen(
                        team: widget.team,
                        app: app,
                        repository: widget.repository,
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.onRetry});
  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            size: 40,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(height: 12),
          SelectableText(
            error.toString(),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton.tonal(
            onPressed: onRetry,
            child: const Text('다시 시도'),
          ),
        ],
      ),
    );
  }
}
