import 'package:flutter/material.dart';
import 'brand_mark.dart';
import 'motion_entrance.dart';

class JourneyHeader extends StatelessWidget {
  final String title, subtitle;
  const JourneyHeader({super.key, required this.title, required this.subtitle});
  @override
  Widget build(BuildContext context) => MotionEntrance(
    child: Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color(0xffffe5aa), Color(0xfffff2da), Color(0xffeef4dc)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const BrandMark(size: 48),
          const SizedBox(height: 18),
          Text(
            title,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: const Color(0xff203b30),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            subtitle,
            style: const TextStyle(color: Color(0xff425c45), height: 1.8),
          ),
        ],
      ),
    ),
  );
}
