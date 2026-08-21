#include "clipboard_channel.h"

#include <gdk-pixbuf/gdk-pixbuf.h>
#include <gtk/gtk.h>

// Writing an image to the clipboard is the one thing the pasteboard plugin
// does not implement on Linux: its method handler covers files, writeFiles and
// image (read), and answers "not implemented" to everything else. Rather than
// pull in a package that needs a Rust toolchain in CI just for this, the
// application registers its own channel here and calls GTK directly.
static constexpr char kChannelName[] = "com.alpinsuite.snipper/clipboard";
static constexpr char kWriteImage[] = "writeImage";

// Builds a pixbuf from encoded image bytes. Returns nullptr and sets `error`
// when the bytes are not an image GDK can read.
static GdkPixbuf* pixbuf_from_bytes(const uint8_t* data, size_t length,
                                    GError** error) {
  g_autoptr(GdkPixbufLoader) loader = gdk_pixbuf_loader_new();
  if (!gdk_pixbuf_loader_write(loader, data, length, error)) {
    gdk_pixbuf_loader_close(loader, nullptr);
    return nullptr;
  }
  if (!gdk_pixbuf_loader_close(loader, error)) {
    return nullptr;
  }
  GdkPixbuf* pixbuf = gdk_pixbuf_loader_get_pixbuf(loader);
  if (pixbuf == nullptr) {
    g_set_error_literal(error, GDK_PIXBUF_ERROR, GDK_PIXBUF_ERROR_FAILED,
                        "the bytes did not decode to an image");
    return nullptr;
  }
  // The loader owns the pixbuf and is about to be freed.
  return GDK_PIXBUF(g_object_ref(pixbuf));
}

static void handle_write_image(FlMethodCall* method_call) {
  FlValue* args = fl_method_call_get_args(method_call);
  if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_UINT8_LIST) {
    fl_method_call_respond_error(method_call, "bad-args",
                                 "writeImage expects a Uint8List", nullptr,
                                 nullptr);
    return;
  }

  g_autoptr(GError) error = nullptr;
  g_autoptr(GdkPixbuf) pixbuf =
      pixbuf_from_bytes(fl_value_get_uint8_list(args),
                        fl_value_get_length(args), &error);
  if (pixbuf == nullptr) {
    fl_method_call_respond_error(method_call, "decode-failed",
                                 error->message, nullptr, nullptr);
    return;
  }

  GtkClipboard* clipboard = gtk_clipboard_get(GDK_SELECTION_CLIPBOARD);
  // Releases the previous copy's ownership before taking the selection again.
  gtk_clipboard_clear(clipboard);
  gtk_clipboard_set_image(clipboard, pixbuf);
  // Marks the contents as worth keeping; the matching store() runs once at
  // shutdown, which is what gtk_clipboard_store is documented for. Calling it
  // per copy would hand the whole image to the clipboard manager every time,
  // which buys nothing while this process is running and still owns the
  // selection. See snipper_clipboard_store_on_exit.
  gtk_clipboard_set_can_store(clipboard, nullptr, 0);

  fl_method_call_respond_success(method_call, nullptr, nullptr);
}

static void method_call_cb(FlMethodChannel* channel, FlMethodCall* method_call,
                           gpointer user_data) {
  if (strcmp(fl_method_call_get_name(method_call), kWriteImage) == 0) {
    handle_write_image(method_call);
  } else {
    fl_method_call_respond_not_implemented(method_call, nullptr);
  }
}

void snipper_clipboard_channel_register(FlView* view) {
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  FlMethodChannel* channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)), kChannelName,
      FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, method_call_cb, nullptr,
                                            nullptr);
}

void snipper_clipboard_store_on_exit() {
  // The documented use of gtk_clipboard_store: on the way out, ask the
  // clipboard manager to keep whatever was last copied, so the image survives
  // the application quitting. An X11 selection otherwise dies with its owner.
  GtkClipboard* clipboard = gtk_clipboard_get(GDK_SELECTION_CLIPBOARD);
  gtk_clipboard_store(clipboard);
}
