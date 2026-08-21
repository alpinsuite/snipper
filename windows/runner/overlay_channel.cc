#include "overlay_channel.h"

#include <flutter/standard_method_codec.h>

#include <string>

namespace {

constexpr char kChannelName[] = "com.alpinsuite.snipper/overlay";

// Reads an int out of the argument map, or returns false if it is not there.
bool GetInt(const flutter::EncodableMap& map, const char* key, int* out) {
  const auto it = map.find(flutter::EncodableValue(std::string(key)));
  if (it == map.end()) return false;
  if (const auto* value = std::get_if<int32_t>(&it->second)) {
    *out = *value;
    return true;
  }
  if (const auto* value = std::get_if<int64_t>(&it->second)) {
    *out = static_cast<int>(*value);
    return true;
  }
  if (const auto* value = std::get_if<double>(&it->second)) {
    *out = static_cast<int>(*value);
    return true;
  }
  return false;
}

}  // namespace

OverlayChannel::OverlayChannel(flutter::BinaryMessenger* messenger, HWND window)
    : window_(window) {
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, kChannelName, &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    HandleMethodCall(call, std::move(result));
  });
}

OverlayChannel::~OverlayChannel() {
  // The window is going away, so restoring its frame is pointless -- but the
  // hotkey is a process-wide registration and leaving it behind would keep the
  // keys taken until the process exits.
  UnregisterHotkey();
}

void OverlayChannel::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const std::string& method = call.method_name();

  if (method == "enterOverlay") {
    const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
    int x = 0, y = 0, width = 0, height = 0;
    if (args == nullptr || !GetInt(*args, "x", &x) ||
        !GetInt(*args, "y", &y) || !GetInt(*args, "width", &width) ||
        !GetInt(*args, "height", &height)) {
      result->Error("bad_arguments", "enterOverlay wants x, y, width, height");
      return;
    }
    if (width <= 0 || height <= 0) {
      result->Error("bad_arguments", "an overlay with no pixels");
      return;
    }
    result->Success(flutter::EncodableValue(EnterOverlay(x, y, width, height)));
    return;
  }

  if (method == "leaveOverlay") {
    LeaveOverlay();
    result->Success(flutter::EncodableValue(true));
    return;
  }

  if (method == "excludeFromCapture") {
    // Keeps the window visible to the person using it and invisible to
    // BitBlt, PrintWindow and the DWM. That removes the hide-wait-capture-show
    // dance entirely: no flicker, no settle delay, no lost z-order.
    const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
    int exclude = 0;
    if (args == nullptr || !GetInt(*args, "exclude", &exclude)) {
      result->Error("bad_arguments", "excludeFromCapture wants exclude");
      return;
    }
    const BOOL ok = SetWindowDisplayAffinity(
        window_, exclude ? WDA_EXCLUDEFROMCAPTURE : WDA_NONE);
    result->Success(flutter::EncodableValue(ok != FALSE));
    return;
  }

  if (method == "registerHotkey") {
    const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
    int modifiers = 0, key = 0;
    if (args == nullptr || !GetInt(*args, "modifiers", &modifiers) ||
        !GetInt(*args, "key", &key)) {
      result->Error("bad_arguments", "registerHotkey wants modifiers and key");
      return;
    }
    if (!RegisterHotkey(static_cast<UINT>(modifiers), static_cast<UINT>(key))) {
      // Almost always ERROR_HOTKEY_ALREADY_REGISTERED (1409): something else
      // owns the combination. The application says so rather than pretending
      // the binding is live.
      result->Error("hotkey_refused", "Windows refused the key combination",
                    flutter::EncodableValue(
                        static_cast<int32_t>(GetLastError())));
      return;
    }
    result->Success(flutter::EncodableValue(true));
    return;
  }

  if (method == "unregisterHotkey") {
    UnregisterHotkey();
    result->Success(flutter::EncodableValue(true));
    return;
  }

  result->NotImplemented();
}

