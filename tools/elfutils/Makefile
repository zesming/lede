# SPDX-License-Identifier: GPL-2.0-only

include $(TOPDIR)/rules.mk

PKG_NAME:=elfutils
PKG_VERSION:=0.192
PKG_RELEASE:=1

PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.bz2
PKG_SOURCE_URL:=https://sourceware.org/$(PKG_NAME)/ftp/$(PKG_VERSION)
PKG_HASH:=616099beae24aba11f9b63d86ca6cc8d566d968b802391334c91df54eab416b4

PKG_LICENSE:=GPL-3.0-or-later
PKG_LICENSE_FILES:=COPYING COPYING-GPLV2 COPYING-LGPLV3
PKG_CPE_ID:=cpe:/a:elfutils_project:elfutils

PKG_FIXUP:=autoreconf
PKG_INSTALL:=1

include $(INCLUDE_DIR)/host-build.mk

HOST_CFLAGS += -Wno-error -fPIC -std=gnu17

HOST_CONFIGURE_ARGS += \
	--disable-debuginfod \
	--disable-libdebuginfod \
	--disable-nls \
	--disable-shared \
	--without-lzma \
	--without-zstd

HOST_MAKE_FLAGS += \
	SUBDIRS="lib libelf libcpu backends libebl libdwelf libdwfl libdw"

define Host/Uninstall
	-$(call Host/Compile/Default,uninstall)
endef

$(eval $(call HostBuild))
