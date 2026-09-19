#ifndef RUNNER_CAPTURE_CHANNEL_H_
#define RUNNER_CAPTURE_CHANNEL_H_

#include <flutter_linux/flutter_linux.h>

// Registers the channel that takes pixels off the screen. See
// capture_channel.cc for the two ways it does that and how it chooses.
void snipper_capture_channel_register(FlView* view);

#endif  // RUNNER_CAPTURE_CHANNEL_H_