bool OverlayChannel::EnterOverlay(int x, int y, int width, int height) {
  if (!in_overlay_) {
    saved_style_ = GetWindowLongPtr(window_, GWL_STYLE);
    saved_ex_style_ = GetWindowLongPtr(window_, GWL_EXSTYLE);
    saved_placement_.length = sizeof(WINDOWPLACEMENT);
    GetWindowPlacement(window_, &saved_placement_);
    in_overlay_ = true;
  }

  // A maximised window ignores SetWindowPos, and the title bar is hidden, so a
  // maximised window is the ordinary case rather than an unusual one.
  ShowWindow(window_, SW_RESTORE);

  SetWindowLongPtr(window_, GWL_STYLE, WS_POPUP | WS_VISIBLE);
  SetWindowLongPtr(window_, GWL_EXSTYLE,
                   saved_ex_style_ | WS_EX_TOPMOST | WS_EX_TOOLWINDOW);

  if (!SetWindowPos(window_, HWND_TOPMOST, x, y, width, height,
                    SWP_FRAMECHANGED | SWP_SHOWWINDOW)) {
    return false;
  }

  // The rectangle that matters is the *client* area, not the window rectangle.
  // Flutter renders into the client area, and window_manager's hidden title bar
  // is not a frameless window: it answers WM_NCCALCSIZE so the caption goes but
  // the resize border stays, which on this machine leaves the client area 16
  // pixels narrower and 9 shorter than what was asked for, offset by 8 and 1.
  //
  // Sixteen pixels of a 1920-wide desktop is under one percent, and it looks
  // like nothing -- which is exactly the problem. The frozen frame was being
  // stretched over a slightly smaller area, so the picture no longer lined up
  // with the desktop it was covering, and every snip came out about one percent
  // larger than the rectangle that was drawn around it.
  //
  // Rather than work out the frame metrics, which depend on the DPI and on what
  // window_manager decided to keep, the window is placed once, measured, and
  // corrected by the difference. The metrics do not change between the two
  // calls, so one pass is enough.
  RECT client{};
  POINT origin{0, 0};
  if (!GetClientRect(window_, &client) || !ClientToScreen(window_, &origin)) {
    return true;
  }
  const int dx = origin.x - x;
  const int dy = origin.y - y;
  const int dw = width - (client.right - client.left);
  const int dh = height - (client.bottom - client.top);
  if (dx == 0 && dy == 0 && dw == 0 && dh == 0) return true;

  return SetWindowPos(window_, HWND_TOPMOST, x - dx, y - dy, width + dw,
                      height + dh, SWP_FRAMECHANGED | SWP_SHOWWINDOW) != FALSE;
}

void OverlayChannel::LeaveOverlay() {
  if (!in_overlay_) return;
  in_overlay_ = false;

  SetWindowLongPtr(window_, GWL_STYLE, saved_style_);
  SetWindowLongPtr(window_, GWL_EXSTYLE, saved_ex_style_);
  // NOTOPMOST as well as the saved ex-style: clearing WS_EX_TOPMOST in the
  // style word alone does not take the window back out of the topmost band.
  SetWindowPos(window_, HWND_NOTOPMOST, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_FRAMECHANGED);
  SetWindowPlacement(window_, &saved_placement_);
  SetWindowDisplayAffinity(window_, WDA_NONE);
}

bool OverlayChannel::RegisterHotkey(UINT modifiers, UINT key) {
  UnregisterHotkey();
  // MOD_NOREPEAT, or holding the key fires the capture over and over.
  if (!RegisterHotKey(window_, kHotkeyId, modifiers | MOD_NOREPEAT, key)) {
    return false;
  }
  hotkey_registered_ = true;
  return true;
}

void OverlayChannel::UnregisterHotkey() {
  if (!hotkey_registered_) return;
  UnregisterHotKey(window_, kHotkeyId);
  hotkey_registered_ = false;
}

bool OverlayChannel::HandleMessage(UINT message, WPARAM wparam,
                                   LPARAM lparam) {
  switch (message) {
    case WM_DPICHANGED:
      // Swallowed only while the overlay is up. The stock handler would move
      // and resize the window to the rectangle Windows suggests for the new
      // monitor, which is exactly what an overlay spanning several monitors
      // must not do.
      return in_overlay_;

    case WM_HOTKEY:
      if (static_cast<int>(wparam) != kHotkeyId) return false;
      channel_->InvokeMethod("onHotkey", nullptr);
      return true;

    default:
      return false;
  }
}
