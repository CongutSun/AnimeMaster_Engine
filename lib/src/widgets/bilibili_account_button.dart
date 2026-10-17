import 'package:flutter/material.dart';

import '../screens/bilibili_login_page.dart';
import '../services/bilibili_auth_service.dart';

class BilibiliAccountButton extends StatelessWidget {
  final BilibiliAuthService auth;
  final bool enabled;

  const BilibiliAccountButton({
    super.key,
    required this.auth,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: auth,
    builder: (context, _) => TextButton.icon(
      onPressed: !enabled
          ? null
          : () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => BilibiliLoginPage(auth: auth),
              ),
            ),
      icon: const Icon(Icons.account_circle_outlined),
      label: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 100),
        child: Text(
          auth.account?.name ?? (auth.isExpired ? '重新登录' : '登录'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ),
  );
}
