#include <assert.h>
#include <bare.h>
#include <js.h>
#include <stdint.h>

uint32_t
answer(void);

static js_value_t *
addon_exports(js_env_t *env, js_value_t *exports) {
  int err = js_create_uint32(env, answer(), &exports);
  assert(err == 0);

  return exports;
}

BARE_MODULE(addon, addon_exports)
