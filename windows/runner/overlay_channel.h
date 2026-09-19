#ifndef RUNNER_OVERLAY_CHANNEL_H_
#define RUNNER_OVERLAY_CHANNEL_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <windows.h>

#include <memory>

// Native services the Dart side cannot perform for itself.
//
// Two of them, and both are here for the same reason: they need the window
// procedure, and Dart does not have one.
//
//  * **Putting the window over the whole virtual desktop.** window_manager's
//    setBounds takes logical pixels and the desktop is measured in physical
//    ones, but that is not the blocking problem. The blocking problem is that
//    moving a window across monitors of different scales raises WM_DPICHANGED,
//    and the stock runner's handler answers it by moving and resizing the
//    window to whatever rectangle Windows suggests -- undoing the placement and
//    changing devicePixelRatio underneath the overlay while it is being drawn.
//    That message has to be swallowed for as long as the overlay is up.
//
//  * **The global hotkey.** WM_HOTKEY is posted to the thread queue that the
//    runner's own GetMessage loop is already draining, and a message with a
//    null window handle is then dropped by DispatchMessage. A Dart-side
//    PeekMessage pump loses that race essentially always.
class OverlayChannel {
 public:
  OverlayChannel(flutter::BinaryMessenger* messenger, HWND window);
  ~OverlayChannel();

  // True while the window is standing in as a fullscreen overlay.
  bool InOverlay() const { return in_overlay_; }

  // Offers a window message to the channel. Returns true when it has been
  // handled and must not reach the default handler.
  bool HandleMessage(UINT message, WPARAM wparam, LPARAM lparam);

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  // Saves the window's frame and puts it over the given physical rectangle,
  // borderless and topmost. Idempotent: entering twice does not overwrite the
  // saved frame with the overlay's own.
  bool EnterOverlay(int x, int y, int width, int height);

  // Puts back everything EnterOverlay changed. Safe to call when not in an
  // overlay, because the failure it guards against -- a window left frameless,
  // topmost and desktop-sized -- is not recoverable from inside the
  // application.
  void LeaveOverlay();

  bool RegisterHotkey(UINT modifiers, UINT key);
  void UnregisterHotkey();

  HWND window_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;

  bool in_overlay_ = false;
  LONG_PTR saved_style_ = 0;
  LONG_PTR saved_ex_style_ = 0;
  WINDOWPLACEMENT saved_placement_ = {};
  bool hotkey_registered_ = false;

  static constexpr int kHotkeyId = 1;
};

#endif  // RUNNER_OVERLAY_CHANNEL_H_
