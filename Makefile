APP     := build/Margin.app
SOURCES := $(wildcard Sources/*.swift)
WEB     := $(wildcard Resources/web/*.html Resources/web/*.js)
SDK     := $(shell xcrun --show-sdk-path)

.PHONY: all app run clean check

all: app

app: $(SOURCES) Resources/Info.plist $(WEB)
	@mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources/web
	@cp Resources/Info.plist $(APP)/Contents/Info.plist
	@cp Resources/web/*.html $(APP)/Contents/Resources/web/ 2>/dev/null || true
	@cp Resources/web/*.js   $(APP)/Contents/Resources/web/ 2>/dev/null || true
	@cp Resources/web/*.png  $(APP)/Contents/Resources/web/ 2>/dev/null || true
	@cp Resources/web/*.svg  $(APP)/Contents/Resources/web/ 2>/dev/null || true
	@cp fixtures/state.sample.json $(APP)/Contents/Resources/web/ 2>/dev/null || true
	@cp Resources/AppIcon.icns $(APP)/Contents/Resources/ 2>/dev/null || true
	swiftc -O -swift-version 5 $(SOURCES) -o $(APP)/Contents/MacOS/Margin -framework AppKit -framework WebKit -framework Security -framework UserNotifications -lsqlite3
	@codesign --force --deep --sign - $(APP) 2>/dev/null || true
	@echo "built $(APP)"

run: app
	@pkill -x Margin 2>/dev/null || true
	@sleep 0.2
	open $(APP)

clean:
	@rm -rf build

test: app
	@$(APP)/Contents/MacOS/Margin --self-test

check:
	@swiftc -typecheck -swift-version 5 $(SOURCES) -framework AppKit -framework WebKit -framework Security -framework UserNotifications -lsqlite3 && echo "typecheck ok"
