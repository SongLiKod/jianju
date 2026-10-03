import 'package:flutter/material.dart';

import '../../core/models/drama.dart';
import '../../core/services/favorite_service.dart';
import '../../widgets/drama_card.dart';
import '../../widgets/state_views.dart';
import '../detail/detail_page.dart';

/// 短剧收藏列表（本地数据）
class FavoritesPage extends StatefulWidget {
  const FavoritesPage({super.key});

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  @override
  Widget build(BuildContext context) {
    final favorites = FavoriteService.favorites;
    return Scaffold(
      appBar: AppBar(title: const Text('我的收藏')),
      body: favorites.isEmpty
          ? const EmptyView(message: '还没有收藏短剧，去详情页收藏吧')
          : ListView.builder(
              padding: EdgeInsets.only(
                top: 6,
                bottom: MediaQuery.paddingOf(context).bottom + 32,
              ),
              itemCount: favorites.length,
              itemBuilder: (context, index) {
                final drama = favorites[index].drama;
                return DramaCard(
                  drama: drama,
                  onTap: () => _open(drama),
                );
              },
            ),
    );
  }

  void _open(Drama drama) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => DetailPage(bookId: drama.bookId)),
    );
    if (mounted) setState(() {}); // 返回后刷新（可能已取消收藏）
  }
}
