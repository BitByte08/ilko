PROJECT    = LiveWallpaper.xcodeproj
SCHEME     = LiveWallpaper
CONFIG     = Debug
BUILD_DIR  = $(PWD)/.build
APP        = $(BUILD_DIR)/Build/Products/$(CONFIG)/LiveWallpaper.app

XCODE_FLAGS = \
	CODE_SIGN_IDENTITY="-" \
	CODE_SIGNING_REQUIRED=NO \
	CODE_SIGNING_ALLOWED=NO

.PHONY: build run clean submodule

## 서브모듈 초기화 (최초 1회)
submodule:
	git submodule update --init --recursive

## 빌드만
build: submodule
	xcodebuild \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-configuration $(CONFIG) \
		-derivedDataPath $(BUILD_DIR) \
		$(XCODE_FLAGS) \
		build

## 빌드 후 바로 실행 (메뉴바에 아이콘 뜨면 성공)
run: build
	open "$(APP)"

## 빌드 결과물 삭제
clean:
	rm -rf $(BUILD_DIR)
