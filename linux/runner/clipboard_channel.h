#ifndef RUNNER_CLIPBOARD_CHANNEL_H_
#define RUNNER_CLIPBOARD_CHANNEL_H_

#include <flutter_linux/flutter_linux.h>

// Registers the channel that lets Dart put an image on the system clipboard.
// See clipboard_channel.cc for why this is not left to a plugin.
void snipper_clipboard_channel_register(FlView* view);

// Hands the last copied image to the clipboard manager so it outlives the
// process. Call once, while shutting down.
void snipper_clipboard_store_on_exit();

#endif  // RUNNER_CLIPBOARD_CHANNEL_H_
