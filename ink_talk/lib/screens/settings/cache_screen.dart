import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

/// 캐시 관리 화면
class CacheScreen extends StatefulWidget {
  const CacheScreen({super.key});

  @override
  State<CacheScreen> createState() => _CacheScreenState();
}

class _CacheScreenState extends State<CacheScreen> {
  String _cacheSizeText = '계산 중...';
  bool _clearing = false;

  @override
  void initState() {
    super.initState();
    _computeSize();
  }

  Future<void> _computeSize() async {
    try {
      final dir = await getTemporaryDirectory();
      final size = await _dirSize(dir);
      if (mounted) {
        setState(() => _cacheSizeText = _formatBytes(size));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _cacheSizeText = '확인 불가');
      }
    }
  }

  Future<int> _dirSize(Directory dir) async {
    int total = 0;
    try {
      final entities = dir.listSync(followLinks: false);
      for (final e in entities) {
        if (e is File) {
          total += await e.length();
        } else if (e is Directory) {
          total += await _dirSize(e);
        }
      }
    } catch (_) {}
    return total;
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _clearCache() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('캐시 삭제'),
        content: const Text(
          '임시 파일(이미지, PDF 등) 캐시를 삭제합니다. 계속할까요?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('삭제', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _clearing = true);
    try {
      final dir = await getTemporaryDirectory();
      for (final e in dir.listSync(followLinks: false)) {
        try {
          if (e is File) {
            await e.delete();
          } else if (e is Directory) {
            await e.delete(recursive: true);
          }
        } catch (_) {}
      }
      if (mounted) {
        setState(() {
          _cacheSizeText = '0 B';
          _clearing = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('캐시가 삭제되었습니다.')),
        );
        _computeSize();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _clearing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('삭제 실패: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('캐시 관리')),
      body: ListView(
        children: [
          ListTile(
            title: const Text('캐시 용량'),
            subtitle: Text(_cacheSizeText),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              '이미지, PDF 등 임시 파일이 저장됩니다.',
              style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ElevatedButton.icon(
              onPressed: _clearing ? null : _clearCache,
              icon: _clearing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.delete_outline),
              label: Text(_clearing ? '삭제 중...' : '캐시 삭제'),
            ),
          ),
        ],
      ),
    );
  }
}
