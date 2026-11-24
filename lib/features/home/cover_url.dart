String? discoveryCoverUrl(String? value) {
  final cover = value?.trim();
  if (cover == null || cover.isEmpty) return null;
  final uri = Uri.tryParse(cover);
  if (uri == null) return null;
  final resolved = Uri.parse('https://yhdm.me').resolveUri(uri);
  if ((!resolved.isScheme('https') && !resolved.isScheme('http')) ||
      resolved.host.isEmpty) {
    return null;
  }
  return resolved.toString();
}
