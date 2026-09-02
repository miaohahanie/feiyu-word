import 'package:flutter/material.dart';

class AboutLicensePage extends StatelessWidget {
  const AboutLicensePage({super.key});

  @override
  Widget build(BuildContext context) {
    const text = '''
单词桌宠 · 非商业同人/学习作品

代码许可：MIT License（LICENSE-CODE）
素材许可：CC BY-NC-SA 4.0（LICENSE-ASSETS）
第三方归属与数据说明：NOTICE

素材版权归属：
· 原创角色「鲸鱼娘'溟月'」 © @上善无形（B站）
· 女仆鲸鱼娘（DS鲸鱼娘）二创形象 © @ZipZipPipe（B站）
· 「蓝色大肥鱼」表情包 © @赤风RED LUE UP（B站）

素材仅限非商业用途；二次分发须署名，并按相同协议
（CC BY-NC-SA 4.0）授权。本项目与上述原作者无隶属关系。
完整许可文本见仓库 LICENSE / LICENSE-CODE / LICENSE-ASSETS / NOTICE。
''';

    return Scaffold(
      appBar: AppBar(title: const Text('关于与许可')),
      body: const SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text(text, style: TextStyle(fontSize: 14, height: 1.6)),
          ),
        ),
      ),
    );
  }
}
