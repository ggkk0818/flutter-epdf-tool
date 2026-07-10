import 'package:flutter/material.dart';

import '../../shared/widgets/device_status_chip.dart';

class DocumentPage extends StatelessWidget {
  const DocumentPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Align(
          alignment: Alignment.centerLeft,
          child: DeviceStatusChip(),
        ),
        const Expanded(child: SizedBox.shrink()),
      ],
    );
  }
}
