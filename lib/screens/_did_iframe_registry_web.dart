/// Web-only impl of `registerDIDAgentIframe` — registers a platform
/// view factory that mounts the D-ID agent in an `<iframe>` with
/// AnySkill-branded overlays masking the D-ID logo on desktop.
///
/// Selected via the conditional import in `_did_iframe_registry.dart`
/// when `dart.library.js_interop` is available. CLAUDE.md §65.
library;

// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

void registerDIDAgentIframe({
  required String viewType,
  required String url,
}) {
  // ignore: undefined_prefixed_name
  ui_web.platformViewRegistry.registerViewFactory(viewType, (int viewId) {
    final isMobile = (html.window.innerWidth ?? 800) < 700;

    final wrapper = html.DivElement()
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.position = 'relative'
      ..style.overflow = 'hidden'
      ..style.backgroundColor = '#1a1a2e';

    // ── Iframe ────────────────────────────────────────────────────────
    // Mobile: NO crop — show full D-ID agent so "Start conversation"
    //         button is visible. D-ID branding is acceptable on mobile.
    // Desktop: crop 60px top (logo) + 60px bottom (CTA) via offset.
    final iframe = html.IFrameElement()
      ..src = url
      ..style.border = 'none'
      ..style.width = '100%'
      ..style.position = 'absolute'
      ..style.left = '0'
      ..allow = 'camera; microphone; autoplay; clipboard-write'
      ..setAttribute('allowfullscreen', 'true');

    if (isMobile) {
      // Full-size, no shift — everything visible including Start button
      iframe.style.height = '100%';
      iframe.style.top = '0';
    } else {
      // Desktop: expand + shift to crop D-ID branding
      iframe.style.height = 'calc(100% + 120px)';
      iframe.style.top = '-60px';
    }

    wrapper.append(iframe);

    // ── Desktop-only overlays to mask D-ID branding ───────────────────
    if (!isMobile) {
      final topLeft = html.DivElement()
        ..style.position = 'absolute'
        ..style.top = '0'
        ..style.left = '0'
        ..style.width = '180px'
        ..style.height = '44px'
        ..style.backgroundColor = '#1a1a2e'
        ..style.zIndex = '10'
        ..style.borderRadius = '0 0 12px 0';

      final topRight = html.DivElement()
        ..style.position = 'absolute'
        ..style.top = '0'
        ..style.right = '0'
        ..style.width = '180px'
        ..style.height = '44px'
        ..style.backgroundColor = '#1a1a2e'
        ..style.zIndex = '10'
        ..style.borderRadius = '0 0 0 12px';

      final bottom = html.DivElement()
        ..style.position = 'absolute'
        ..style.bottom = '0'
        ..style.left = '0'
        ..style.width = '100%'
        ..style.height = '60px'
        ..style.zIndex = '10'
        ..style.background =
            'linear-gradient(to bottom, transparent, #1a1a2e 30%)';

      wrapper.append(topLeft);
      wrapper.append(topRight);
      wrapper.append(bottom);
    }

    return wrapper;
  });
}
