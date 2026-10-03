/// 单集信息
///
/// [itemId] 为官方 vid；[playable] 标记该集是否在官方免费开放集数内
/// （官方硬限制：每剧仅前 3 集可播，之后官方锁定）。
class Episode {
  final String itemId;
  final int index; // 从 1 开始的集数
  final String title;
  final bool playable;

  const Episode({
    required this.itemId,
    required this.index,
    required this.title,
    this.playable = true,
  });
}
