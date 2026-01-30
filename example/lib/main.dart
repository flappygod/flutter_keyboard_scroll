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
          },
          hideAnimationListener: (value, flag) {
            print("BBBB:::$value");
          },
          animationMode: KeyboardAnimationMode.mediaQuery,
          child: Container(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              width: MediaQuery.of(context).size.width,
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
