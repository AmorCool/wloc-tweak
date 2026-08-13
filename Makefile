TARGET := iphone:clang:16.5:15.0
INSTALL_TARGET_PROCESSES = locationd
ARCHS = arm64 arm64e
THEOS_PACKAGE_SCHEME = rootless
THEOS_PACKAGE_SCHEME_VERSION = 2.0
THEOS_DEVICE_IP = 127.0.0.1
THEOS_DEVICE_PORT = 2222

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = wloc
wloc_FILES = Tweak.xm
wloc_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -I./include
wloc_LDFLAGS = -Wl,-undefined,dynamic_lookup

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += WLOCApp
include $(THEOS_MAKE_PATH)/aggregate.mk
