TARGET := iphone:clang:16.5:15.0
ARCHS = arm64 arm64e
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = WLOCApp
WLOCApp_FILES = main.m WLOCAppDelegate.m WLOCViewController.m WLOCMapPicker.m
WLOCApp_FRAMEWORKS = UIKit WebKit
WLOCApp_INFOPLIST_FILE = Info.plist
WLOCApp_INSTALL_PATH = /Applications
WLOCApp_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/application.mk
