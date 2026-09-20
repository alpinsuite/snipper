#include "capture_channel.h"

#include <gdk-pixbuf/gdk-pixbuf.h>
#include <gdk/gdk.h>
#include <gio/gio.h>
#include <gtk/gtk.h>

#include <cstring>

#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

// Screen capture on Linux is two unrelated mechanisms, and which one applies is
// decided by the display server and by nothing the application can influence.
//
// Under X11 any client may read the root window, so the capture is one GDK
// call. Under Wayland no client may read another's pixels at all; the only way
// to a screenshot is to ask xdg-desktop-portal for one over D-Bus, which asks
// the compositor, which may ask the user. The portal answers asynchronously
// with the URI of a file it wrote.
//
// Both paths end in a GdkPixbuf and share everything after that, so the part
// that turns pixels into a reply is exercised by whichever path a test can
// reach. In CI that is X11, under Xvfb.
static constexpr char kChannelName[] = "com.alpinsuite.snipper/capture";
static constexpr char kEnumerateDisplays[] = "enumerateDisplays";
static constexpr char kCaptureDesktop[] = "captureDesktop";
static constexpr char kCaptureInteractive[] = "captureInteractive";
static constexpr char kBackend[] = "backend";

static constexpr char kPortalBus[] = "org.freedesktop.portal.Desktop";
static constexpr char kPortalPath[] = "/org/freedesktop/portal/desktop";
static constexpr char kPortalScreenshot[] = "org.freedesktop.portal.Screenshot";
static constexpr char kPortalRequest[] = "org.freedesktop.portal.Request";

// SNIPPER_CAPTURE=portal asks the desktop even on an X server. It is how the
// portal path is tested, since CI has an X server and no compositor, and it is
// also the answer for a desktop whose X root is not the real screen — a
// Wayland session reached through XWayland shows every native window black.
// LinuxCaptureService reads the same variable, so the two cannot disagree
// about who runs the selection.
static bool display_is_x11() {
  if (g_strcmp0(g_getenv("SNIPPER_CAPTURE"), "portal") == 0) return false;
#ifdef GDK_WINDOWING_X11
  GdkDisplay* display = gdk_display_get_default();
  return display != nullptr && GDK_IS_X11_DISPLAY(display);
#else
  return false;
#endif
}

// --- replying ---------------------------------------------------------------

// Sends a pixbuf back as tightly packed RGBA rows.
//
// Packed here rather than in Dart for one reason: a pixbuf's buffer is allowed
// to stop short of a full stride on its last row, and the Dart side rightly
// refuses a buffer shorter than `bytesPerRow * height`. Copying row by row
// makes the question go away instead of answering it twice.
static void respond_with_pixbuf(FlMethodCall* method_call, GdkPixbuf* source) {
  // The root window has no alpha channel and a portal PNG may or may not.
  // add_alpha without a substitute colour just appends an opaque byte.
  g_autoptr(GdkPixbuf) rgba =
      gdk_pixbuf_get_has_alpha(source)
          ? GDK_PIXBUF(g_object_ref(source))
          : gdk_pixbuf_add_alpha(source, FALSE, 0, 0, 0);
  if (rgba == nullptr || gdk_pixbuf_get_n_channels(rgba) != 4 ||
      gdk_pixbuf_get_bits_per_sample(rgba) != 8) {
    fl_method_call_respond_error(method_call, "bad-format",
                                 "The screenshot is not 8-bit RGBA.", nullptr,
                                 nullptr);
    return;
  }

  const int width = gdk_pixbuf_get_width(rgba);
  const int height = gdk_pixbuf_get_height(rgba);
  const int stride = gdk_pixbuf_get_rowstride(rgba);
  const guint8* pixels = gdk_pixbuf_read_pixels(rgba);
  if (width <= 0 || height <= 0 || pixels == nullptr) {
    fl_method_call_respond_error(method_call, "empty",
                                 "The screenshot has no pixels.", nullptr,
                                 nullptr);
    return;
  }

  const gsize row_bytes = static_cast<gsize>(width) * 4;
  g_autofree guint8* packed =
      static_cast<guint8*>(g_malloc(row_bytes * static_cast<gsize>(height)));
  for (int y = 0; y < height; y++) {
    memcpy(packed + row_bytes * y, pixels + static_cast<gsize>(stride) * y,
           row_bytes);
  }

  g_autoptr(FlValue) result = fl_value_new_map();
  fl_value_set_string_take(result, "width", fl_value_new_int(width));
  fl_value_set_string_take(result, "height", fl_value_new_int(height));
  fl_value_set_string_take(result, "bytesPerRow",
                           fl_value_new_int(static_cast<int64_t>(row_bytes)));
  fl_value_set_string_take(
      result, "bytes",
      fl_value_new_uint8_list(packed, row_bytes * static_cast<gsize>(height)));
  fl_method_call_respond_success(method_call, result, nullptr);
}

