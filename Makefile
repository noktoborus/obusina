# The application identifier, which is what a desktop names the program by:
# the desktop entry, the icon and the `app_id` the window carries are one name.
ID = ru.styxheim.obusina

PREFIX ?= /usr/local
BINDIR = $(DESTDIR)$(PREFIX)/bin
APPDIR = $(DESTDIR)$(PREFIX)/share/applications
ICONDIR = $(DESTDIR)$(PREFIX)/share/icons/hicolor

.PHONY: build build-windows build-android apk apk-release aab web install uninstall mockups version

# `make VERSION=YYYY.MM.DD` writes the version of the program into the tree,
# and does nothing else (the target `version` at the end).
ifdef VERSION
.DEFAULT_GOAL := version
endif

build:
	cargo build --release

# Windows, built with mingw: target/x86_64-pc-windows-gnu/release/obusina.exe.
build-windows:
	cargo build --release --target x86_64-pc-windows-gnu -p obusina

# The page of the program in a browser, built by trunk from web/index.html
# (Trunk.toml): the site in target/web.
web:
	trunk build

# The library android loads, built with the NDK of ANDROID_NDK_HOME:
# target/aarch64-linux-android/release/libobusina_android.so.
build-android:
	cargo ndk -t arm64-v8a build --release -p obusina-android

# The package of android, built by gradle, which builds the library of every
# ABI itself. It needs ANDROID_HOME and ANDROID_NDK_HOME.
#
# `apk` is a release signed with the debug key DEBUG_KEY, made by keytool when
# it is missing: target/obusina.apk, installable by hand, not for a store.
# The key lives outside the repositories (android/README.md).
# `apk-release` is signed when OBUSINA_KEYSTORE names a keystore, else
# unsigned: target/obusina-release.apk.
DEBUG_KEY ?= $(OBUSINA_DEBUG_KEY)
# The build tools the Android Gradle plugin uses, in ANDROID_HOME.
BUILD_TOOLS = $(ANDROID_HOME)/build-tools/36.0.0

apk: $(DEBUG_KEY)
	@test -n "$(DEBUG_KEY)" || { echo 'OBUSINA_DEBUG_KEY: the file of the debug key'; exit 1; }
	cd android && env -u OBUSINA_KEYSTORE ./gradlew --no-daemon assembleRelease
	mkdir -p target
	$(BUILD_TOOLS)/zipalign -c -p 4 android/app/build/outputs/apk/release/app-release-unsigned.apk
	$(BUILD_TOOLS)/apksigner sign --ks $(DEBUG_KEY) --ks-pass pass:android \
		--ks-key-alias androiddebugkey --key-pass pass:android \
		--out target/obusina.apk android/app/build/outputs/apk/release/app-release-unsigned.apk
	rm -f target/obusina.apk.idsig
	$(BUILD_TOOLS)/apksigner verify target/obusina.apk

# The debug key: the one the Android Gradle plugin makes, with its passwords.
$(DEBUG_KEY):
	mkdir -p $(dir $(DEBUG_KEY))
	keytool -genkeypair -keystore $(DEBUG_KEY) -storepass android \
		-alias androiddebugkey -keypass android -keyalg RSA -keysize 2048 \
		-validity 10000 -dname "CN=Android Debug,O=Android,C=US"

apk-release:
	cd android && ./gradlew --no-daemon assembleRelease
	mkdir -p target
	cp android/app/build/outputs/apk/release/app-release*.apk target/obusina-release.apk

aab:
	cd android && ./gradlew --no-daemon bundleRelease

install:
	@test -x target/release/obusina || { echo "run 'make build' first"; exit 1; }
	sudo install -Dm755 target/release/obusina $(BINDIR)/obusina
	sudo install -Dm644 assets/$(ID).desktop $(APPDIR)/$(ID).desktop
	sudo install -Dm644 assets/icon.svg $(ICONDIR)/scalable/apps/$(ID).svg
	sudo update-desktop-database $(APPDIR) 2>/dev/null || true

# The mockups of experiments/mockups, built into the module `mockups` of the
# desk `obusina` of the server of showcase on port 6080; SHOWCASE is the
# directory of showcase. The server is started if none answers, and lives on
# after the command. trunk and wasm-bindgen are on PATH.
mockups:
	@test -n "$(SHOWCASE)" || { echo 'SHOWCASE: the directory of showcase'; exit 1; }
	ln -sfn "$(SHOWCASE)" experiments/mockups/.showcase
	cargo build --manifest-path "$(SHOWCASE)/Cargo.toml" --bin showcase
	"$(SHOWCASE)/target/debug/showcase" up
	"$(SHOWCASE)/target/debug/showcase" build experiments/mockups --desk obusina --as mockups

uninstall:
	sudo rm -f $(BINDIR)/obusina
	sudo rm -f $(APPDIR)/$(ID).desktop
	sudo rm -f $(ICONDIR)/scalable/apps/$(ID).svg
	sudo update-desktop-database $(APPDIR) 2>/dev/null || true

# The version of the program, `make VERSION=YYYY.MM.DD`, the day of a
# release: `version` of `[workspace.package]` of Cargo.toml, which the
# android package reads too, and the version of each crate of the workspace
# in `[workspace.dependencies]`. Cargo takes no zero before a number, so
# 2026.01.09 is written 2026.1.9; cargo fits Cargo.lock to it on the next
# build. It is written into the tree only: nothing is committed or tagged.
version:
	@echo "$(VERSION)" | grep -Eq '^[0-9]{4}\.[0-9]{2}\.[0-9]{2}$$' \
		|| { echo "give VERSION=YYYY.MM.DD"; exit 1; }
	@cargo=$$(echo "$(VERSION)" | sed 's/\.0*\([0-9]\)/.\1/g'); \
	sed -i -e "/^\[workspace.package\]/,/^\[/ s/^version = \".*\"/version = \"$$cargo\"/" \
		-e "/^\[workspace.dependencies\]/,/^\[/ s/\(path = \"[^\"]*\", version = \"\)[^\"]*\"/\1$$cargo\"/" \
		Cargo.toml; \
	grep -q "^version = \"$$cargo\"" Cargo.toml \
		|| { echo "no version written into Cargo.toml"; exit 1; }
