import 'dart:convert';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dartotsu/Functions/Function.dart';
import 'package:dartotsu/Screens/Settings/BaseSettingsScreen.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../Api/Anilist/Anilist.dart';
import '../../Api/Discord/Discord.dart';
import '../../Api/MyAnimeList/Mal.dart';
import '../../Api/Simkl/Simkl.dart';
import '../../Theme/LanguageSwitcher.dart';
import '../../Widgets/AlertDialogBuilder.dart';
import '../../Widgets/LoadSvg.dart';

class SettingsAccountScreen extends StatefulWidget {
  const SettingsAccountScreen({super.key});

  @override
  State<StatefulWidget> createState() => SettingsAccountScreenState();
}

class SettingsAccountScreenState extends BaseSettingsScreen {
  @override
  String title() => getString.account;

  @override
  Widget icon() => Padding(
        padding: const EdgeInsets.only(right: 16),
        child: Icon(
          size: 52,
          Icons.person,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      );

  @override
  List<Widget> get settingsList => _buildSettings(context);

  List<Widget> _buildSettings(BuildContext context) {
    return [
      _buildAccountSection(
        context,
        iconPath: 'assets/svg/anilist.svg',
        title: getString.anilist,
        isLoggedIn: Anilist.token,
        username: Anilist.username,
        avatarUrl: Anilist.avatar,
        onLogOut: () => AlertDialogBuilder(context)
          ..setTitle(getString.logout(getString.anilist))
          ..setMessage(getString.confirmLogout)
          ..setPositiveButton(getString.yes, Anilist.removeSavedToken)
          ..setNegativeButton(getString.no, null)
          ..show(),
        onLogIn: () => Anilist.login(context),
      ),
      _buildAccountSection(
        context,
        iconPath: 'assets/svg/mal.svg',
        title: getString.mal,
        isLoggedIn: Mal.token,
        username: Mal.username,
        avatarUrl: Mal.avatar,
        onLogOut: () => AlertDialogBuilder(context)
          ..setTitle(getString.logout(getString.mal))
          ..setMessage(getString.confirmLogout)
          ..setPositiveButton(getString.yes, Mal.removeSavedToken)
          ..setNegativeButton(getString.no, null)
          ..show(),
        onLogIn: () => Mal.login(context),
      ),
      _buildAccountSection(
        context,
        iconPath: 'assets/svg/simkl.svg',
        title: getString.simkl,
        isLoggedIn: Simkl.token,
        username: Simkl.username,
        avatarUrl: Simkl.avatar,
        onLogOut: () => AlertDialogBuilder(context)
          ..setTitle(getString.logout(getString.simkl))
          ..setMessage(getString.confirmLogout)
          ..setPositiveButton(getString.yes, Simkl.removeSavedToken)
          ..setNegativeButton(getString.no, null)
          ..show(),
        onLogIn: () => Simkl.login(context),
      ),
      _buildAccountSection(
        context,
        iconPath: 'assets/svg/discord.svg',
        title: getString.discord,
        isLoggedIn: Discord.token,
        username: Discord.userName,
        avatarUrl: Discord.avatar,
        onLogOut: () => AlertDialogBuilder(context)
          ..setTitle(getString.logout(getString.discord))
          ..setMessage(getString.confirmLogout)
          ..setPositiveButton(getString.yes, Discord.removeSavedToken)
          ..setNegativeButton(getString.no, null)
          ..show(),
        onLogIn: () => Discord.warning(context),
      ),
      ListTile(
        leading: const Icon(Icons.tv),
        title: Text(getString.loginOnTvTitle),
        onTap: () => _showLoginOnTvDialog(context),
      ),
    ];
  }

  RawDatagramSocket? _discoverySocket;
  final Map<String, String> _discoveredTvs = {};

  void _showLoginOnTvDialog(BuildContext context) {
    final codeController = TextEditingController();
    bool isLoading = false;

    _startDiscovery();

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(getString.loginOnTvTitle),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isLoading)
                    const CircularProgressIndicator()
                  else
                    TextField(
                      controller: codeController,
                      keyboardType: TextInputType.number,
                      maxLength: 5,
                      decoration: InputDecoration(
                        labelText: getString.loginOnTvCodePrompt,
                      ),
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    _stopDiscovery();
                    Navigator.of(context).pop();
                  },
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: isLoading
                      ? null
                      : () async {
                          setState(() {
                            isLoading = true;
                          });
                          await _sendTokenToTV(codeController.text);
                          setState(() {
                            isLoading = false;
                          });
                        },
                  child: const Text('Connect'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _startDiscovery() async {
    try {
      _discoverySocket =
          await RawDatagramSocket.bind(InternetAddress.anyIPv4, 45679);
      _discoverySocket?.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          final datagram = _discoverySocket?.receive();
          if (datagram != null) {
            final message = utf8.decode(datagram.data);
            try {
              final data = jsonDecode(message);
              _discoveredTvs[data['code']] = data['ip'];
            } catch (e) {
              // Handle message format error
            }
          }
        }
      });
    } catch (e) {
      // Handle listen error
    }
  }

  void _stopDiscovery() {
    _discoverySocket?.close();
    _discoveredTvs.clear();
  }

  Future<String?> _getIpAddress() async {
    for (var interface in await NetworkInterface.list()) {
      for (var addr in interface.addresses) {
        if (addr.type == InternetAddressType.IPv4) {
          return addr.address;
        }
      }
    }
    return null;
  }

  void _sendTokenToTV(String code) async {
    if (code.length != 5) {
      snackString(getString.loginOnTvInvalidCode);
      return;
    }

    final tvIp = _discoveredTvs[code];
    if (tvIp == null) {
      snackString('TV not found. Make sure you are on the same network.');
      return;
    }

    final mobileIp = await _getIpAddress();
    if (mobileIp == null) {
      snackString('Could not get mobile IP address.');
      return;
    }

    final token = Anilist.token.value;
    if (token.isEmpty) {
      snackString(getString.loginOnTvNoToken);
      return;
    }

    final encryptedToken = _encryptToken(token, code);
    final data = {
      'token': encryptedToken,
      'ip': mobileIp,
    };

    try {
      final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.send(
        utf8.encode(jsonEncode(data)),
        InternetAddress(tvIp),
        45678,
      );
      socket.close();

      // Listen for confirmation
      final confirmationSocket =
          await RawDatagramSocket.bind(InternetAddress.anyIPv4, 45680);
      confirmationSocket.timeout(const Duration(seconds: 10), onTimeout: (sink) {
        snackString('Login timed out. Please try again.');
        sink.close();
      });
      confirmationSocket.listen((event) {
        if (event == RawSocketEvent.read) {
          final datagram = confirmationSocket.receive();
          if (datagram != null && utf8.decode(datagram.data) == 'OK') {
            snackString(getString.loginOnTvSuccess);
            confirmationSocket.close();
          }
        }
      });
    } catch (e) {
      snackString(getString.loginOnTvError);
    }
  }

  String _encryptToken(String token, String code) {
    final key = encrypt.Key.fromUtf8(code.padRight(16));
    final iv = encrypt.IV.fromLength(16);
    final encrypter = encrypt.Encrypter(encrypt.AES(key));

    final encrypted = encrypter.encrypt(token, iv: iv);
    return encrypted.base64;
  }

  Widget _buildAccountSection(
    BuildContext context, {
    String? iconPath,
    Widget? icon,
    required String title,
    required RxString isLoggedIn,
    required RxString username,
    required RxString avatarUrl,
    required Function() onLogOut,
    required Function() onLogIn,
    Function()? onAvatarTap,
    Function()? onIconTap,
    Function()? onIconLongTap,
  }) {
    var theme = Theme.of(context).colorScheme;

    final leadingIcon = iconPath != null
        ? loadSvg(iconPath, width: 26, height: 26, color: theme.primary)
        : icon!;

    return Obx(() => isLoggedIn.value.isNotEmpty
        ? _logged(context, leadingIcon, title, username, avatarUrl, onLogOut,
            onAvatarTap, onIconTap, onIconLongTap)
        : _notLogged(leadingIcon, onLogIn));
  }

  Widget _logged(
    BuildContext context,
    Widget leadingIcon,
    String? title,
    RxString username,
    RxString avatarUrl,
    Function() onPressed,
    Function()? onAvatarTap,
    Function()? onIconTap,
    Function()? onIconLongTap,
  ) {
    var theme = Theme.of(context).colorScheme;
    return Obx(() {
      return ListTile(
        leading: leadingIcon,
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                username.value.isNotEmpty ? username.value : title ?? '',
                style: TextStyle(
                  color: theme.secondary,
                  fontSize: 16,
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                getString.logout(""),
                style: TextStyle(
                  color: theme.onSurface,
                  fontSize: 14,
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.bold,
                ),
              ),
            ]),
            Row(
              children: [
                if (onIconTap != null || onIconLongTap != null)
                  GestureDetector(
                    onTap: onIconTap,
                    onLongPress: onIconLongTap,
                    child: Container(
                      padding: const EdgeInsets.all(8.0),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: theme.primary,
                      ),
                      child: Icon(
                        Icons.question_mark,
                        size: 14,
                        color: theme.surface,
                      ),
                    ),
                  ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: onAvatarTap,
                  child: CircleAvatar(
                    backgroundColor: Colors.transparent,
                    radius: 26.0,
                    backgroundImage: avatarUrl.value.isNotEmpty
                        ? CachedNetworkImageProvider(avatarUrl.value)
                        : null,
                  ),
                ),
              ],
            ),
          ],
        ),
        onTap: onPressed,
      );
    });
  }

  Widget _notLogged(Widget leadingIcon, Function() onPressed) {
    return ListTile(
      leading: leadingIcon,
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            getString.login,
            style: const TextStyle(
              fontSize: 14,
              fontFamily: 'Poppins',
              fontWeight: FontWeight.bold,
            ),
          ),
          Container(
            padding: const EdgeInsets.all(8.0),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.grey,
                width: 0.8,
              ),
            ),
            child: const Icon(
              Icons.person,
              size: 32,
            ),
          ),
        ],
      ),
      onTap: onPressed,
    );
  }
}
