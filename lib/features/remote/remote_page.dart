import 'package:flutter/material.dart';

import '../../shared/widgets/device_status_chip.dart';

class RemotePage extends StatelessWidget {
  const RemotePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Align(
          alignment: Alignment.centerLeft,
          child: DeviceStatusChip(),
        ),
        Expanded(
          child: Center(
            child: Text(
              '遥控页占位',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        ),
      ],
    );
  }
}