// --- monitors ---------------------------------------------------------------

static void handle_enumerate_displays(FlMethodCall* method_call) {
  GdkDisplay* display = gdk_display_get_default();
  if (display == nullptr) {
    fl_method_call_respond_error(method_call, "no-display",
                                 "There is no display to enumerate.", nullptr,
                                 nullptr);
    return;
  }

  g_autoptr(FlValue) monitors = fl_value_new_list();
  const int count = gdk_display_get_n_monitors(display);
  for (int i = 0; i < count; i++) {
    GdkMonitor* monitor = gdk_display_get_monitor(display, i);
    if (monitor == nullptr) continue;

    // GDK reports geometry in application pixels, which are device pixels
    // divided by the integer scale factor. A screenshot is device pixels, so
    // the multiplication happens here, once, and never again above this line.
    GdkRectangle geometry;
    gdk_monitor_get_geometry(monitor, &geometry);
    const int scale = gdk_monitor_get_scale_factor(monitor);

    g_autoptr(FlValue) entry = fl_value_new_map();
    g_autofree gchar* id = g_strdup_printf("monitor-%d", i);
    fl_value_set_string_take(entry, "id", fl_value_new_string(id));
    fl_value_set_string_take(entry, "x", fl_value_new_int(geometry.x * scale));
    fl_value_set_string_take(entry, "y", fl_value_new_int(geometry.y * scale));
    fl_value_set_string_take(entry, "width",
                             fl_value_new_int(geometry.width * scale));
    fl_value_set_string_take(entry, "height",
                             fl_value_new_int(geometry.height * scale));
    fl_value_set_string_take(entry, "scale", fl_value_new_float(scale));
    fl_value_set_string_take(entry, "primary",
                             fl_value_new_bool(gdk_monitor_is_primary(monitor)));
    fl_value_append(monitors, entry);
  }
  fl_method_call_respond_success(method_call, monitors, nullptr);
}

// --- X11 --------------------------------------------------------------------

static void capture_x11(FlMethodCall* method_call) {
  GdkWindow* root = gdk_get_default_root_window();
  if (root == nullptr) {
    fl_method_call_respond_error(method_call, "no-root",
                                 "The X server has no root window.", nullptr,
                                 nullptr);
    return;
  }

  // The root window spans every monitor and starts at the origin, so unlike
  // Windows there is no negative coordinate to carry. The size asked for is in
  // application pixels; the pixbuf that comes back is in device pixels, and
  // its own width and height are what the reply reports.
  g_autoptr(GdkPixbuf) shot =
      gdk_pixbuf_get_from_window(root, 0, 0, gdk_window_get_width(root),
                                 gdk_window_get_height(root));
  if (shot == nullptr) {
    fl_method_call_respond_error(method_call, "capture-failed",
                                 "The X server refused to hand over the screen.",
                                 nullptr, nullptr);
    return;
  }
  respond_with_pixbuf(method_call, shot);
}

// --- the portal -------------------------------------------------------------

