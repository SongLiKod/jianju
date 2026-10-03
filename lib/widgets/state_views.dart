import 'package:flutter/material.dart';

/// 加载中 / 加载失败（可重试）/ 空状态 通用视图
class LoadingView extends StatelessWidget {
  final String text;
  const LoadingView({super.key, this.text = '加载中...'});

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(strokeWidth: 2.5),
            const SizedBox(height: 12),
            Text(text,
                style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.outline)),
          ],
        ),
      );
}

class ErrorRetryView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const ErrorRetryView(
      {super.key, this.message = '网络加载失败，请稍后重试', required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final secondary = Theme.of(context).colorScheme.outline;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.wifi_off_rounded, size: 44, color: secondary),
          const SizedBox(height: 12),
          Text(message,
              style: TextStyle(fontSize: 13, color: secondary)),
          const SizedBox(height: 14),
          FilledButton.tonal(
            onPressed: onRetry,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 28),
            ),
            child: const Text('重新加载'),
          ),
        ],
      ),
    );
  }
}

class EmptyView extends StatelessWidget {
  final String message;
  const EmptyView({super.key, this.message = '暂无内容'});

  @override
  Widget build(BuildContext context) {
    final secondary = Theme.of(context).colorScheme.outline;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.explore_outlined, size: 44, color: secondary),
          const SizedBox(height: 12),
          Text(message, style: TextStyle(fontSize: 13, color: secondary)),
        ],
      ),
    );
  }
}
