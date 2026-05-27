export ARCHS = arm64 arm64e
export TARGET = iphone:latest:15.0

INSTALL_TARGET_PROCESSES = SpringBoard

SUBPROJECTS += Tweak

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/aggregate.mk
