const lziApiSourceId = 'lziapi';

final _numericVodId = RegExp(r'^\d+$');

bool isNumericVodId(String id) => _numericVodId.hasMatch(id);

String encodeSourceVideoId(String sourceConfigId, String vodId) {
  return sourceConfigId == lziApiSourceId ? vodId : '$sourceConfigId:$vodId';
}

({String sourceConfigId, String vodId})? decodeSourceVideoId(String id) {
  final separator = id.lastIndexOf(':');
  if (separator == 0) return null;

  final vodId = id.substring(separator + 1);
  if (!isNumericVodId(vodId)) return null;

  return (
    sourceConfigId: separator < 0 ? lziApiSourceId : id.substring(0, separator),
    vodId: vodId,
  );
}