// Everything one portal request needs to outlive the call that started it.
//
// Two callbacks hold the same pointer: the method return and the Response
// signal. The signal normally comes second, but the portal documentation says
// outright that it may come first, so neither is allowed to free the request
// until both have happened or the first has failed.
struct PortalRequest {
  FlMethodCall* method_call;
  GDBusConnection* bus;
  guint subscription;
  gchar* handle;
  bool call_returned;
  bool answered;
};

static void portal_request_free(PortalRequest* request) {
  if (request->subscription != 0) {
    g_dbus_connection_signal_unsubscribe(request->bus, request->subscription);
  }
  g_clear_object(&request->method_call);
  g_clear_object(&request->bus);
  g_free(request->handle);
  g_free(request);
}

// Called once the Dart side has its answer, whichever callback produced it.
static void portal_answered(PortalRequest* request) {
  request->answered = true;
  if (request->call_returned) portal_request_free(request);
}

static void portal_fail(PortalRequest* request, const char* code,
                        const char* message) {
  fl_method_call_respond_error(request->method_call, code, message, nullptr,
                               nullptr);
  portal_answered(request);
}

static void portal_response_cb(GDBusConnection* bus, const gchar* sender,
                               const gchar* path, const gchar* interface,
                               const gchar* signal, GVariant* parameters,
                               gpointer user_data) {
  PortalRequest* request = static_cast<PortalRequest*>(user_data);

  guint32 response = 2;
  g_autoptr(GVariant) results = nullptr;
  g_variant_get(parameters, "(u@a{sv})", &response, &results);

  if (response == 1) {
    // The user closed the desktop's dialog. Not a failure, and Dart tells the
    // two apart by this code.
    portal_fail(request, "cancelled", "The screenshot was cancelled.");
    return;
  }
  const gchar* uri = nullptr;
  if (response != 0 || !g_variant_lookup(results, "uri", "&s", &uri) ||
      uri == nullptr) {
    portal_fail(request, "portal-refused",
                "The desktop declined to take a screenshot.");
    return;
  }

  g_autoptr(GFile) file = g_file_new_for_uri(uri);
  g_autofree gchar* local_path = g_file_get_path(file);
  g_autoptr(GError) error = nullptr;
  g_autoptr(GdkPixbuf) shot =
      local_path == nullptr ? nullptr
                            : gdk_pixbuf_new_from_file(local_path, &error);

  // The portal writes the file for this request and for nobody else, usually
  // into the user's Pictures folder. Leaving it there would fill that folder
  // with a copy of every capture, whether or not it was ever saved.
  g_file_delete(file, nullptr, nullptr);

  if (shot == nullptr) {
    portal_fail(request, "portal-unreadable",
                error != nullptr ? error->message
                                 : "The desktop's screenshot could not be read.");
    return;
  }
  respond_with_pixbuf(request->method_call, shot);
  portal_answered(request);
}

static void portal_subscribe(PortalRequest* request, const gchar* handle) {
  if (request->subscription != 0) {
    g_dbus_connection_signal_unsubscribe(request->bus, request->subscription);
  }
  g_free(request->handle);
  request->handle = g_strdup(handle);
  request->subscription = g_dbus_connection_signal_subscribe(
      request->bus, kPortalBus, kPortalRequest, "Response", handle, nullptr,
      G_DBUS_SIGNAL_FLAGS_NONE, portal_response_cb, request, nullptr);
}

