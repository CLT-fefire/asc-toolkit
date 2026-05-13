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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.team.name} · 앱 목록'),
        actions: [
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
