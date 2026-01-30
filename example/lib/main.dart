import 'package:flutter/material.dart';
import 'dart:async';

import 'package:flutter_keyboard_scroll/keyboard_observer.dart';
import 'package:flutter_keyboard_scroll/keyboard_scroll.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  ///底部
  double _marginBottom = 0;

  @override
  void initState() {
    super.initState();
    initPlatformState();
  }

  // Platform messages are asynchronous, so we initialize in an async method.
  Future<void> initPlatformState() async {}

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        resizeToAvoidBottomInset: false,
        appBar: AppBar(
          title: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () {
              FocusScope.of(context).requestFocus(FocusNode());
            },
            child: const Text('Plugin example app'),
          ),
        ),
        body: KeyboardObserver(
          showListener: (double former, double newer, int time) {
            print("AAA:::$newer");
          },
          hideListener: (double former, double newer, int time) {
            print("BBB:::$newer");
          },
          showAnimationListener: (value, flag) {
            print("AAAA:::$value");
            setState(() {
              _marginBottom = value;
            });
          },
          hideAnimationListener: (value, flag) {
            print("BBBB:::$value");
            setState(() {
              _marginBottom = value;
            });
          },
          animationMode: KeyboardAnimationMode.mediaQuery,
          child: Container(
            width: double.infinity,
            height: double.infinity,
            alignment: Alignment.bottomCenter,
            child: Container(
              width: MediaQuery.of(context).size.width,
              decoration: const BoxDecoration(
                color: Colors.red,
              ),
              margin: EdgeInsets.fromLTRB(0, 0, 0, _marginBottom),
              height: 45,
              child: const TextField(
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  hintText: "Input your words",
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
