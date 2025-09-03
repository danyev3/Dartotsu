import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dartotsu/Api/Anilist/Anilist.dart';
import 'package:dartotsu/Functions/Function.dart';
import 'package:dartotsu/Screens/Home/HomeScreen.dart';
import 'package:dartotsu/Theme/LanguageSwitcher.dart';
import 'package:dartotsu/logger.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class LoginTvScreen extends StatefulWidget {
  const LoginTvScreen({super.key});

  @override
  LoginTvScreenState createState() => LoginTvScreenState();
}

class LoginTvScreenState extends State<LoginTvScreen> {
  String _code = '';
  RawDatagramSocket? _socket;
  Timer? _broadcastTimer;
  String? _ipAddress;
  bool _timedOut = false;
  Timer? _timeoutTimer;

  @override
  void initState() {
    super.initState();
    _init();
  }

  void _init() async {
    setState(() {
      _timedOut = false;
    });
    _generateCode();
    await _getIpAddress();
    _startUdpListener();
    _startBroadcasting();
    _startTimeoutTimer();
  }

  void _startTimeoutTimer() {
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(const Duration(minutes: 5), () {
      if (mounted) {
        setState(() {
          _timedOut = true;
        });
      }
    });
  }

  void _generateCode() {
    final random = Random();
    _code = (10000 + random.nextInt(90000)).toString();
  }

  Future<void> _getIpAddress() async {
    for (var interface in await NetworkInterface.list()) {
      for (var addr in interface.addresses) {
        if (addr.type == InternetAddressType.IPv4) {
          _ipAddress = addr.address;
          return;
        }
      }
    }
  }

  void _startBroadcasting() {
    if (_ipAddress == null) return;

    _broadcastTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      try {
        final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
        socket.broadcastEnabled = true;
        final data = {
          'ip': _ipAddress,
          'code': _code,
        };
        socket.send(
          utf8.encode(jsonEncode(data)),
          InternetAddress('255.255.255.255'),
          45679, // Discovery port
        );
        socket.close();
      } catch (e, s) {
        Logger.log('Broadcast error: $e\n$s', logLevel: LogLevel.error);
      }
    });
  }

  void _startUdpListener() async {
    try {
      _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 45678);
      _socket?.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          final datagram = _socket?.receive();
          if (datagram != null) {
            final message = utf8.decode(datagram.data);
            try {
              final data = jsonDecode(message);
              final encryptedToken = data['token'];
              final mobileIp = data['ip'];
              final decryptedToken = _decryptToken(encryptedToken);
              _login(decryptedToken, mobileIp);
            } catch (e, s) {
              Logger.log('Message format error: $e\n$s',
                  logLevel: LogLevel.error);
            }
          }
        }
      });
    } catch (e, s) {
      Logger.log('Listen error: $e\n$s', logLevel: LogLevel.error);
    }
  }

  String _decryptToken(String encryptedToken) {
    final key = encrypt.Key.fromUtf8(_code.padRight(16));
    final iv = encrypt.IV.fromLength(16);
    final encrypter = encrypt.Encrypter(encrypt.AES(key));

    final decrypted =
        encrypter.decrypt(encrypt.Encrypted.fromBase64(encryptedToken), iv: iv);
    return decrypted;
  }

  void _login(String token, String mobileIp) async {
    Anilist.setToken(token);

    // Send confirmation
    try {
      final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.send(
        utf8.encode('OK'),
        InternetAddress(mobileIp),
        45680, // Confirmation port
      );
      socket.close();
    } catch (e, s) {
      Logger.log('Confirmation error: $e\n$s', logLevel: LogLevel.error);
    }

    Get.offAll(() => const HomeScreen());
  }

  @override
  void dispose() {
    _socket?.close();
    _broadcastTimer?.cancel();
    _timeoutTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_timedOut) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Login timed out. Please try again.'),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _init,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              getString.loginOnTv,
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Text(
              _code,
              style: Theme.of(context)
                  .textTheme
                  .displayLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            const CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
