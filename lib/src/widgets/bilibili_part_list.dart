import 'package:flutter/material.dart';

import '../models/bilibili_video.dart';

class BilibiliPartList extends StatelessWidget {
  final BilibiliVideo video;
  final int? selectedCid;
  final int? openingCid;
  final int? recommendedCid;
  final ValueChanged<BilibiliPart> onSelected;

  const BilibiliPartList({
    super.key,
    required this.video,
    required this.onSelected,
    this.selectedCid,
    this.openingCid,
    this.recommendedCid,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: video.parts.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (BuildContext context, int index) {
        final BilibiliPart part = video.parts[index];
        final bool selected = part.cid == selectedCid;
        final int seconds = part.duration.inSeconds;
        final String duration =
            '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
        return ListTile(
          key: ValueKey<int>(part.cid),
          selected: selected,
          leading: Icon(selected ? Icons.play_circle_fill : Icons.play_circle),
          title: Text(part.label),
          subtitle: Text(duration),
          trailing: openingCid == part.cid
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : part.cid == recommendedCid
              ? const Text('建议')
              : const Icon(Icons.chevron_right),
          enabled: openingCid == null,
          onTap: () => onSelected(part),
        );
      },
    );
  }
}
