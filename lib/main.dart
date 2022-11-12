/*
実行例
00 8B
I/flutter (32087): 00 00 00 00 00 00 00 00 32 00 00 B2 29 00 2E B1
09 0F
I/flutter (32087): 16 01 00 17 2D 64 8F 43 D9 52 B2 29 00 2E B1 A0
I/flutter (32087): 16 01 00 02 2D 64 FA B3 FA BE D4 2A 00 2E AF A0
I/flutter (32087): 1A 06 00 0E 2D 64 D9 52 D9 52 EC 2B 00 2E AD A0
I/flutter (32087): C8 46 00 00 2D 63 5C 84 01 35 EC 2B 00 2E AB 00
I/flutter (32087): C8 46 00 00 2D 62 A9 04 01 35 F4 2D 00 2E AA 00
I/flutter (32087): 16 01 00 17 2D 62 8F 43 D9 52 FC 2F 00 2E A9 A0
I/flutter (32087): 16 01 00 17 2D 62 D9 52 8F 43 1E 31 00 2E A7 A0
I/flutter (32087): 16 01 00 17 2D 61 8F 43 D9 52 40 32 00 2E A5 A0
I/flutter (32087): 16 01 00 17 2D 61 D9 52 8F 43 62 33 00 2E A3 A0
I/flutter (32087): 16 01 00 17 2D 5F 8F 43 D9 52 84 34 00 2E A1 A0
I/flutter (32087): 16 01 00 17 2D 5F D9 52 8F 43 A6 35 00 2E 9F A0
I/flutter (32087): 08 02 00 00 2D 5E FA B3 00 00 C8 36 00 2E 9D 80
*/

import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/platform_tags.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(MyApp());
}

class MyApp extends StatefulWidget {
  @override
  State<StatefulWidget> createState() => MyAppState();
}

