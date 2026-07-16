import 'dart:async';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:fastnin/custom_appbar.dart';
import 'package:fastnin/exit_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:http/http.dart' as http;
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';
import 'package:permission_handler/permission_handler.dart'
    hide PermissionStatus;
import 'package:url_launcher/url_launcher.dart';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'colors.dart';
import 'download_method.dart';
import 'package:share_plus/share_plus.dart';

class WebViewScreen extends StatefulWidget {
  final String url;
  const WebViewScreen({super.key, required this.url});

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  InAppWebViewController? _webViewController;
  PullToRefreshController? _pullToRefreshController;

  bool _hasError = false;
  bool _isOffline = false;
  String currentLongPressImageUrl = '';
  late StreamSubscription<List<ConnectivityResult>> _connectivitySubscription;
  String _currentUrl = '';
  bool _isRemoveBgSite = false;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  double _progress = 0;
  late AnimationController _logoController;
  late Animation<double> _logoAnimation;
  bool _isInitialLoad = true;
  bool _isDarkMode = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // _requestAllPermissionsUpfront();
    _checkAndListenInternet();

    // Logo animation setup
    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);

    _logoAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.easeInOut),
    );

    _pullToRefreshController = PullToRefreshController(
      settings: PullToRefreshSettings(
        color: Colors.green,
        backgroundColor: Colors.white,
      ),
      onRefresh: () async {
        if (_webViewController != null) {
          _webViewController!.reload();
        }
      },
    );
  }

  Future<void> _requestAllPermissionsUpfront() async {
    await [
      Permission.camera,
      Permission.microphone,
      Permission.location,
      Permission.notification,
    ].request();

    if (await _isAndroid13OrAbove()) {
      await [Permission.photos, Permission.audio, Permission.videos].request();
    } else {
      await Permission.storage.request();
    }
  }

  Future<bool> _isAndroid13OrAbove() async {
    if (!mounted) return false;
    final sdkInt = await _getAndroidSdkInt();
    return sdkInt >= 33;
  }

  Future<int> _getAndroidSdkInt() async {
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      return info.version.sdkInt;
    } catch (_) {
      return 0;
    }
  }

  void _checkAndListenInternet() {
    Connectivity().checkConnectivity().then((result) {
      if (mounted) {
        setState(() {
          _isOffline = result.contains(ConnectivityResult.none);
        });
      }
    });

    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      result,
    ) {
      if (!mounted) return;
      final wasOffline = _isOffline;
      setState(() {
        _isOffline = result.contains(ConnectivityResult.none);
      });
      if (wasOffline && !_isOffline && _webViewController != null) {
        _webViewController!.reload();
      }
    });
  }

  // Blob বা Data URL থেকে Image Save করার জন্য
  Future<void> _handleBlobOrDataImage(String url) async {
    if (url.startsWith('data:image')) {
      // Direct base64
      String base64 = url.split(',').last;
      await _saveBase64ImageToGallery(base64, context, _isRemoveBgSite);
    } else if (url.startsWith('blob:')) {
      // Blob URL → JS দিয়ে base64 বানিয়ে পাঠাবে
      final base64 = await _webViewController?.evaluateJavascript(
        source:
            """
      (function() {
        return new Promise((resolve) => {
          var xhr = new XMLHttpRequest();
          xhr.open('GET', '$url', true);
          xhr.responseType = 'blob';
          xhr.onload = function() {
            var reader = new FileReader();
            reader.onloadend = function() {
              var result = reader.result;
              resolve(result.split(',')[1]);
            };
            reader.readAsDataURL(xhr.response);
          };
          xhr.send();
        });
      })();
      """,
      );

      if (base64 != null && base64 is String) {
        await _saveBase64ImageToGallery(base64, context, _isRemoveBgSite);
      }
    }
  }

  // ==================== BASE64 IMAGE SAVE ====================
  Future<void> _saveBase64ImageToGallery(
    String base64Data,
    BuildContext context,
    bool isRemoveBg,
  ) async {
    try {
      String cleanBase64 = base64Data;
      if (base64Data.contains(',')) {
        cleanBase64 = base64Data.split(',').last;
      }
      cleanBase64 = cleanBase64.trim().replaceAll('\n', '').replaceAll(' ', '');

      final bytes = base64Decode(cleanBase64);

      final decodedImage = img.decodeImage(bytes);

      if (decodedImage == null) {
        debugPrint('❌ Could not decode image');
        return;
      }

      final pngBytes = Uint8List.fromList(img.encodePng(decodedImage));

      final result = await ImageGallerySaverPlus.saveImage(
        pngBytes,
        quality: 100,
        name: "removed_bg_${DateTime.now().millisecondsSinceEpoch}",
      );

      if (result['isSuccess'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Background removed & saved to Gallery!'),
              backgroundColor: AppColors.primaryColor,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('❌ Save failed!'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Save error: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error saving image'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _toggleWebTheme() async {
    setState(() {
      _isDarkMode = !_isDarkMode;
    });

    if (_webViewController != null) {
      if (_isDarkMode) {
        // Dark mode CSS Injection (CSS filter invert trick)
        await _webViewController!.evaluateJavascript(
          source: """
        if (!document.getElementById('custom-dark-mode')) {
          var style = document.createElement('style');
          style.id = 'custom-dark-mode';
          style.innerHTML = 'html { filter: invert(1) hue-rotate(180deg) !important; background: #000 !important; } img, video, iframe, canvas { filter: invert(1) hue-rotate(180deg) !important; }';
          document.head.appendChild(style);
        }
      """,
        );
      } else {
        // Remove Dark mode CSS
        await _webViewController!.evaluateJavascript(
          source: """
        var style = document.getElementById('custom-dark-mode');
        if (style) {
          style.parentNode.removeChild(style);
        }
      """,
        );
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connectivitySubscription.cancel();
    _logoController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _webViewController?.pauseTimers();
      _webViewController?.evaluateJavascript(
        source:
            "document.querySelectorAll('video, audio').forEach(v => v.pause());",
      );
    } else if (state == AppLifecycleState.resumed) {
      _webViewController?.resumeTimers();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;

        final canGoBack = await _webViewController?.canGoBack() ?? false;

        if (canGoBack) {
          try {
            var history = await _webViewController?.getCopyBackForwardList();
            if (history != null && history.currentIndex != null) {
              int currentIndex = history.currentIndex!;
              int stepsToSkip = -1;
              String? currentUrl = history.list?[currentIndex].url?.toString();

              for (int i = currentIndex - 1; i >= 0; i--) {
                String? previousUrl = history.list?[i].url?.toString();

                if (previousUrl != null &&
                    previousUrl != currentUrl &&
                    !previousUrl.contains("google.com/url")) {
                  stepsToSkip = i - currentIndex;
                  break;
                }
              }

              if (stepsToSkip < -1 &&
                  await _webViewController!.canGoBackOrForward(
                    steps: stepsToSkip,
                  )) {
                await _webViewController!.goBackOrForward(steps: stepsToSkip);
              } else {
                await _webViewController!.goBack();
              }
            } else {
              await _webViewController!.goBack();
            }
          } catch (e) {
            debugPrint('Smart back error: $e');
            await _webViewController?.goBack();
          }
          return;
        }

        try {
          final currentUrl = await _webViewController?.getUrl();
          if (currentUrl != null) {
            final urlStr = currentUrl.toString().toLowerCase();

            bool isTrickyPage =
                urlStr.contains('google.com/search') ||
                urlStr.contains('google.') &&
                    (urlStr.contains('?q=') || urlStr.contains('/search')) ||
                urlStr.contains('www.google.') ||
                urlStr.contains('facebook.com/sharer') ||
                urlStr.contains('twitter.com/intent') ||
                urlStr.contains('linkedin.com/sharing') ||
                urlStr.contains('t.me/share') ||
                urlStr.contains('wa.me') ||
                urlStr.contains('api.whatsapp.com') ||
                urlStr.contains('bing.com/search') ||
                urlStr.contains('search.yahoo.com') ||
                urlStr.contains('duckduckgo.com') ||
                urlStr.contains('search?') && urlStr.contains('q=') ||
                urlStr.contains('yehrishta.se') && urlStr.contains('episode') ||
                urlStr.contains('/search?q=') ||
                urlStr.contains('?q=') && urlStr.contains('utm_source') ||
                urlStr.contains('redirect') ||
                urlStr.contains('?redirect=') ||
                urlStr.contains('click.php');

            if (isTrickyPage) {
              final historyCount = await _webViewController
                  ?.getCopyBackForwardList();
              if (historyCount != null &&
                  (historyCount.list?.length ?? 0) > 1) {
                await _webViewController?.goBack();
                return;
              }
            }
          }
        } catch (e) {
          debugPrint('Back navigation error: $e');
        }

        bool? exitConfirmed = await showDialog<bool>(
          context: context,
          builder: (context) => const ExitConfirmationDialog(),
        );

        if (exitConfirmed == true) {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        key: _scaffoldKey,
        extendBodyBehindAppBar: true,
        backgroundColor: AppColors.backgroundColor,
        resizeToAvoidBottomInset: false,
        appBar: CustomHeader(progress: _progress),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    // ==================== MAIN WEBVIEW ====================
                    if (!_isOffline)
                      InAppWebView(
                        initialUrlRequest: URLRequest(url: WebUri(widget.url)),
                        pullToRefreshController: _pullToRefreshController,
                        initialSettings: InAppWebViewSettings(
                          javaScriptEnabled: true,
                          allowFileAccess: true,
                          javaScriptCanOpenWindowsAutomatically: true,
                          allowFileAccessFromFileURLs: true,
                          allowUniversalAccessFromFileURLs: true,
                          safeBrowsingEnabled: true,
                          geolocationEnabled: true,
                          supportMultipleWindows: true,
                          mediaPlaybackRequiresUserGesture: false,
                          mixedContentMode:
                              MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
                          allowsInlineMediaPlayback: true,
                          iframeAllowFullscreen: true,
                          useHybridComposition: true,
                          domStorageEnabled: true,
                          databaseEnabled: true,
                          thirdPartyCookiesEnabled: true,
                          userAgent:
                              "Mozilla/5.0 (Linux; Android 10; Pixel 3) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36",
                          useShouldOverrideUrlLoading: true,
                          useOnLoadResource: true,
                          clearCache: false,
                        ),

                        onPermissionRequest: (controller, request) async {
                          final resources = request.resources;

                          // কোন কোন permission দরকার সেটা বের করো
                          bool needsMic = resources.contains(
                            PermissionResourceType.MICROPHONE,
                          );
                          bool needsCam = resources.contains(
                            PermissionResourceType.CAMERA,
                          );

                          List<Permission> toRequest = [];
                          if (needsMic) toRequest.add(Permission.microphone);
                          if (needsCam) toRequest.add(Permission.camera);

                          if (toRequest.isEmpty) {
                            return PermissionResponse(
                              resources: resources,
                              action: PermissionResponseAction.GRANT,
                            );
                          }

                          // Runtime permission চাও
                          final statuses = await toRequest.request();
                          final allGranted = statuses.values.every(
                            (s) => s.isGranted,
                          );

                          return PermissionResponse(
                            resources: resources,
                            action: allGranted
                                ? PermissionResponseAction.GRANT
                                : PermissionResponseAction.DENY,
                          );
                        },

                        onGeolocationPermissionsShowPrompt:
                            (controller, origin) async {
                              final status = await Permission.location
                                  .request();
                              if (status.isGranted) {
                                return GeolocationPermissionShowPromptResponse(
                                  origin: origin,
                                  allow: true,
                                  retain: true,
                                );
                              }
                              return GeolocationPermissionShowPromptResponse(
                                origin: origin,
                                allow: false,
                                retain: false,
                              );
                            },

                        onWebViewCreated: (controller) {
                          _webViewController = controller;

                          // ✅ Web Share API Handler (Flutter Receiver)
                          controller.addJavaScriptHandler(
                            handlerName: 'webShareApi',
                            callback: (args) async {
                              if (args.length >= 3) {
                                final String title = args[0].toString().trim();
                                final String text = args[1].toString().trim();
                                final String url = args[2].toString().trim();

                                String shareContent = '';
                                if (title.isNotEmpty)
                                  shareContent += '$title\n\n';
                                if (text.isNotEmpty)
                                  shareContent += '$text\n\n';
                                if (url.isNotEmpty) shareContent += url;

                                if (shareContent.trim().isNotEmpty) {
                                  try {
                                    // share_plus
                                    await Share.share(
                                      shareContent.trim(),
                                      subject: title.isNotEmpty
                                          ? title
                                          : 'Check this out!',
                                    );
                                  } catch (e) {
                                    debugPrint('Web Share API error: $e');
                                  }
                                }
                              }
                            },
                          );

                          controller.addJavaScriptHandler(
                            handlerName: 'triggerNativeLens',
                            callback: (args) async {
                              debugPrint(
                                '📸 JS Trigger: Launching System Default Native Lens...',
                              );
                              try {
                                final Uri nativeLensUri = Uri.parse(
                                  'googleapp://lens',
                                );
                                bool launched = await launchUrl(
                                  nativeLensUri,
                                  mode: LaunchMode.externalApplication,
                                );

                                if (!launched) {
                                  await launchUrl(
                                    Uri.parse(
                                      "https://play.google.com/store/apps/details?id=com.google.android.googlequicksearchbox",
                                    ),
                                    mode: LaunchMode.externalApplication,
                                  );
                                }
                              } catch (e) {
                                debugPrint('Error: $e');
                              }
                            },
                          );

                          // ✅ JavaScript → Flutter bridge for blob/base64 image download
                          controller.addJavaScriptHandler(
                            handlerName: 'downloadBase64Image',
                            callback: (args) async {
                              if (args.isNotEmpty) {
                                final base64Data = args[0] as String;
                                await _saveBase64ImageToGallery(
                                  base64Data,
                                  context,
                                  _isRemoveBgSite,
                                );
                              }
                            },
                          );

                          // ✅ Social Share Buttons Handler (Improved)

                          controller.addJavaScriptHandler(
                            handlerName: 'shareSocial',
                            callback: (args) async {
                              if (args.isEmpty) return;

                              final String rawUrl = args[0].toString().trim();
                              final String platform = args.length > 1
                                  ? args[1].toString().toLowerCase()
                                  : '';

                              if (rawUrl.isEmpty) return;

                              try {
                                Uri? launchUri;

                                if (platform.contains('whatsapp')) {
                                  final String message =
                                      "Check this out: $rawUrl";
                                  final String encodedMessage =
                                      Uri.encodeComponent(message);
                                  launchUri = Uri.parse(
                                    "https://wa.me/?text=$encodedMessage",
                                  );
                                  await launchUrl(
                                    launchUri,
                                    mode: LaunchMode.externalApplication,
                                  );
                                } else if (platform.contains('email')) {
                                  final String subject = "Check this page";
                                  final String body =
                                      "Here is the link:\n$rawUrl";
                                  final String encodedSubject =
                                      Uri.encodeComponent(subject);
                                  final String encodedBody =
                                      Uri.encodeComponent(body);

                                  launchUri = Uri.parse(
                                    "mailto:?subject=$encodedSubject&body=$encodedBody",
                                  );
                                  await launchUrl(
                                    launchUri,
                                    mode: LaunchMode.externalApplication,
                                  );
                                } else if (platform.contains('linkedin')) {
                                  launchUri = Uri.parse(
                                    "https://www.linkedin.com/sharing/share-offsite/?url=$rawUrl",
                                  );
                                  await launchUrl(
                                    launchUri,
                                    mode: LaunchMode.platformDefault,
                                  );
                                } else if (platform.contains('facebook')) {
                                  launchUri = Uri.parse(
                                    "https://www.facebook.com/sharer/sharer.php?u=$rawUrl",
                                  );
                                  await launchUrl(
                                    launchUri,
                                    mode: LaunchMode.platformDefault,
                                  );
                                } else if (platform.contains('telegram')) {
                                  final String message = "Check this: $rawUrl";
                                  final String encoded = Uri.encodeComponent(
                                    message,
                                  );
                                  launchUri = Uri.parse(
                                    "https://t.me/share/url?url=$rawUrl&text=$encoded",
                                  );
                                  await launchUrl(
                                    launchUri,
                                    mode: LaunchMode.externalApplication,
                                  );
                                } else if (platform.contains('twitter')) {
                                  final String message = "Check this out:";
                                  final String encodedText =
                                      Uri.encodeComponent(message);
                                  launchUri = Uri.parse(
                                    "https://twitter.com/intent/tweet?text=$encodedText&url=$rawUrl",
                                  );
                                  await launchUrl(
                                    launchUri,
                                    mode: LaunchMode.platformDefault,
                                  );
                                } else {
                                  // Default fallback
                                  launchUri = Uri.parse(rawUrl);
                                  await launchUrl(
                                    launchUri,
                                    mode: LaunchMode.platformDefault,
                                  );
                                }
                              } catch (e) {
                                debugPrint('Share error for $platform: $e');
                                // Final fallback
                                try {
                                  await launchUrl(
                                    Uri.parse(rawUrl),
                                    mode: LaunchMode.platformDefault,
                                  );
                                } catch (_) {}
                              }
                            },
                          );

                          controller.addJavaScriptHandler(
                            handlerName: 'shareLink',
                            callback: (args) async {
                              if (args.isNotEmpty) {
                                final String urlToShare = args[0]
                                    .toString()
                                    .trim();
                                if (urlToShare.isNotEmpty) {
                                  try {
                                    await Share.share(
                                      urlToShare,
                                      subject: 'Check this out!',
                                    );
                                  } catch (e) {
                                    debugPrint('Share error: $e');
                                  }
                                }
                              }
                            },
                          );
                        },

                        onReceivedServerTrustAuthRequest:
                            (controller, challenge) async {
                              return ServerTrustAuthResponse(
                                action: ServerTrustAuthResponseAction.PROCEED,
                              );
                            },

                        onProgressChanged: (controller, progress) {
                          if (mounted) {
                            setState(() {
                              _progress = progress / 100.0;
                              if (_progress >= 1.0) {
                                _isInitialLoad = false;
                              }
                            });
                          }
                        },

                        onLoadStart: (controller, url) {
                          if (url != null && mounted) {
                            setState(() {
                              _hasError = false;
                              _currentUrl = url.toString();
                              _isRemoveBgSite = _currentUrl
                                  .toLowerCase()
                                  .contains('remove.bg');
                              _progress = 0.0;
                            });
                          }
                        },

                        onLoadStop: (controller, url) async {
                          if (mounted) {
                            setState(() => _hasError = false);
                          }

                          _pullToRefreshController?.endRefreshing();

                          // ✅ Universal Web Share API Support
                          await controller.evaluateJavascript(
                            source: """
                                (function() {
                                  if (window.__webSharePolyfillInstalled) return;
                                  window.__webSharePolyfillInstalled = true;
              
                                  navigator.share = function(shareData) {
                                    return new Promise(function(resolve, reject) {
                                      if (shareData) {
                                        var title = shareData.title || document.title || '';
                                        var text = shareData.text || '';
                                        var url = shareData.url || window.location.href;
                                        
                                        console.log('Universal Share Triggered:', title, url);
                                        
                                        window.flutter_inappwebview.callHandler('webShareApi', title, text, url);
                                        resolve();
                                      } else {
                                        reject(new Error('No share data provided'));
                                      }
                                    });
                                  };
                                })();
                                """,
                          );

                          await controller.evaluateJavascript(
                            source: """
                                console.log("Speech Support Check: " + ('speechSynthesis' in window));
                              """,
                          );

                          await controller.evaluateJavascript(
                            source: """
                            (function() {
                              document.querySelectorAll('a[target="_blank"]').forEach(function(link) {
                                link.removeAttribute('target');
                              });
                            })();
                          """,
                          );

                          await controller.evaluateJavascript(
                            source: """
                          (function() {
                            if (window.__elementorShareFixed) return;
                            window.__elementorShareFixed = true;
        
                            function handleShareClick(e) {
                              const btn = e.target.closest('.elementor-share-btn');
                              if (!btn) return;
        
                              const className = btn.className || '';
                              let platform = '';
                              let shareUrl = window.location.href;
        
                              if (className.includes('whatsapp')) platform = 'whatsapp';
                              else if (className.includes('facebook')) platform = 'facebook';
                              else if (className.includes('telegram')) platform = 'telegram';
                              else if (className.includes('twitter')) platform = 'twitter';
                              else if (className.includes('linkedin')) platform = 'linkedin';
                              else if (className.includes('email')) platform = 'email';
        
                              // Get actual share URL from href or data attribute
                              const link = btn.closest('a') || btn.querySelector('a');
                              if (link && link.href) {
                                shareUrl = link.href;
                              }
        
                              console.log('Share button clicked → Platform:', platform, 'URL:', shareUrl);
        
                              window.flutter_inappwebview.callHandler('shareSocial', shareUrl, platform);
        
                              e.preventDefault();
                              e.stopImmediatePropagation();
                            }
        
                            // Click listener
                            document.addEventListener('click', handleShareClick, true);
        
        
                            const observer = new MutationObserver(() => {
                              document.querySelectorAll('.elementor-share-btn').forEach(btn => {
                                btn.removeEventListener('click', handleShareClick);
                                btn.addEventListener('click', handleShareClick);
                              });
                            });
                            observer.observe(document.body, { childList: true, subtree: true });
        
                          })();
                          """,
                          );

                          await controller.evaluateJavascript(
                            source: """
                        (function() {
                          if (window.__nativeShareHandlerAdded) return;
                          window.__nativeShareHandlerAdded = true;
        
                          function triggerNativeShare() {
                            let btn = document.getElementById('customShareBtn') || 
                                      document.querySelector('.share-style');
                            
                            if (!btn) return;
        
                            let shareUrl = window.location.href;   // default current page
        
                            const link = btn.closest('a') || btn.querySelector('a');
                            if (link && link.href) {
                              shareUrl = link.href;
                            }
        
                            console.log('Native Share triggered for URL:', shareUrl);
        
                            window.flutter_inappwebview.callHandler('shareLink', shareUrl);
                          }
        
                          // Click Listener
                          document.addEventListener('click', function(e) {
                            const clickedElement = e.target.closest('button, [role="button"], #customShareBtn, .share-style');
                            
                            if (clickedElement) {
                              const text = (clickedElement.innerText || clickedElement.textContent || '').trim();
                              
                              if (text.includes('শেয়ার করুন') || 
                                  clickedElement.id === 'customShareBtn' || 
                                  clickedElement.classList.contains('share-style')) {
                                
                                e.preventDefault();
                                e.stopImmediatePropagation();
        
                                setTimeout(() => {
                                  triggerNativeShare();
                                }, 80);
                              }
                            }
                          }, true);
        
                        })();
                        """,
                          );

                          // WhatsApp links fix
                          await controller.evaluateJavascript(
                            source: """
                      (function() {
                        document.querySelectorAll('a[href*="wa.me"], a[href*="api.whatsapp.com"]').forEach(function(link) {
                          link.removeAttribute('target');
                          link.removeAttribute('onclick');
                        });
                      })();
                    """,
                          );

                          // ✅ Blob / Data URL / Canvas download interceptor
                          await controller.evaluateJavascript(
                            source: """
                        (function() {
                          if (window.__downloadInterceptorInstalled) return;
                          window.__downloadInterceptorInstalled = true;
        
                          var _saving = false;
                          var _allBlobUrls = [];  // সব blob URL track করবো
        
                          function safeSend(base64) {
                            if (_saving) return;
                            _saving = true;
                            setTimeout(function() { _saving = false; }, 4000);
                            window.flutter_inappwebview.callHandler('downloadBase64Image', base64);
                          }
        
                          // ✅ Blob → Base64 (PNG force)
                          function blobUrlToBase64(blobUrl, cb) {
                            var xhr = new XMLHttpRequest();
                            xhr.open('GET', blobUrl, true);
                            xhr.responseType = 'blob';
                            xhr.onload = function() {
                              var blob = xhr.response;
                              var reader = new FileReader();
                              reader.onloadend = function() {
                                var result = reader.result; // data:image/png;base64,...
                                var b64 = result.split(',')[1];
                                cb(b64, blob.size);
                              };
                              // ✅ সবসময় PNG হিসেবে read করো — transparency রক্ষা হবে
                              reader.readAsDataURL(new Blob([blob], {type: 'image/png'}));
                            };
                            xhr.onerror = function() { cb(null, 0); };
                            xhr.send();
                          }
        
                          // ✅ Canvas থেকে PNG (transparent background সহ)
                          function tryGetBestCanvas() {
                            var canvases = Array.from(document.querySelectorAll('canvas'));
                            // সবচেয়ে বড় canvas = result image
                            canvases.sort(function(a, b) {
                              return (b.width * b.height) - (a.width * a.height);
                            });
                            for (var i = 0; i < canvases.length; i++) {
                              var c = canvases[i];
                              if (c.width > 100 && c.height > 100) {
                                try {
                                  // ✅ PNG নিলে transparency থাকে, JPEG নিলে black হয়
                                  var dataUrl = c.toDataURL('image/png');
                                  if (dataUrl && dataUrl !== 'data:,') {
                                    return dataUrl.split(',')[1];
                                  }
                                } catch(e) {
                                  console.log('Canvas tainted:', e);
                                }
                              }
                            }
                            return null;
                          }
        
                          // ✅ সবচেয়ে বড় IMG (result image হওয়ার সম্ভাবনা বেশি)
                          function tryGetLargestImg(cb) {
                            var imgs = Array.from(document.querySelectorAll('img'));
                            // naturalWidth দিয়ে sort করো — সবচেয়ে বড় টা result
                            imgs.sort(function(a, b) {
                              return (b.naturalWidth * b.naturalHeight) - (a.naturalWidth * a.naturalHeight);
                            });
                            for (var i = 0; i < imgs.length; i++) {
                              var src = imgs[i].src || '';
                              if (src.startsWith('blob:')) {
                                blobUrlToBase64(src, function(b64, size) {
                                  if (b64 && size > 1000) cb(b64);  // ছোট file (icon) skip
                                });
                                return true;
                              } else if (src.startsWith('data:image')) {
                                cb(src.split(',')[1]);
                                return true;
                              }
                            }
                            return false;
                          }
        
                          // ✅ সবচেয়ে বড় blob URL নেওয়া (size দিয়ে filter)
                          function getBestBlobUrl(cb) {
                            if (_allBlobUrls.length === 0) { cb(null); return; }
                            var checked = 0;
                            var bestB64 = null;
                            var bestSize = 0;
                            _allBlobUrls.forEach(function(blobUrl) {
                              blobUrlToBase64(blobUrl, function(b64, size) {
                                if (size > bestSize) {
                                  bestSize = size;
                                  bestB64 = b64;
                                }
                                checked++;
                                if (checked === _allBlobUrls.length) {
                                  // ✅ সবচেয়ে বড় মানে result image — icon/thumbnail না
                                  cb(bestSize > 5000 ? bestB64 : null);
                                }
                              });
                            });
                          }
        
                          // ✅ সব image blob URL track (শুধু image type)
                          var origCreate = URL.createObjectURL;
                          URL.createObjectURL = function(obj) {
                            var url = origCreate.call(URL, obj);
                            if (obj instanceof Blob && obj.type.startsWith('image/')) {
                              _allBlobUrls.push(url);
                              // Max 10 রাখো
                              if (_allBlobUrls.length > 10) _allBlobUrls.shift();
                            }
                            return url;
                          };
        
                          // ✅ <a download> direct intercept
                          document.addEventListener('click', function(e) {
                            var el = e.target.closest('[download]');
                            if (!el) return;
                            var href = el.getAttribute('href') || '';
                            if (href.startsWith('blob:')) {
                              e.preventDefault(); e.stopPropagation();
                              blobUrlToBase64(href, function(b64, size) {
                                if (b64) safeSend(b64);
                              });
                            } else if (href.startsWith('data:image')) {
                              e.preventDefault(); e.stopPropagation();
                              safeSend(href.split(',')[1]);
                            }
                          }, true);
        
                          // ✅ Download / Save button — smart fallback chain
                          document.addEventListener('click', function(e) {
                            var btn = e.target.closest('button, a, [role="button"], div, span');
                            if (!btn) return;
                            var text = (btn.innerText || btn.getAttribute('aria-label') || btn.title || '').toLowerCase();
                            var isDownload = text.includes('download') || text.includes('save') ||
                                            btn.getAttribute('download') !== null ||
                                            btn.querySelector('[download]') !== null;
                            if (!isDownload) return;
        
                            setTimeout(function() {
        
                              getBestBlobUrl(function(b64) {
                                if (b64) { safeSend(b64); return; }
        
                                var canvasB64 = tryGetBestCanvas();
                                if (canvasB64) { safeSend(canvasB64); return; }
        
                                var found = tryGetLargestImg(safeSend);
                                if (!found) {
                                  console.log('No image source found');
                                }
                              });
        
                            }, 800); 
                          }, true);
        
                        })();
                        """,
                          );
                        },

                        onReceivedError: (controller, request, error) {
                          debugPrint(
                            'WebView Error: \${error.description} | IsMainFrame: \${request.isForMainFrame}',
                          );
                          if ((request.isForMainFrame ?? false) && mounted) {
                            setState(() => _hasError = true);
                          }
                          _pullToRefreshController?.endRefreshing();
                        },

                        // ✅ onDownloadStartRequest: regular HTTP file download
                        onDownloadStartRequest: (controller, request) async {
                          final url = request.url.toString();
                          final mimeType = request.mimeType ?? '';
                          final suggestedFilename =
                              request.suggestedFilename ?? 'downloaded_file';

                          debugPrint(
                            '📥 Download Triggered: $url | MIME: $mimeType',
                          );

                          if (url.startsWith('blob:') ||
                              url.startsWith('data:image')) {
                            await _handleBlobOrDataImage(url);
                            return;
                          }

                          if (mimeType == 'text/x-vcard' ||
                              url.endsWith('.vcf')) {
                            final status = await FlutterContacts.permissions
                                .request(PermissionType.readWrite);

                            if (status == PermissionStatus.granted) {
                              try {
                                final response = await http.get(Uri.parse(url));

                                if (response.statusCode == 200) {
                                  String vcardText = response.body;

                                  List<Contact> contacts = FlutterContacts.vCard
                                      .import(vcardText);

                                  if (contacts.isNotEmpty) {
                                    await FlutterContacts.create(
                                      contacts.first,
                                    );

                                    if (mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            '${contacts.first.displayName ?? "Contact"} has been saved!',
                                          ),
                                        ),
                                      );
                                    }
                                  } else {
                                    debugPrint(
                                      'No contact data found in vCard.',
                                    );
                                  }
                                } else {
                                  debugPrint('Failed to download vCard file.');
                                }
                              } catch (e) {
                                debugPrint('Error saving contact: $e');
                              }
                            } else {
                              debugPrint('Contact permission denied by user.');
                            }
                          } else {
                            await downloadAndSaveToGallery(
                              url,
                              context,
                              mimeType: mimeType,
                              suggestedFilename: suggestedFilename,
                            );
                          }
                        },

                        onLongPressHitTestResult:
                            (controller, hitTestResult) async {
                              if (hitTestResult.type ==
                                      InAppWebViewHitTestResultType
                                          .SRC_IMAGE_ANCHOR_TYPE ||
                                  hitTestResult.type ==
                                      InAppWebViewHitTestResultType
                                          .IMAGE_TYPE) {
                                final imageUrl =
                                    hitTestResult.extra?.toString() ?? '';

                                if (imageUrl.isEmpty) return;

                                setState(() {
                                  currentLongPressImageUrl = imageUrl;
                                });

                                // ==================== Context Menu Popup ====================
                                if (!mounted) return;

                                showModalBottomSheet(
                                  context: context,
                                  backgroundColor: Colors.white,
                                  shape: const RoundedRectangleBorder(
                                    borderRadius: BorderRadius.vertical(
                                      top: Radius.circular(20),
                                    ),
                                  ),
                                  builder: (context) {
                                    return SafeArea(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Padding(
                                            padding: EdgeInsets.all(16),
                                            child: Text(
                                              'Image Options',
                                              style: TextStyle(
                                                fontSize: 18,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                          ListTile(
                                            leading: const Icon(
                                              Icons.copy,
                                              color: Colors.blue,
                                            ),
                                            title: const Text(
                                              'Copy Image Address',
                                            ),
                                            onTap: () async {
                                              Navigator.pop(context);
                                              await Clipboard.setData(
                                                ClipboardData(text: imageUrl),
                                              );
                                              if (mounted) {
                                                ScaffoldMessenger.of(
                                                  context,
                                                ).showSnackBar(
                                                  const SnackBar(
                                                    content: Text(
                                                      '✅ Image address copied!',
                                                    ),
                                                    backgroundColor:
                                                        Colors.blue,
                                                  ),
                                                );
                                              }
                                            },
                                          ),
                                          ListTile(
                                            leading: const Icon(
                                              Icons.download,
                                              color: Colors.blue,
                                            ),
                                            title: const Text('Download Image'),
                                            onTap: () async {
                                              Navigator.pop(context);
                                              if (imageUrl.startsWith(
                                                    'blob:',
                                                  ) ||
                                                  imageUrl.startsWith(
                                                    'data:image',
                                                  )) {
                                                await _handleBlobOrDataImage(
                                                  imageUrl,
                                                );
                                              } else {
                                                // Normal HTTP URL
                                                await downloadAndSaveToGallery(
                                                  imageUrl,
                                                  context,
                                                );
                                              }
                                            },
                                          ),

                                          const Divider(),
                                          ListTile(
                                            leading: const Icon(Icons.close),
                                            title: const Text('Cancel'),
                                            onTap: () => Navigator.pop(context),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                );
                              }
                            },

                        onCreateWindow: (controller, createWindowAction) async {
                          final uri = createWindowAction.request.url;

                          if (uri != null) {
                            final String urlString = uri
                                .toString()
                                .toLowerCase();
                            if (urlString.contains('wa.me') ||
                                urlString.contains('whatsapp') ||
                                urlString.contains('facebook.com/sharer') ||
                                urlString.contains('twitter.com/intent') ||
                                urlString.contains('t.me') ||
                                urlString.contains('linkedin.com/sharing')) {
                              try {
                                await launchUrl(
                                  uri,
                                  mode: LaunchMode.externalApplication,
                                );
                              } catch (e) {
                                debugPrint(
                                  'Error launching external browser: $e',
                                );
                              }
                            } else {
                              controller.loadUrl(
                                urlRequest: URLRequest(url: uri),
                              );
                            }
                          }

                          return true;
                        },

                        // ==================== FULLSCREEN ORIENTATION CONTROL ====================
                        onEnterFullscreen: (controller) async {
                          debugPrint(
                            '✅ Entered Fullscreen - Switching to Landscape',
                          );

                          await SystemChrome.setPreferredOrientations([
                            DeviceOrientation.landscapeLeft,
                            DeviceOrientation.landscapeRight,
                          ]);

                          await SystemChrome.setEnabledSystemUIMode(
                            SystemUiMode.immersiveSticky,
                          );
                        },

                        onExitFullscreen: (controller) async {
                          debugPrint('✅ Exited Fullscreen - Back to Portrait');

                          await SystemChrome.setPreferredOrientations([
                            DeviceOrientation.portraitUp,
                            DeviceOrientation.portraitDown,
                          ]);

                          await SystemChrome.setEnabledSystemUIMode(
                            SystemUiMode.edgeToEdge,
                          );
                        },

                        shouldOverrideUrlLoading: (controller, navigationAction) async {
                          final uri = navigationAction.request.url;
                          if (uri == null) return NavigationActionPolicy.CANCEL;

                          final String urlString = uri.toString();
                          final String urlStringLower = urlString.toLowerCase();
                          final String scheme = uri.scheme.toLowerCase();

                          // 📸 System Default Google Lens (App Link Method)
                          if (urlString.contains('search.app.goo.gl') &&
                              urlStringLower.contains('lens')) {
                            debugPrint(
                              '📸 Launching System Default Native Lens...',
                            );

                            Future.microtask(() async {
                              try {
                                bool launched = await launchUrl(
                                  uri,
                                  mode:
                                      LaunchMode.externalNonBrowserApplication,
                                );

                                if (!launched) {
                                  await launchUrl(
                                    uri,
                                    mode: LaunchMode.externalApplication,
                                  );
                                }
                              } catch (e) {
                                debugPrint('Lens Error: $e');
                              }
                            });

                            return NavigationActionPolicy.CANCEL;
                          }

                          if ([
                            'http',
                            'https',
                            'file',
                            'chrome',
                            'data',
                            'javascript',
                            'about',
                          ].contains(scheme)) {
                            if (urlStringLower.contains('wa.me') ||
                                urlStringLower.contains('api.whatsapp.com') ||
                                urlStringLower.contains('chat.whatsapp.com') ||
                                urlStringLower.contains(
                                  'facebook.com/sharer',
                                ) ||
                                urlStringLower.contains('twitter.com/intent') ||
                                urlStringLower.contains('t.me') ||
                                urlStringLower.contains(
                                  'linkedin.com/sharing',
                                )) {
                              try {
                                await launchUrl(
                                  uri,
                                  mode: LaunchMode.externalApplication,
                                );
                              } catch (e) {
                                debugPrint('Launch error: $e');
                                await launchUrl(
                                  uri,
                                  mode: LaunchMode.platformDefault,
                                );
                              }
                              return NavigationActionPolicy.CANCEL;
                            }

                            return NavigationActionPolicy.ALLOW;
                          }

                          if (scheme == 'whatsapp' ||
                              scheme == 'tel' ||
                              scheme == 'mailto' ||
                              scheme == 'sms' ||
                              scheme == 'tg') {
                            try {
                              await launchUrl(
                                uri,
                                mode: LaunchMode.externalApplication,
                              );
                            } catch (e) {
                              debugPrint('Direct app link error: $e');
                            }
                            return NavigationActionPolicy.CANCEL;
                          }

                          if (urlString.startsWith('intent://') ||
                              urlString.startsWith('whatsapp://')) {
                            try {
                              bool launched = await launchUrl(
                                uri,
                                mode: LaunchMode.externalApplication,
                              );
                              if (!launched)
                                throw Exception('Could not launch intent');
                              return NavigationActionPolicy.CANCEL;
                            } catch (e) {
                              debugPrint(
                                'Intent launch failed, looking for fallback URL...',
                              );

                              RegExp fallbackRegExp = RegExp(
                                r"(?:browser_fallback_url|S\.browser_fallback_url)=([^;]+)",
                              );
                              Match? match = fallbackRegExp.firstMatch(
                                urlString,
                              );

                              if (match != null && match.groupCount >= 1) {
                                String fallbackUrl = Uri.decodeComponent(
                                  match.group(1)!,
                                );

                                if (fallbackUrl.contains(
                                  'play.google.com/store/apps/details',
                                )) {
                                  try {
                                    await launchUrl(
                                      Uri.parse(fallbackUrl),
                                      mode: LaunchMode.externalApplication,
                                    );
                                  } catch (_) {
                                    controller.loadUrl(
                                      urlRequest: URLRequest(
                                        url: WebUri(fallbackUrl),
                                      ),
                                    );
                                  }
                                } else {
                                  controller.loadUrl(
                                    urlRequest: URLRequest(
                                      url: WebUri(fallbackUrl),
                                    ),
                                  );
                                }
                              }
                              return NavigationActionPolicy.CANCEL;
                            }
                          }

                          try {
                            await launchUrl(
                              uri,
                              mode: LaunchMode.externalApplication,
                            );
                          } catch (e) {
                            debugPrint('Launch error for custom scheme: $e');
                            try {
                              await launchUrl(
                                uri,
                                mode: LaunchMode.platformDefault,
                              );
                            } catch (_) {}
                          }

                          return NavigationActionPolicy.CANCEL;
                        },
                      ),

                    // ==================== LOGO POPUP ANIMATION ====================
                    if (_isInitialLoad && !_isOffline)
                      Container(
                        color: AppColors.backgroundColor,
                        child: Center(
                          child: ScaleTransition(
                            scale: _logoAnimation,
                            child: Image.asset(
                              'assets/logo/loading_logo.png',
                              width: 150,
                              errorBuilder: (context, error, stackTrace) =>
                                  const Icon(
                                    Icons.language,
                                    size: 80,
                                    color: Colors.green,
                                  ),
                            ),
                          ),
                        ),
                      ),

                    // ==================== OFFLINE UI ====================
                    if (_isOffline)
                      Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.cloud_off,
                              size: 100,
                              color: Colors.grey,
                            ),
                            const SizedBox(height: 24),
                            const Text(
                              'ইন্টারনেট সংযোগ নেই!',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'অনুগ্রহ করে আপনার সংযোগ পরীক্ষা করে আবার চেষ্টা করুন।',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 16),
                            ),
                            const SizedBox(height: 32),
                            ElevatedButton.icon(
                              icon: const Icon(Icons.refresh),
                              label: const Text('আবার চেষ্টা করুন'),
                              onPressed: () {
                                Connectivity().checkConnectivity().then((
                                  result,
                                ) {
                                  if (mounted) {
                                    setState(() {
                                      _isOffline = result.contains(
                                        ConnectivityResult.none,
                                      );
                                    });
                                  }
                                  if (!_isOffline &&
                                      _webViewController != null) {
                                    _webViewController!.reload();
                                  }
                                });
                              },
                            ),
                          ],
                        ),
                      ),

                    // ==================== ERROR UI ====================
                    if (!_isOffline && _hasError)
                      Container(
                        color: Colors.white,
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.error_outline,
                                size: 80,
                                color: Colors.red,
                              ),
                              const SizedBox(height: 20),
                              const Text(
                                'কিছু একটা ভুল হয়েছে!',
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'পৃষ্ঠাটি সঠিকভাবে লোড হতে পারেনি। \n অনুগ্রহ করে আবার চেষ্টা করুন।',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 16),
                              ),
                              const SizedBox(height: 24),
                              ElevatedButton.icon(
                                icon: const Icon(Icons.refresh),
                                label: const Text('পৃষ্ঠাটি পুনরায় লোড করুন'),
                                onPressed: () {
                                  if (mounted)
                                    setState(() => _hasError = false);
                                  _webViewController?.reload();
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
