import 'package:flutter_test/flutter_test.dart';
import 'package:jianju/core/constants/app_constants.dart';
import 'package:jianju/core/services/storage_service.dart';
import 'package:jianju/core/state/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 52api 数据源与 apikey 联动的离线行为
void main() {
  late SettingsProvider provider;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await StorageService.init();
    provider = SettingsProvider()..load();
  });

  test('当前源为 52api 时清除 apikey：自动切回官方网页源', () async {
    await provider.setApiKey52('sk-test');
    await provider.setDataSource(AppConstants.dataSourceApi52);
    expect(provider.dataSource, AppConstants.dataSourceApi52);

    await provider.setApiKey52('');
    expect(provider.hasApi52Key, isFalse);
    expect(provider.dataSource, AppConstants.dataSourceWeb);
    // 持久化同步：重新 load 后仍是官方源
    final fresh = SettingsProvider()..load();
    expect(fresh.dataSource, AppConstants.dataSourceWeb);
    expect(fresh.apiKey52, isEmpty);
  });

  test('当前源为官方时清除 apikey：数据源保持不变', () async {
    await provider.setApiKey52('sk-test');
    await provider.setDataSource(AppConstants.dataSourceWeb);

    await provider.setApiKey52('');
    expect(provider.dataSource, AppConstants.dataSourceWeb);
  });

  test('当前源为整站线路时清除 apikey：数据源保持不变', () async {
    await provider.setApiKey52('sk-test');
    await provider.setDataSource('${AppConstants.dataSourceLinePrefix}bsvod.com');

    await provider.setApiKey52('');
    expect(provider.dataSource,
        '${AppConstants.dataSourceLinePrefix}bsvod.com');
  });

  test('保存非空 apikey：数据源与已配 key 均保持不变', () async {
    await provider.setDataSource(AppConstants.dataSourceWeb);

    await provider.setApiKey52(' sk-abc ');
    expect(provider.apiKey52, 'sk-abc');
    expect(provider.hasApi52Key, isTrue);
    expect(provider.dataSource, AppConstants.dataSourceWeb);
  });
}
