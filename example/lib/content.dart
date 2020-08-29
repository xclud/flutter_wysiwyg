import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:wysiwyg/wysiwyg.dart';

InlineSpan _createLink(String uri, [String text]) {
  return TextSpan(
    text: text ?? uri,
    style: TextStyle(color: Colors.blue.shade700),
    recognizer: TapGestureRecognizer()..onTap = () {},
  );
}

InlineSpan _createText(String text) {
  return TextSpan(text: text);
}

TextEditingController c = TextEditingController();

class ContentWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SelectableTextWithToolbar.rich(
      TextSpan(
        children: [
          _createText('به نظر من'),
          _createText(' '),
          _createLink('http://www.google.com', 'گوگل'),
          _createText(' '),
          _createText('سایت خیلی خوبی هست.'),
          _createText(
              'چون در این سایت میشه کارهای خیلی بزرگی انجام داد. چون در این سایت میشه کارهای خیلی بزرگی انجام داد. چون در این سایت میشه کارهای خیلی بزرگی انجام داد. چون در این سایت میشه کارهای خیلی بزرگی انجام داد. چون در این سایت میشه کارهای خیلی بزرگی انجام داد. چون در این سایت میشه کارهای خیلی بزرگی انجام داد. چون در این سایت میشه کارهای خیلی بزرگی انجام داد. '),
        ],
      ),
      textDirection: TextDirection.rtl,
      scrollPhysics: ClampingScrollPhysics(),
      showCursor: true,
      toolbarBuilder: (d) => [
        IconButton(
          icon: Icon(Icons.format_clear),
          onPressed: () {
            //d.hideToolbar();
          },
          tooltip: 'Normal',
        ),
        IconButton(
          icon: Icon(Icons.format_bold),
          onPressed: () {
            //d.hideToolbar();
          },
          tooltip: 'Bold',
        ),
        VerticalDivider(),
        IconButton(
          icon: Icon(Icons.close),
          onPressed: () {
            d.hideToolbar();
          },
          tooltip: 'Close',
        ),
      ],
    );
  }
}
