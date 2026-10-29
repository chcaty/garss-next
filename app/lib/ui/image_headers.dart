/// Public image CDNs that require a browser user agent or their site's referer.
Map<String, String> imageRequestHeaders(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null || !{'http', 'https'}.contains(uri.scheme)) return {};
  final host = uri.host.toLowerCase();
  bool within(String domain) => host == domain || host.endsWith('.$domain');
  return {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
        'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
    if (within('doubanio.com')) 'Referer': 'https://movie.douban.com/',
    if (within('hdslb.com')) 'Referer': 'https://www.bilibili.com/',
    if (within('sspai.com')) 'Referer': 'https://sspai.com/',
  };
}
