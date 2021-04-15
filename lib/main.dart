import 'dart:async';
import 'dart:io';

import 'package:consumer/consumer.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

SharedPreferences fs;
Future main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isAndroid) {
    await AndroidInAppWebViewController.setWebContentsDebuggingEnabled(true);
  }
  fs = await SharedPreferences.getInstance();
  consumer.state.url = fs.getString("url") ?? "https://aoife.writeflowy.com";
  consumer.state.barHeight = fs.getDouble("barHeight") ?? 32.0;
  consumer.state.light = fs.getBool("light") ?? true;
  await Permission.camera.request();

  await Permission.microphone.request(); // if you need microphone permission
  if (consumer.state.light) {
    light();
  } else {
    dark();
  }
  runApp(MyApp());
}

class AppState {
  bool light = true;
  String url = "";
  double barHeight = 32.0;
  Function reloadURL = () {};
}

var consumer = Consumer(AppState());

light() {
  SystemUiOverlayStyle systemUiOverlayStyle = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent, //全局设置透明
      statusBarIconBrightness: Brightness.dark);
  SystemChrome.setSystemUIOverlayStyle(systemUiOverlayStyle);
}

dark() {
  SystemUiOverlayStyle systemUiOverlayStyle = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent, //全局设置透明
      statusBarIconBrightness: Brightness.light);
  SystemChrome.setSystemUIOverlayStyle(systemUiOverlayStyle);
}

loadLocal() {
  consumer.state.url = fs.getString("url") ?? "https://aoife.writeflowy.com";
  consumer.state.barHeight = fs.getDouble("barHeight") ?? 32.0;
  consumer.state.light = fs.getBool("light") ?? true;
}

setLocal() {
  fs.setString("url", consumer.state.url);
  fs.setDouble("barHeight", consumer.state.barHeight);
  fs.setBool("light", consumer.state.light);
  if (consumer.state.light) {
    light();
  } else {
    dark();
  }
}

jsHandle(InAppWebViewController controller) {
  controller.evaluateJavascript(source: """
  window.isFlutter = true;
  window.flutterCall = function(...args){
    // 操蛋，handler 字符串必须带 handle
    return window.flutter_inappwebview.callHandler('myHandlerName', ...args);
  }
  """);

  // js-to-flutter 交互方案:
  // window.addEventListener("flutterInAppWebViewPlatformReady", function(event) {
  //     // flutter, barHeight, isLight, url
  //     window.flutter_inappwebview.callHandler('myHandlerName', 32, true, "https://aoife.writeflowy.com")
  //       .then(function(result) {
  //         // print to the console the data coming
  //         // from the Flutter side.
  //         console.log(JSON.stringify(result));
  //     });
  //   });

  controller.addJavaScriptHandler(
      handlerName: 'myHandlerName',
      callback: (args) {
        Map<String, Object> obj = args[0];

        if (obj == null) {
          return {'error': "args 参数为空"};
        }
        if (obj["barHeight"] != null) {
          consumer.state.barHeight = obj["barHeight"];
        }

        if (obj["light"] != null) {
          consumer.state.light = obj["light"];
        }

        if (obj["url"] != null) {
          var nextUrl = obj["url"];
          if (consumer.state.url != nextUrl) {
            consumer.state.url = nextUrl;
            consumer.state.reloadURL();
          }
        }

        consumer.setState((state) => {});
        loadLocal();

        return {
          'light': consumer.state.light,
          'barHeight': consumer.state.barHeight,
          'url': consumer.state.url,
        };
      });

  controller.addJavaScriptHandler(
    handlerName: 'consumer',
    callback: (args) {
      consumer.state.barHeight =
          args[0]["barHeight"] ?? consumer.state.barHeight;
      consumer.state.light = args[0]["light"] ?? consumer.state.light;

      var nextUrl = args[0]["url"] ?? consumer.state.url;
      var needReload = consumer.state.url != nextUrl;
      consumer.state.url = nextUrl;

      consumer.setState((state) {});
      if (needReload) {
        consumer.state.reloadURL();
      }
      return {
        'light': consumer.state.light,
        'barHeight': consumer.state.barHeight,
        'url': consumer.state.url,
      };
    },
  );
}

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      initialRoute: "/",
      routes: {
        "/": (BuildContext context) => WebPage(),
        "/setting": (BuildContext context) => Setting(),
      },
    );
  }
}

