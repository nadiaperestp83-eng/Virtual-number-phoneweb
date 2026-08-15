const appBuildInfo = AppBuildInfo(
  product: "mnscloud-phoneweb",
  version: "0.1.32",
  channel: "stable",
);

class AppBuildInfo {
  const AppBuildInfo({
    required this.product,
    required this.version,
    required this.channel,
  });

  final String product;
  final String version;
  final String channel;
}
