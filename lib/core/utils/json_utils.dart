/// 容错 JSON 读取工具：
/// 源接口字段随版本变动较大，这里统一做安全取值 + 递归探测，
/// 避免因单个字段缺失导致解析崩溃。
class JsonUtils {
  JsonUtils._();

  static String? s(Map<dynamic, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v != null && v.toString().isNotEmpty) return v.toString();
    }
    return null;
  }

  static int? i(Map<dynamic, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) {
        final cleaned = v.replaceAll(RegExp(r'[^0-9]'), '');
        if (cleaned.isNotEmpty) return int.tryParse(cleaned);
        // 可能是 "10.2万人看" 之类文本，交由展示层处理
        return null;
      }
    }
    return null;
  }

  static List<Map<dynamic, dynamic>> listOfMaps(dynamic json, List<String> keys) {
    for (final k in keys) {
      final v = _resolve(json, k);
      if (v is List) {
        final out = <Map<dynamic, dynamic>>[];
        for (final e in v) {
          if (e is Map) out.add(e);
        }
        if (out.isNotEmpty) return out;
      }
    }
    return const [];
  }

  static dynamic _resolve(dynamic json, String key) {
    if (json is Map) return json[key];
    return null;
  }

  /// 在任意 JSON 结构中递归查找第一个包含 [needle] 的字符串
  /// （用于从结构多变的播放信息中提取 m3u8 地址）
  static String? findFirstStringContaining(dynamic json, String needle,
      {Set<Object?>? visited}) {
    visited ??= {};
    if (json == null || visited.contains(json)) return null;
    visited.add(json);
    if (json is String) {
      return json.contains(needle) ? json : null;
    }
    if (json is Map) {
      for (final v in json.values) {
        final r = findFirstStringContaining(v, needle, visited: visited);
        if (r != null) return r;
      }
    } else if (json is List) {
      for (final v in json) {
        final r = findFirstStringContaining(v, needle, visited: visited);
        if (r != null) return r;
      }
    }
    return null;
  }
}
