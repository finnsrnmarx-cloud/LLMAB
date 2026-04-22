# ω — convenience wrappers around swift / xcodebuild / xcodegen for LLMAB.
#
#   make xcodeproj   regenerate LLMAB.xcodeproj from project.yml
#   make app         build the .app bundle (debug) via xcodebuild
#   make run-app     build + launch the .app bundle
#   make build       swift build (libraries + CLI, no app)
#   make test        swift test
#   make lint        swiftlint --strict
#   make cli         swift build -c release --product llmab
#   make package     sign + notarise + DMG (see docs/RELEASE.md)
#   make clean       clean SwiftPM and build outputs

.PHONY: build test lint cli xcodeproj app run-app icon package clean

build:
	swift build -c debug

test:
	swift test --parallel

lint:
	swiftlint --strict

cli:
	swift build -c release --product llmab
	@echo "✓ built: $$(swift build -c release --show-bin-path)/llmab"

xcodeproj:
	@command -v xcodegen >/dev/null || { echo "xcodegen not found — brew install xcodegen"; exit 1; }
	xcodegen generate
	@echo "✓ LLMAB.xcodeproj regenerated"

icon:
	./scripts/make-icon.sh

app: xcodeproj
	xcodebuild -project LLMAB.xcodeproj \
	    -scheme LLMABApp \
	    -configuration Debug \
	    -derivedDataPath build/DerivedData \
	    build

run-app: app
	open "build/DerivedData/Build/Products/Debug/LLMAB.app"

package:
	./scripts/package.sh

clean:
	swift package clean
	rm -rf .build build LLMAB.xcodeproj
