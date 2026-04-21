# ω — convenience wrappers around swift/xcodebuild for LLMAB.

.PHONY: build test lint cli run-app package clean

build:
	swift build -c debug

test:
	swift test --parallel

lint:
	swiftlint --strict

cli:
	swift build -c release --product llmab
	@echo "✓ swift run llmab models"

run-app:
	swift run LLMABApp

package:
	./scripts/package.sh

clean:
	swift package clean
	rm -rf .build build