class MyAppState extends State<MyApp> {
  String _message = '';
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: Scaffold(
        body: SafeArea(
          child: Stack(
            children: myWidgets()
          ),
        )
      )
    );
  }

  List<Widget> myWidgets(){
    return <Widget>[
      Positioned(
        bottom: 60.0, left:0.0, right:0,
        child: IconButton(
          icon: Icon(Icons.play_circle_fill, size:60, color:Colors.white),
          onPressed:() => onStart(),
        ),
      ),
      Positioned(
        left:30, right:30, top:50, bottom:120,
        child:Container(
          padding: EdgeInsets.all(14.0),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white, width:1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(_message, style:TextStyle(fontSize:20)),
        )
      ),
    ];
  }

  msg(String s){
    print(s);
    setState(() {
      _message = s;
    });
  }

  /// onStart
  Future onStart() async {
    if(NfcManager.instance.isAvailable()==false){
      msg('NFC is not available');
      return;
    }
    msg('Please touch Suica');
    try {
      await NfcManager.instance.startSession(
        alertMessage: "Please touch Suica",
        onDiscovered: (tag) async {
          try {
            if (Platform.isIOS)
              await onDiscoveredForIos(tag);
            else if (Platform.isAndroid)
              await onDiscoveredForAndroid(tag);
          } catch (e) {
            msg('Error\n${e.toString()}');
            NfcManager.instance.stopSession(errorMessage: 'Error ${e.toString()}');
          }
          print('stopSession');
          NfcManager.instance.stopSession();
        },
      );
    } catch (e) {
      msg('Error\n${e.toString()}');
    }
  }

  /// iOS向け
  Future onDiscoveredForIos(NfcTag tag) async {
    final felica = FeliCa.from(tag);
    if (felica == null) {
      msg("Unsupported card for type FeliCa");
      return;
    }

    // 属性情報(008B)から残高を取得
    final res = await felica.readWithoutEncryption(
      serviceCodeList: [Uint8List.fromList([0x8b,0x00])],
      blockList: [Uint8List.fromList([0x80,0])],
    );
    // 残高[11][12]
    int balance = -1;
    if (res.blockData.length > 0) {
      balance = res.blockData[0][12] * 256 + res.blockData[0][11];
    }

    // 利用履歴(090F)から履歴20件を取得 ※一度に12件まで
    final list1 = [for (int i=0; i<12; i++) Uint8List.fromList([0x80,i])];
    final res1 = await felica.readWithoutEncryption(
      serviceCodeList: [Uint8List.fromList([0x0f,0x09])],
      blockList: list1,
    );
    final list2 = [for (int i=12; i<20; i++) Uint8List.fromList([0x80,i])];
    final res2 = await felica.readWithoutEncryption(
      serviceCodeList: [Uint8List.fromList([0x0f,0x09])],
      blockList: list2,
    );
    final blocklist = [...res1.blockData, ...res2.blockData];

    String histories = '';
    for (List<int> b in blocklist) {
      // 年月日[4][5](7bit 4bit 5bit)
      int idate = b[4] * 256 + b[5];
      String y = ((idate & 0xFE00) >> 9).toString();
      String m = ((idate & 0x01E0) >> 5).toString().padLeft(2,'0');
      String d = ((idate & 0x001F) >> 0).toString().padLeft(2,'0');
      histories += '${y}-${m}-${d}';
      // 残高[10][11]
      histories += '  ' + (b[11] * 256 + b[10]).toString().padLeft(5,' ') + ' yen';
      histories += '\n';
    }

    String s = '';
    s += 'IDm ${intlist_to_string(felica.currentIDm)}\n';
    s += 'SystemCode ${intlist_to_string(felica.currentSystemCode)}\n';
    s += 'Balance ${balance} yen\n';
    s += histories;
    msg(s);

    NfcManager.instance.stopSession(alertMessage: 'Succeeded');
  }

  /// アンドロイド向け
  Future onDiscoveredForAndroid(NfcTag tag) async {
    final nfcf = NfcF.from(tag);
    if (nfcf == null) {
      msg('Unsupported card for NFC type F');
      return;
    }
    Uint8List IDm = nfcf.identifier;

    // 属性情報(008B)から残高を取得
    final list = [0x80,0];
    List<List<int>> res = await _readWithoutEncryption(
        nfcf:nfcf,
        IDm:IDm,
        serviceCode:[0x8b,0x00],
        blockCount:1,
        blockList:list);

    // 残高[11][12]
    int balance = -1;
    if(res.length>0)
      balance = res[0][12] * 256 + res[0][11];

    // 利用履歴(090F)から履歴20件を取得 ※一度に12件まで
    List<int> list1=[];
    for (int i=0; i<12; i++) list1.addAll([0x80,i]);
    List<List<int>> res1 = await _readWithoutEncryption(
        nfcf:nfcf,
        IDm:IDm,
        serviceCode:[0x0f,0x09],
        blockCount:12,
        blockList:list1);

    List<int> list2=[];
    for (int i=12; i<20; i++) list2.addAll([0x80,i]);
    List<List<int>> res2 = await _readWithoutEncryption(
        nfcf:nfcf,
        IDm:IDm,
        serviceCode:[0x0f,0x09],
        blockCount:8,
        blockList:list2);
    List<List<int>> blocklist = [...res1,...res2];

    String histories = '';
    for(List<int> b in blocklist) {
      // 年月日[4][5](7bit 4bit 5bit)
      int idate = b[4] * 256 + b[5];
      String y = ((idate & 0xFE00) >> 9).toString();
      String m = ((idate & 0x01E0) >> 5).toString().padLeft(2,'0');
      String d = ((idate & 0x001F) >> 0).toString().padLeft(2,'0');
      histories += '${y}-${m}-${d}';
      // 残高[10][11]
      histories += '  ' + (b[11] * 256 + b[10]).toString().padLeft(5,' ') + ' yen';
      histories += '\n';
    }

    String s = '';
    s += 'IDm ${intlist_to_string(nfcf.identifier)}\n';
    s += 'SystemCode ${intlist_to_string(nfcf.systemCode)}\n';
    s += 'Balance ${balance} yen\n';
    s += histories;
    msg(s);
  }

  /// コマンド Read Without Encryption (0x06) の送受信
  /// - nfcf Android 向け
  /// - IDm 固有ID 8バイト
  /// - serviceCode 属性情報(008B) 利用履歴(090F)
  /// - blockCount 受信ブロック数
  /// - blockList 受信ブロック
  /// - 戻り値 16バイトのリスト
  Future<List<List<int>>> _readWithoutEncryption({
    required NfcF nfcf,
    required List<int> IDm,
    required List<int> serviceCode,
    required int blockCount,
    required List<int> blockList }) async {
    List<int> cmd = [];
    cmd.add(0x00);           // コマンド長（後で）
    cmd.add(0x06);           // コマンドコード 06 Read Without Encryption
    cmd.addAll(IDm);         // IDm (8byte)
    cmd.add(0x01);           // サービス数
    cmd.addAll(serviceCode); // サービスコード
    cmd.add(blockCount);     // 受信ブロックの数
    cmd.addAll(blockList);   // 受信ブロック
    cmd[0] = cmd.length;     // コマンド長

    List<List<int>> blist = [];
    try {
      Uint8List res = await nfcf.transceive(data:Uint8List.fromList(cmd));

      // 応答データから16バイトのブロックリストを取得
      // [10] 0x00が成功
      // [12] 16バイトのブロックの数
      // [13] 以降16バイトのブロックが続く
      if (res.length >= 11 && res[10] == 0x00){
        int nblock = res[12];
        for (var i=0; i<nblock; i++){
          List<int> b = [];
          for (int j=0; j<16; j++){
            int k = 13 + (16*i) + j;
            if (res.length > k)
              b.add(res[k]);
          }
          blist.add(b);
          print(intlist_to_string(b));
        }
      } else {
        print('faild res.length ${res.length}');
        if(res.length>10) print('faild res[10] ${res[10]} (OK=0x00)');
      }
    } catch (e) {
      msg('Error:${e.toString()}');
      return blist;
    }
    return blist;
  }

  /// Uint8Listを16進数の文字列に変換（デバッグ用）
  String intlist_to_string(List<int> list){
    String s = '';
    for(int i in list){
      s += i.toRadixString(16).toUpperCase().padLeft(2,'0') + ' ';
    }
    return s;
  }
}
