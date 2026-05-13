import 'package:flutter/material.dart';

import '../models/team.dart';
import '../services/team_repository.dart';
import 'apps_screen.dart';
import 'team_form_screen.dart';

class TeamsScreen extends StatefulWidget {
  const TeamsScreen({super.key, required this.repository});

  final TeamRepository repository;

  @override
  State<TeamsScreen> createState() => _TeamsScreenState();
}

class _TeamsScreenState extends State<TeamsScreen> {
  late Future<List<Team>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.repository.loadAll();
  }

  void _reload() {
    setState(() {
      _future = widget.repository.loadAll();
    });
  }

  Future<void> _openForm({Team? initial}) async {
    final result = await Navigator.of(context).push<Team>(
      MaterialPageRoute(
        builder: (_) => TeamFormScreen(
          repository: widget.repository,
          initial: initial,
        ),
      ),
    );
    if (result != null) _reload();
  }

  Future<void> _confirmDelete(Team team) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('팀 삭제'),
        content: Text("'${team.name}' 팀을 삭제할까요? 저장된 .p8 키도 함께 제거됩니다."),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await widget.repository.delete(team.id);
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('App Store Connect 팀'),
        actions: [
          IconButton(
            tooltip: '새로고침',
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add),
        label: const Text('팀 추가'),
      ),
      body: FutureBuilder<List<Team>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final teams = snapshot.data ?? const [];
          if (teams.isEmpty) return const _EmptyView();
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: teams.length,
            separatorBuilder: (_, _) => const Divider(height: 0),
            itemBuilder: (context, i) {
              final team = teams[i];
              return ListTile(
                leading: const Icon(Icons.groups_2_outlined),
                title: Text(team.name),
                subtitle: Text(
                  'Issuer: ${team.issuerId}\nKey ID: ${team.keyId}',
                ),
                isThreeLine: true,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: '편집',
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () => _openForm(initial: team),
                    ),
                    IconButton(
                      tooltip: '삭제',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _confirmDelete(team),
                    ),
                  ],
                ),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => AppsScreen(
                        team: team,
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

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.key_outlined, size: 48),
            const SizedBox(height: 16),
            Text(
              '등록된 팀이 없습니다.',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              '우측 하단 "팀 추가" 버튼을 눌러\n'
              'App Store Connect API Key를 등록해주세요.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
