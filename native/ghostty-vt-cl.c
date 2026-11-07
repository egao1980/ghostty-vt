/*
 * ghostty-vt-cl: flattens the few libghostty-vt calls that pass or return a
 * struct by value, so CFFI can call them without libffi. No other logic.
 *
 * libghostty-vt passes GhosttyString / GhosttyMousePosition /
 * GhosttyTerminalScrollViewport by value. How those travel (integer
 * registers, float registers, or a hidden pointer) differs between SysV
 * x86-64, AAPCS64 and Win64, so we let a C compiler do it.
 */
#include <stdint.h>
#include <stddef.h>
#include <ghostty/vt.h>

#if defined(_WIN32)
#define CL_API __declspec(dllexport)
#else
#define CL_API __attribute__((visibility("default")))
#endif

/* Bump when a function below is added or changes signature. */
#define GHOSTTY_VT_CL_ABI 2

CL_API int ghostty_vt_cl_abi(void) { return GHOSTTY_VT_CL_ABI; }

CL_API GhosttyResult ghostty_vt_cl_key_event_set_utf8(GhosttyKeyEvent event,
                                                      const uint8_t *ptr,
                                                      size_t len) {
  GhosttyString s = {ptr, len};
  return ghostty_key_event_set_utf8(event, s);
}

CL_API void ghostty_vt_cl_key_event_get_utf8(GhosttyKeyEvent event,
                                             const uint8_t **out_ptr,
                                             size_t *out_len) {
  GhosttyString s = ghostty_key_event_get_utf8(event);
  *out_ptr = s.ptr;
  *out_len = s.len;
}

CL_API GhosttyResult ghostty_vt_cl_mouse_event_set_position(
    GhosttyMouseEvent event, float x, float y) {
  GhosttyMousePosition p = {x, y};
  return ghostty_mouse_event_set_position(event, p);
}

CL_API void ghostty_vt_cl_mouse_event_get_position(GhosttyMouseEvent event,
                                                   float *out_x, float *out_y) {
  GhosttyMousePosition p = ghostty_mouse_event_get_position(event);
  *out_x = p.x;
  *out_y = p.y;
}

/* tag: GhosttyTerminalScrollViewportTag. value fills the union's first word:
 * delta (DELTA), row (ROW) or delta_prompt (DELTA_PROMPT); ignored otherwise. */
CL_API GhosttyResult ghostty_vt_cl_terminal_scroll_viewport(
    GhosttyTerminal terminal, int tag, intptr_t delta) {
  GhosttyTerminalScrollViewport behavior;
  behavior.tag = (GhosttyTerminalScrollViewportTag)tag;
  behavior.value.delta = delta;
  return ghostty_terminal_scroll_viewport(terminal, behavior);
}

/* ABI 2. tag: GhosttyPointTag (ACTIVE, VIEWPORT, SCREEN, HISTORY). */
CL_API GhosttyResult ghostty_vt_cl_terminal_grid_ref(GhosttyTerminal terminal,
                                                    int tag, uint16_t x,
                                                    uint32_t y,
                                                    GhosttyGridRef *out_ref) {
  GhosttyPoint point;
  point.tag = (GhosttyPointTag)tag;
  point.value.coordinate.x = x;
  point.value.coordinate.y = y;
  return ghostty_terminal_grid_ref(terminal, point, out_ref);
}
