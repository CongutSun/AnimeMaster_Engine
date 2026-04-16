class TrackerPool {
  static const List<String> robustTrackers = <String>[
    'udp://tracker.opentrackr.org:1337/announce',
    'udp://tracker.openbittorrent.com:6969/announce',
    'http://tracker.openbittorrent.com:80/announce',
    'udp://tracker.torrent.eu.org:451/announce',
    'udp://explodie.org:6969/announce',
    'udp://open.demonii.com:1337/announce',
    'udp://tracker.moeking.me:6969/announce',
    'udp://open.stealth.si:80/announce',
    'udp://tracker.cyberia.is:6969/announce',
    'udp://tracker.tiny-vps.com:6969/announce',
    'udp://tracker.theoks.net:6969/announce',
    'udp://tracker.bitsearch.to:1337/announce',
    'http://tracker.dler.org:6969/announce',
    'http://t.nyaatracker.com:80/announce',
    'http://tracker.nyanya.uk:6969/announce',
    'udp://exodus.desync.com:6969/announce',
    'udp://open.tracker.cl:1337/announce',
    'udp://open.dstud.io:6969/announce',
    'udp://tracker.dump.cl:6969/announce',
    'udp://tracker-udp.gbitt.info:80/announce',
    'udp://tracker.tryhackx.org:6969/announce',
    'http://tracker.gbitt.info:80/announce',
    'http://tracker.ipv6tracker.org:80/announce',
  ];

  static final List<Uri> dhtBootstrapNodes = <Uri>[
    Uri(host: 'router.bittorrent.com', port: 6881),
    Uri(host: 'router.utorrent.com', port: 6881),
    Uri(host: 'dht.transmissionbt.com', port: 6881),
    Uri(host: 'dht.aelitis.com', port: 6881),
  ];
}
