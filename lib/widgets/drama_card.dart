import 'package:flutter/material.dart';

import '../core/models/drama.dart';
import 'cover_image.dart';

/// 短剧卡片：展示封面、标题、简介、集数、热度（首页/搜索结果统一样式）
///
/// [sourceLabel] 非空时在标题上方标注资源站点（搜索结果标明来源站点）
class DramaCard extends StatelessWidget {
  final Drama drama;
  final VoidCallback onTap;
  final String? sourceLabel;

  const DramaCard({
    super.key,
    required this.drama,
    required this.onTap,
    this.sourceLabel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = isDark ? Colors.white54 : Colors.black45;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CoverImage(
                url: drama.coverUrl,
                width: 96,
                height: 128,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 128,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (sourceLabel != null) ...[
                        Row(
                          children: [
                            Icon(Icons.dns_outlined,
                                size: 13, color: theme.colorScheme.primary),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                '来源 $sourceLabel',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 11.5,
                                    color: theme.colorScheme.primary),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                      ],
                      Text(
                        drama.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Expanded(
                        child: Text(
                          drama.abstractText.isEmpty ? '暂无简介' : drama.abstractText,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style:
                              TextStyle(fontSize: 13, color: secondary, height: 1.3),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (drama.episodeCount > 0) ...[
                            Icon(Icons.playlist_play_rounded,
                                size: 15, color: secondary),
                            const SizedBox(width: 2),
                            Text('${drama.episodeCount}集',
                                style:
                                    TextStyle(fontSize: 12, color: secondary)),
                            const SizedBox(width: 10),
                          ],
                          if (drama.statusText.isNotEmpty) ...[
                            Text(drama.statusText,
                                style: TextStyle(
                                    fontSize: 12, color: secondary)),
                            const SizedBox(width: 10),
                          ],
                          if (drama.readCountText.isNotEmpty) ...[
                            Icon(Icons.local_fire_department_rounded,
                                size: 15, color: theme.colorScheme.primary),
                            const SizedBox(width: 2),
                            Flexible(
                              child: Text(
                                drama.readCountText,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 12,
                                    color: theme.colorScheme.primary),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
