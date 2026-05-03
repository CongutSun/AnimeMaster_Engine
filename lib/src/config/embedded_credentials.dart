class EmbeddedCredentials {
  const EmbeddedCredentials._();

  static const String bangumiClientId = String.fromEnvironment(
    'ANIMEMASTER_BANGUMI_CLIENT_ID',
    defaultValue: '',
  );
  static const String bangumiClientSecret = String.fromEnvironment(
    'ANIMEMASTER_BANGUMI_CLIENT_SECRET',
    defaultValue: '',
  );
  static const String bangumiAuthGatewayUrl = String.fromEnvironment(
    'ANIMEMASTER_AUTH_GATEWAY_URL',
    defaultValue: 'https://auth.congutsun.com',
  );
  static const String appUpdateFeedUrl = String.fromEnvironment(
    'ANIMEMASTER_UPDATE_FEED_URL',
    defaultValue: 'https://auth.congutsun.com/app_update.json',
  );
  static const String resourceProxyBaseUrl = String.fromEnvironment(
    'ANIMEMASTER_RESOURCE_PROXY_URL',
    defaultValue: 'https://auth.congutsun.com',
  );

  static const String dandanplayAppId = String.fromEnvironment(
    'ANIMEMASTER_DANDANPLAY_APP_ID',
    defaultValue: '',
  );
  static const String dandanplayAppSecret = String.fromEnvironment(
    'ANIMEMASTER_DANDANPLAY_APP_SECRET',
    defaultValue: '',
  );
}