static void portal_call_cb(GObject* source, GAsyncResult* result,
                           gpointer user_data) {
  PortalRequest* request = static_cast<PortalRequest*>(user_data);
  g_autoptr(GError) error = nullptr;
  g_autoptr(GVariant) reply =
      g_dbus_connection_call_finish(G_DBUS_CONNECTION(source), result, &error);
  request->call_returned = true;
  if (request->answered) {
    // The signal got here first and has already replied.
    portal_request_free(request);
    return;
  }
  if (reply == nullptr) {
    // Almost always "the name org.freedesktop.portal.Desktop was not
    // provided": xdg-desktop-portal, or its backend for this desktop, is not
    // installed. The message names the package because that is the fix.
    portal_fail(request, "portal-unavailable",
                "This desktop has no screenshot portal. Install "
                "xdg-desktop-portal and the backend for your desktop.");
    return;
  }

  // Portals older than 0.9 pick the request path themselves instead of
  // deriving it from the token, so the subscription follows whatever came back.
  const gchar* handle = nullptr;
  g_variant_get(reply, "(&o)", &handle);
  if (handle != nullptr && g_strcmp0(handle, request->handle) != 0) {
    portal_subscribe(request, handle);
  }
}

static void capture_portal(FlMethodCall* method_call, bool interactive) {
  g_autoptr(GError) error = nullptr;
  GDBusConnection* bus = g_bus_get_sync(G_BUS_TYPE_SESSION, nullptr, &error);
  if (bus == nullptr) {
    fl_method_call_respond_error(method_call, "portal-unavailable",
                                 "There is no session bus to ask for a "
                                 "screenshot on.",
                                 nullptr, nullptr);
    return;
  }

  PortalRequest* request = g_new0(PortalRequest, 1);
  request->method_call = FL_METHOD_CALL(g_object_ref(method_call));
  request->bus = bus;

  // The reply arrives as a signal on an object whose path is derived from this
  // connection's name and a token chosen here. Subscribing before calling is
  // the documented way to not miss a reply that beats the method return.
  g_autofree gchar* token = g_strdup_printf("snipper%u", g_random_int());
  g_autofree gchar* sender =
      g_strdup(g_dbus_connection_get_unique_name(bus) + 1);
  for (gchar* c = sender; *c != '\0'; c++) {
    if (*c == '.') *c = '_';
  }
  g_autofree gchar* handle = g_strdup_printf(
      "/org/freedesktop/portal/desktop/request/%s/%s", sender, token);
  portal_subscribe(request, handle);

  GVariantBuilder options;
  g_variant_builder_init(&options, G_VARIANT_TYPE_VARDICT);
  g_variant_builder_add(&options, "{sv}", "handle_token",
                        g_variant_new_string(token));
  // Interactive hands the whole job to the desktop's own screenshot interface,
  // region selection included. It is how a region is chosen under Wayland,
  // where this application cannot put a window over the screen to do it.
  g_variant_builder_add(&options, "{sv}", "interactive",
                        g_variant_new_boolean(interactive));

  g_dbus_connection_call(bus, kPortalBus, kPortalPath, kPortalScreenshot,
                         "Screenshot", g_variant_new("(sa{sv})", "", &options),
                         G_VARIANT_TYPE("(o)"), G_DBUS_CALL_FLAGS_NONE, -1,
                         nullptr, portal_call_cb, request);
}

// --- dispatch ---------------------------------------------------------------

static void method_call_cb(FlMethodChannel* channel, FlMethodCall* method_call,
                           gpointer user_data) {
  const gchar* name = fl_method_call_get_name(method_call);
  if (strcmp(name, kEnumerateDisplays) == 0) {
    handle_enumerate_displays(method_call);
  } else if (strcmp(name, kBackend) == 0) {
    g_autoptr(FlValue) backend =
        fl_value_new_string(display_is_x11() ? "x11" : "portal");
    fl_method_call_respond_success(method_call, backend, nullptr);
  } else if (strcmp(name, kCaptureDesktop) == 0) {
    if (display_is_x11()) {
      capture_x11(method_call);
    } else {
      capture_portal(method_call, false);
    }
  } else if (strcmp(name, kCaptureInteractive) == 0) {
    capture_portal(method_call, true);
  } else {
    fl_method_call_respond_not_implemented(method_call, nullptr);
  }
}

void snipper_capture_channel_register(FlView* view) {
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  FlMethodChannel* channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)), kChannelName,
      FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, method_call_cb, nullptr,
                                            nullptr);
}
