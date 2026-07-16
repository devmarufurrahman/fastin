import 'package:fastnin/app_url.dart';
import 'package:fastnin/webview_screen.dart';
import 'package:flutter/material.dart';
import 'colors.dart';

class CustomDrawer extends StatelessWidget {
  final Function(String url) onUrlSelected;

  const CustomDrawer({super.key, required this.onUrlSelected});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: AppColors.primaryColor,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          // Drawer Header
          DrawerHeader(
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Colors.white24, width: 1),
              ),
            ),
            child: Center(
              child: Column(
                children: [
                  Image.asset(
                    'assets/logo/appbar_logo.png',
                    height: 50,
                    width: 150,
                    errorBuilder: (context, error, stackTrace) => const Icon(
                      Icons.image_not_supported,
                      color: Colors.white,
                      size: 34,
                    ),
                  ),
                  SizedBox(height: 20),

                  Text(
                    'This app is not affiliated with any government entity. We only provide links to official websites.',
                    style: TextStyle(color: Colors.white, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),

          // ১. হোম
          ListTile(
            leading: const Icon(Icons.home, color: Colors.white, size: 28),
            title: const Text(
              'হোম',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w500,
              ),
            ),
            onTap: () {
              Navigator.pop(context);
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(
                  builder: (context) => WebViewScreen(url: AppUrl.url),
                ),
                (Route<dynamic> route) => false,
              );
            },
          ),
          const Divider(color: Colors.white24, height: 1),

          ListTile(
            leading: const Icon(
              Icons.notifications_active,
              color: Colors.white,
              size: 28,
            ),
            title: const Text(
              'আপডেট তথ্য',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w500,
              ),
            ),
            onTap: () {
              Navigator.pop(context);
              onUrlSelected("https://esebago.com/update-info");
            },
          ),
          const Divider(color: Colors.white24, height: 1),

          // ২. আপডেট তথ্য
          ListTile(
            leading: const Icon(Icons.info, color: Colors.white, size: 28),
            title: const Text(
              'প্রাইভেসী-পলিসি',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w500,
              ),
            ),
            onTap: () {
              Navigator.pop(context);
              onUrlSelected("https://esebago.com/privacy-policy");
            },
          ),
          const Divider(color: Colors.white24, height: 1),

          // ৩. যোগাযোগ
          ListTile(
            leading: const Icon(
              Icons.perm_phone_msg,
              color: Colors.white,
              size: 28,
            ),
            title: const Text(
              'যোগাযোগ',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w500,
              ),
            ),
            onTap: () {
              Navigator.pop(context);
              onUrlSelected("https://esebago.com/contact-us");
            },
          ),
          const Divider(color: Colors.white24, height: 1),

          // ৪. রেটিং দিন
          ListTile(
            leading: const Icon(Icons.star, color: Colors.white, size: 28),
            title: const Text(
              'রেটিং দিন',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w500,
              ),
            ),
            onTap: () {
              Navigator.pop(context);
              // রেটিং এর জন্য সাধারণত স্টোর লিঙ্ক হয়, সেটি এখানে দিতে পারেন
              onUrlSelected(
                "https://play.google.com/store/apps/details?id=com.esebago.app",
              );
            },
          ),
          const Divider(color: Colors.white24, height: 1),

          // ৫. অন্য অ্যাপ গুলো দেখুন
          ListTile(
            leading: const Icon(Icons.android, color: Colors.white, size: 28),
            title: const Text(
              'অন্য অ্যাপ গুলো দেখুন',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w500,
              ),
            ),
            onTap: () {
              Navigator.pop(context);
              onUrlSelected("https://esebago.com/other-apps");
            },
          ),
          const Divider(color: Colors.white24, height: 1),
        ],
      ),
    );
  }
}
