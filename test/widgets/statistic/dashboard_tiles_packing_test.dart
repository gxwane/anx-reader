import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/main.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/dashboard_tile_metadata.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/dashboard_tile_registry.dart';
import 'package:anx_reader/widgets/statistic/statistics_dashboard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Statistics Dashboard Tiles Packing & Geometry Integrity', () {
    testWidgets('defaultStatisticsDashboardTiles packs perfectly into 4-col and 8-col grids without cavities',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          locale: const Locale('en'),
          home: const Scaffold(body: SizedBox()),
        ),
      );
      await tester.pumpAndSettle();

      final tiles = defaultStatisticsDashboardTiles;

      // Group 1: The top row in 8-col mode must be formed by rowSpan=1 tiles totaling columnSpan=8
      // and in 4-col mode, it must cleanly divide into two rowSpan=1 rows of columnSpan=4.
      final row1SubGroup = tiles.sublist(0, 3);
      final row1SubGroupCols = row1SubGroup.fold<int>(
        0,
        (sum, type) => sum + dashboardTileRegistry[type]!.metadata.columnSpan,
      );
      expect(row1SubGroupCols, 4,
          reason: 'The first 3 tiles (days, books, period) must occupy exactly 4 columns');

      for (final type in row1SubGroup) {
        expect(dashboardTileRegistry[type]!.metadata.rowSpan, 1,
            reason: '$type must be 1 row tall');
      }

      final row2SubGroup = tiles.sublist(3, 5);
      final row2SubGroupCols = row2SubGroup.fold<int>(
        0,
        (sum, type) => sum + dashboardTileRegistry[type]!.metadata.columnSpan,
      );
      expect(row2SubGroupCols, 4,
          reason: 'The 7-day and 30-day trend tiles must occupy exactly 4 columns');

      for (final type in row2SubGroup) {
        expect(dashboardTileRegistry[type]!.metadata.rowSpan, 1,
            reason: '$type must be 1 row tall');
      }

      // Together, the first 5 tiles must form an 8-col x 1-row block in 8-col mode (or two 4-col x 1-row rows in 4-col mode)
      final topBand = tiles.sublist(0, 5);
      final topBandTotalCols = topBand.fold<int>(
        0,
        (sum, type) => sum + dashboardTileRegistry[type]!.metadata.columnSpan,
      );
      expect(topBandTotalCols, 8,
          reason: 'The 1-row tiles must combine to exactly 8 columns to pack cleanly on wide screens');

      // The rest of the default tiles must be rowSpan=2 items that align in multiples of 4 columns
      final remainingTiles = tiles.sublist(5);
      for (final type in remainingTiles) {
        final meta = dashboardTileRegistry[type]!.metadata;
        expect(meta.rowSpan, 2, reason: '$type must be 2 rows tall');
      }

      final remainingCols = remainingTiles.fold<int>(
        0,
        (sum, type) => sum + metaFor(type).columnSpan,
      );
      expect(remainingCols % 4, 0,
          reason: 'Remaining tiles must form blocks that are multiples of 4 columns');
    });

    test('calculateColumnUnits strictly aligns to 4-column base grid (no 6-column tearing)', () {
      // Narrow / mobile screens (< 800px) must stay at 4 columns
      expect(StatisticsDashboard.calculateColumnUnits(300), 4);
      expect(StatisticsDashboard.calculateColumnUnits(450), 4);
      expect(StatisticsDashboard.calculateColumnUnits(600), 4);
      expect(StatisticsDashboard.calculateColumnUnits(750), 4);

      // Wide screens (>= 800px) step to 8 columns
      expect(StatisticsDashboard.calculateColumnUnits(800), 8);
      expect(StatisticsDashboard.calculateColumnUnits(1000), 8);
      expect(StatisticsDashboard.calculateColumnUnits(1199), 8);

      // Ultra-wide screens (>= 1200px) step to 12 columns
      expect(StatisticsDashboard.calculateColumnUnits(1200), 12);
      expect(StatisticsDashboard.calculateColumnUnits(1600), 16);
    });
  });
}

StatisticsDashboardTileMetadata metaFor(StatisticsDashboardTileType type) =>
    dashboardTileRegistry[type]!.metadata;
