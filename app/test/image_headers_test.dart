import 'package:flutter_test/flutter_test.dart';
import 'package:garss_app/ui/image_headers.dart';

void main() {
  test('public image CDNs receive their required site referer', () {
    expect(
      imageRequestHeaders('https://img9.doubanio.com/cover.jpg')['Referer'],
      'https://movie.douban.com/',
    );
    expect(
      imageRequestHeaders('https://i1.hdslb.com/cover.jpg')['Referer'],
      'https://www.bilibili.com/',
    );
    expect(
      imageRequestHeaders('https://cdn.sspai.com/cover.png')['Referer'],
      'https://sspai.com/',
    );
    expect(
      imageRequestHeaders('https://github.com/avatar.png')['User-Agent'],
      startsWith('Mozilla/'),
    );
  });
  test('referer matching requires an exact host suffix', () {
    expect(
      imageRequestHeaders('https://doubanio.com.example.org/x')
          .containsKey('Referer'),
      isFalse,
    );
    expect(imageRequestHeaders('javascript:alert(1)'), isEmpty);
  });
}
