// Run: flutter test (from apps/office)
import 'package:flutter_test/flutter_test.dart';
import 'package:office/scan_logic.dart';

void main() {
  final places = [
    {'id': 1, 'code': 'R15-L-S3', 'name': 'Shelf 3'},
    {'id': 2, 'code': null, 'name': 'Untitled'},
  ];
  final assets = [
    {'id': 10, 'tag': 'TL-0042', 'serial': 'SN-100'},
    {'id': 11, 'tag': null, 'serial': 'SN-200'},
    {'id': 12, 'tag': 'TL-0099', 'serial': null},
  ];

  test('a bare place code matches the place, case-insensitively', () {
    final r = resolveCode('  r15-l-s3 ', places, assets);
    expect(r.kind, ScanKind.place);
    expect(r.code, 'r15-l-s3');
    expect(r.row?['id'], 1);
  });

  test('a ?place= URL resolves to the place row', () {
    final r = resolveCode('https://x/office/?place=r15-l-s3', places, assets);
    expect(r.kind, ScanKind.place);
    expect(r.code, 'r15-l-s3');
    expect(r.row?['id'], 1);
  });

  test('a lowercase asset tag matches the asset', () {
    final r = resolveCode('tl-0042', places, assets);
    expect(r.kind, ScanKind.asset);
    expect(r.code, 'tl-0042');
    expect(r.row?['id'], 10);
  });

  test('a ?asset= URL resolves to the asset row', () {
    final r = resolveCode('https://x/office/?asset=SN-100', places, assets);
    expect(r.kind, ScanKind.asset);
    expect(r.code, 'SN-100');
    expect(r.row?['id'], 10);
  });

  test('a serial match works even when the tag is null', () {
    final r = resolveCode('SN-200', places, assets);
    expect(r.kind, ScanKind.asset);
    expect(r.code, 'SN-200');
    expect(r.row?['id'], 11);
  });

  test('nothing matching gives unknown', () {
    final r = resolveCode('nope', places, assets);
    expect(r.kind, ScanKind.unknown);
    expect(r.code, 'nope');
    expect(r.row, isNull);
  });

  test('empty input gives unknown with an empty code', () {
    final r = resolveCode('   ', places, assets);
    expect(r.kind, ScanKind.unknown);
    expect(r.code, '');
    expect(r.row, isNull);
  });

  test('rows with null code/serial/tag do not crash', () {
    expect(resolveCode('SN-200', places, assets).kind, ScanKind.asset,
        reason: 'serial match skips the null tag');
    expect(resolveCode('tl-0099', places, assets).kind, ScanKind.asset,
        reason: 'tag match skips the null serial');
    expect(resolveCode('untitled', places, assets).kind, ScanKind.unknown,
        reason: 'the null-code row is not matched by name');
    expect(resolveCode('https://x/office/', places, assets).kind, ScanKind.unknown,
        reason: 'a URL without place/asset falls back to the trimmed text');
  });
}
