TWEAK_NAME = Locus

$(TWEAK_NAME)_FILES = $(TWEAK_NAME).x $(wildcard LocationManager/*.m) $(wildcard FloatingButton/*.m) $(wildcard MapViewController/*.m)
$(TWEAK_NAME)_FRAMEWORKS = UIKit CoreLocation MapKit CoreMotion
$(TWEAK_NAME)_CFLAGS = -fobjc-arc

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/tweak.mk
