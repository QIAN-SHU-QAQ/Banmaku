import '../../models/video_model.dart';

final _fullWidthAlphanumeric = RegExp(
  r'[\uFF10-\uFF19\uFF21-\uFF3A\uFF41-\uFF5A]',
);
const _voiceLanguages = r'(?:普通话|国语|粤语|日语|国配|日配)';
final _voiceEdition = RegExp(
  r'(?:[\s\[【(（]+'
  '$_voiceLanguages'
  r'版?|'
  '$_voiceLanguages'
  r'版)[\]】)）]*$',
);
final _arcTitle = RegExp(r'^(.*?)(?:[·・:：]\s*(.+?)(?:篇)?|之(.+)篇)$');
final _titleSeparators = RegExp(r'[\s·・:：!！?？《》]+');
final _season = RegExp(r'第([一二三四五六七八九十]|\d+)季$');
const _seasonNumbers = '一二三四五六七八九十';
final _releaseYear = RegExp(r'^[1-9]\d{3}$');

/// 保留搜索排序和片源身份。两个明确不同的年份各自保留一张卡片。
Map<String, List<VideoModel>> groupPlaybackSearchResults(
  List<VideoModel> results,
) {
  final entries =
      results.map((video) {
        final year = video.year?.trim();
        return (
          video: video,
          title: _workTitle(video.title),
          year: year != null && _releaseYear.hasMatch(year) ? year : null,
        );
      }).toList();
  final yearsByTitle = <String, Set<String>>{};
  for (final entry in entries) {
    if (entry.year case final year?) {
      (yearsByTitle[entry.title] ??= {}).add(year);
    }
  }

  final groups = <(String, String?, String?), Map<String, VideoModel>>{};
  for (final entry in entries) {
    final knownYears = yearsByTitle[entry.title];
    final year =
        entry.year ?? (knownYears?.length == 1 ? knownYears!.single : null);
    final id = entry.video.id;
    final key = (entry.title, year, entry.title.isEmpty ? id : null);
    (groups[key] ??= {}).putIfAbsent(id, () => entry.video);
  }
  return {
    for (final versions in groups.values)
      versions.keys.first: versions.values.toList(growable: false),
  };
}

String _workTitle(String title) {
  var text =
      title
          .trim()
          .replaceAllMapped(
            _fullWidthAlphanumeric,
            (match) => String.fromCharCode(match[0]!.codeUnitAt(0) - 0xFEE0),
          )
          .toLowerCase()
          .replaceFirst(_voiceEdition, '')
          .trim();
  final arc = _arcTitle.firstMatch(text);
  if (arc != null) {
    text = arc[1]! + (arc[2] ?? arc[3]!);
  }
  return text.replaceAll(_titleSeparators, '').replaceFirstMapped(_season, (
    match,
  ) {
    final label = match[1]!;
    final number = int.tryParse(label) ?? (_seasonNumbers.indexOf(label) + 1);
    return number == 1 ? '' : '第$number季';
  });
}