class WebPage extends StatefulWidget {
  @override
  _WebPageState createState() => _WebPageState();
}

class _WebPageState extends State<WebPage> {
  var _lastTime = DateTime.now().microsecondsSinceEpoch;

  int _tapNum = 0;
  var _lastUrl = consumer.state.url;
  final GlobalKey webViewKey = GlobalKey();
  void _showAlert() {
    Navigator.pushNamed(context, "/setting");
  }

  _handleTapNum(BuildContext context) {
    var _now = DateTime.now().millisecondsSinceEpoch;

    if (_tapNum >= 2) {
      _showAlert();
      _tapNum = 0;
    } else {
      var diff = _now - _lastTime;
      if (diff < 3000) {
        _tapNum += 1;
      } else {
        _tapNum = 0;
      }
    }

    _lastTime = _now;
    setState(() {});
  }

  InAppWebViewController _controller;

  @override
  void initState() {
    super.initState();
    consumer.state.reloadURL = () {
      if (_controller != null) {
        _controller.loadUrl(
            urlRequest: URLRequest(url: Uri.parse(consumer.state.url)));
      }
    };
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: GestureDetector(
        onLongPress: () {
          _handleTapNum(context);
        },
        child: consumer.build(
          (ctx, state) {
            if (_lastUrl != consumer.state.url) {
              _lastUrl = consumer.state.url;
            }
            return Scaffold(
              body: Container(
                color: state.light ? Colors.white : Colors.black,
                child: Column(
                  children: [
                    Container(
                      height: state.barHeight,
                    ),
                    Expanded(
                      child: InAppWebView(
                        onLoadStop: (controller, url) {
                          jsHandle(controller);
                        },
                        onWebViewCreated: (ctrl) {
                          _controller = ctrl;
                          // jsHandle(ctrl);
                        },
                        // key: webViewKey,
                        initialUrlRequest: URLRequest(
                          url: Uri.parse(consumer.state.url),
                        ),
                        androidOnPermissionRequest:
                            (controller, origin, resources) async {
                          return PermissionRequestResponse(
                              resources: resources,
                              action: PermissionRequestResponseAction.GRANT);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
          memo: (state) => [state.barHeight, state.url],
        ),
      ),
    );
  }
}

class Setting extends StatefulWidget {
  @override
  _SettingState createState() => _SettingState();
}

class _SettingState extends State<Setting> {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      child: Scaffold(
        body: Container(
          padding: EdgeInsets.all(20),
          child: ListView(
            children: [
              Row(
                children: [
                  Text("导航栏是否 Theme Light："),
                  consumer.build(
                      (ctx, state) => Switch(
                            value: consumer.state.light,
                            onChanged: (ok) {
                              consumer.setState((state) {
                                state.light = ok;
                              });
                            },
                          ),
                      memo: (state) => [state.light])
                ],
              ),
              TextField(
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                ],
                controller: new TextEditingController(
                    text: consumer.state.barHeight.toString()),
                onChanged: (text) {
                  consumer.state.barHeight = double.tryParse(text) ?? 32.0;
                },
                decoration: InputDecoration(hintText: "设置顶部高度"),
              ),
              TextField(
                controller: new TextEditingController(text: consumer.state.url),
                onChanged: (text) {
                  consumer.state.url = text;
                },
                decoration: InputDecoration(hintText: "请输入URL"),
              ),
              TextButton(
                child: Text("确定"),
                onPressed: () {
                  setLocal();
                  Timer(Duration(milliseconds: 500), () {
                    consumer.setState((state) {});
                    consumer.state.reloadURL();
                    Navigator.of(context).pop();
                  });
                },
              ),
            ],
          ),
        ),
      ),
      behavior: HitTestBehavior.translucent,
      onTap: () {
        FocusScope.of(context).requestFocus(FocusNode());
      },
    );
  }
}
